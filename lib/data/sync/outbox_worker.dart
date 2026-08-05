import 'dart:math' as math;

import 'package:drift/drift.dart';

import 'package:veredas/core/error/app_exception.dart';
import 'package:veredas/core/error/error_mapper.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/sync/remote_source.dart';
import 'package:veredas/data/sync/sync_entity.dart';

/// Drena a fila de escrita (outbox) enviando as operações pendentes ao
/// Supabase.
///
/// **Toda escrita do app passa pela outbox** (ver `AGENTS.md` §6 regra 8). O
/// repositório, numa transação drift única, aplica a mudança otimista no cache
/// e insere a entrada na outbox. A UI atualiza na hora porque a tela observa o
/// `Stream` do drift. O OutboxWorker envia ao servidor quando há conexão.
///
/// **Tratamento por tipo de falha** (`PLANO.md §2.5`):
///
/// | Falha | Ação |
/// |---|---|
/// | Rede/timeout/5xx | mantém na fila, retenta com backoff exponencial |
/// | 401/403 (RLS negou) | remove da fila, **reverte** o cache, emite erro |
/// | 409/constraint | remove da fila, reverte o cache, força pull da entidade |
/// | UPDATE/DELETE 0 linhas | remove da fila, reverte o cache (permissão ou linha sumiu) |
///
/// **O caso 0-linhas.** Um `UPDATE ... WHERE id = X` que não afeta nenhuma
/// linha devolve HTTP 200 com array vazio — não é erro. Mas significa que a
/// linha foi removida por outra pessoa, ou que o RLS filtrou a linha no
/// `USING` (a pessoa não tem acesso à linha). Os dois casos são
/// indistinguíveis. O tratamento é o mesmo: reverter o cache e remover da
/// fila. A mensagem ao usuário é `permissionDeniedOrStale`, não
/// `permissionDenied`, porque dizer "sem permissão" quando o item foi apagado
/// confunde (ver `app_exception.dart`).
class OutboxWorker {
  OutboxWorker({
    required this.db,
    required this.remote,
    this.isConnected = _defaultConnectivityCheck,
  });

  final AppDatabase db;
  final RemoteSource remote;

  /// Verificador de conectividade, injetado para testes. Em produção, usa
  /// `connectivity_plus` via o provider.
  final Future<bool> Function() isConnected;

  /// Drena a fila. Processa as entradas em ordem de `id` (ordem de inserção).
  ///
  /// Para na primeira falha retentável (rede/timeout/5xx): as entradas
  /// seguintes provavelmente também falhariam, e tentar todas é desperdício.
  /// Falhas permanentes (403/conflito/0-linhas) não interrompem o drain —
  /// cada entrada é independente.
  Future<void> drain() async {
    if (!await isConnected()) return;

    final entries = await _getPendingEntries();
    for (final entry in entries) {
      try {
        await _send(entry);
        await _deleteEntry(entry.id);
      } on AppException catch (e) {
        if (e.isRetryable) {
          await _scheduleRetry(entry, e);
          return; // rede provavelmente down — para o drain
        } else {
          await _rollbackAndRemove(entry, e);
          // continua para a próxima entrada
        }
      } catch (e) {
        // Exceção não-AppException (PostgrestException, SocketException etc.):
        // mapeia e trata como AppException.
        final appError = mapError(e);
        if (appError.isRetryable) {
          await _scheduleRetry(entry, appError);
          return;
        } else {
          await _rollbackAndRemove(entry, appError);
        }
      }
    }
  }

  // --- Envio ----------------------------------------------------------------

  Future<void> _send(OutboxRow entry) async {
    final entity = syncEntityByName(entry.entity);
    if (entity == null) {
      throw AppException(
        AppErrorCode.unknown,
        debugMessage: 'Entidade desconhecida na outbox: ${entry.entity}',
      );
    }

    final op = OutboxOp.values.byName(entry.op);
    final payload = decodePayload(entry.payload);

    switch (op) {
      case OutboxOp.insert:
        // INSERT não devolve linhas por padrão. Se houver conflito (23505),
        // o PostgREST lança PostgrestException → mapError → conflict →
        // requiresRollback.
        await remote.insert(
          table: entity.remoteTable,
          payload: payload,
        );

      case OutboxOp.update:
        // .select() devolve as linhas afetadas. Array vazio = 0 linhas
        // (linha sumiu ou RLS filtrou). Não é erro do PostgREST, mas é uma
        // negação implícita — tratamos como permissionDeniedOrStale.
        final result = await remote.update(
          table: entity.remoteTable,
          payload: payload,
          eqColumn: entity.eqColumn,
          eqValue: entry.rowId,
        );
        if (result.isEmpty) {
          throw const AppException(AppErrorCode.permissionDeniedOrStale);
        }

      case OutboxOp.delete:
        // Mesma lógica do update: 0 linhas = linha já não existia ou RLS
        // filtrou. Para delete, "linha já não existia" é idempotente — o
        // resultado desejado (linha apagada) já é o estado do servidor. Mas
        // não podemos distinguir de "RLS negou", e tratar como sucesso quando
        // o RLS negou deixaria o cache local sem a linha enquanto o servidor
        // ainda a tem. Então tratamos como negação e revertemos.
        final result = await remote.delete(
          table: entity.remoteTable,
          eqColumn: entity.eqColumn,
          eqValue: entry.rowId,
        );
        if (result.isEmpty) {
          throw const AppException(AppErrorCode.permissionDeniedOrStale);
        }
    }
  }

  // --- Rollback -------------------------------------------------------------

  /// Reverte o cache otimista e remove a entrada da fila.
  ///
  /// O `previousRow` é um snapshot drift JSON (`row.toJson()`) da linha antes
  /// da mudança. Para insert, não há previousRow — a linha não existia, então
  /// basta removê-la. Para update/delete, o previousRow é restaurado.
  Future<void> _rollbackAndRemove(OutboxRow entry, AppException e) async {
    final entity = syncEntityByName(entry.entity);
    if (entity == null) return; // não deveria acontecer — _send já validou

    final op = OutboxOp.values.byName(entry.op);
    final previous = decodePreviousRow(entry.previousRow);

    await db.transaction(() async {
      switch (op) {
        case OutboxOp.insert:
          // A inserção foi recusada. A linha otimista precisa sair do cache.
          await entity.remove(db, entry.rowId);

        case OutboxOp.update:
          // A atualização foi recusada. Restaura o snapshot anterior.
          if (previous != null) {
            await entity.restore(db, previous);
          } else {
            // Sem snapshot: não deveria acontecer para um update, mas como
            // fallback remove a linha (estado "não existe" é mais seguro que
            // estado "dado que o servidor recusou").
            await entity.remove(db, entry.rowId);
          }

        case OutboxOp.delete:
          // A exclusão foi recusada. Restaura a linha que tentamos apagar.
          if (previous != null) {
            await entity.restore(db, previous);
          }
          // Se não há previousRow, a linha não existia localmente antes do
          // delete — nada a reverter.
      }

      // Remove a entrada da fila.
      await _deleteEntry(entry.id);
    });

    // Registra o erro no sync_state para diagnóstico.
    await _setSyncError(entry.entity, e.code.name);
  }

  // --- Backoff --------------------------------------------------------------

  /// Calcula o atraso da próxima tentativa.
  ///
  /// Backoff exponencial: 2^attempts segundos, capado em 256s (~4min).
  /// - attempts 0 (primeira falha): 1s
  /// - attempts 1: 2s
  /// - attempts 2: 4s
  /// - ...
  /// - attempts 8+: 256s
  static Duration backoffDelay(int attempts) {
    final seconds = 1 << math.min(attempts, 8);
    return Duration(seconds: seconds);
  }

  Future<void> _scheduleRetry(OutboxRow entry, AppException e) async {
    final nextAttempts = entry.attempts + 1;
    final nextAttemptAt = DateTime.now().add(backoffDelay(entry.attempts));

    await (db.update(db.outboxEntries)..where((t) => t.id.equals(entry.id)))
        .write(
      OutboxEntriesCompanion(
        attempts: Value(nextAttempts),
        nextAttemptAt: Value(nextAttemptAt),
        lastError: Value(e.code.name),
      ),
    );
  }

  // --- Queries drift --------------------------------------------------------

  /// Entradas prontas para envio: `nextAttemptAt is null` (nunca tentou) ou
  /// `nextAttemptAt <= agora`, em ordem de `id` (inserção).
  Future<List<OutboxRow>> _getPendingEntries() async {
    final now = DateTime.now();
    final query = db.select(db.outboxEntries)
      ..orderBy([(t) => OrderingTerm.asc(t.id)])
      ..where((t) =>
          t.nextAttemptAt.isNull() | t.nextAttemptAt.isSmallerOrEqualValue(now));
    return query.get();
  }

  Future<void> _deleteEntry(int id) async {
    await (db.delete(db.outboxEntries)..where((t) => t.id.equals(id))).go();
  }

  Future<void> _setSyncError(String entity, String error) async {
    await db.into(db.syncStates).insertOnConflictUpdate(
          SyncStatesCompanion.insert(
            entity: entity,
            lastError: Value(error),
          ),
        );
  }

  /// Verifica se há entradas pendentes na outbox.
  Future<bool> hasPending() async {
    final count = await db.outboxEntries.count().getSingle();
    return count > 0;
  }

  /// Stream que emite `true` quando há entradas pendentes. Usado pelo
  /// `syncStatusProvider` para mostrar "sincronizando…" na UI.
  Stream<bool> watchPending() {
    // `count().watchSingle()` emite `Stream<int>` — o count da tabela inteira.
    return db.outboxEntries.count().watchSingle().map((c) => c > 0);
  }
}

Future<bool> _defaultConnectivityCheck() async {
  // Em produção, o provider injeta uma implementação com connectivity_plus.
  // O default assume conectado — o Supabase vai falhar com noConnection se
  // não houver rede, e o item volta para a fila com backoff.
  return true;
}
