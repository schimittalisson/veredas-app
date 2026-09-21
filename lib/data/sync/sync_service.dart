import 'package:drift/drift.dart';

import 'package:veredas/core/error/app_exception.dart';
import 'package:veredas/core/error/error_mapper.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/sync/remote_source.dart';
import 'package:veredas/data/sync/sync_entity.dart';

/// Faz o *pull* incremental (ou fullReplace) do servidor para o cache local.
///
/// As telas leem do drift, não do Supabase. O SyncService é quem alimenta o
/// cache. A estratégia está em `docs/PLANO.md §2.5` e `docs/SCHEMA.md §"Estratégia de
/// sincronização por tabela"`.
///
/// **Janela de segurança de 2 minutos.** O pull incremental consulta
/// `updated_at > (lastSyncedAt - 2min)`. Isto cobre desvio de relógio entre
/// servidor e dispositivo: se o servidor está 1 minuto adiantado, uma linha
/// atualizada "agora" tem `updated_at` no futuro do ponto de vista do
/// dispositivo, e ficaria de fora de um filtro `> lastSyncedAt` exato. A
/// janela reprocessa essas linhas — o upsert é idempotente, então é inofensivo.
class SyncService {
  SyncService({required this.db, required this.remote});

  final AppDatabase db;
  final RemoteSource remote;

  /// Janela de segurança aplicada ao filtro `updated_at`.
  static const safetyWindow = Duration(minutes: 2);

  /// Sincroniza todas as entidades, em ordem de dependência (FKs primeiro).
  ///
  /// Para no primeiro erro: se a rede caiu, as entidades seguintes também
  /// falhariam. O chamador (trigger de sync) decide se mostra erro ou tenta
  /// de novo.
  Future<void> pullAll() async {
    for (final entity in syncEntities) {
      await pull(entity);
    }
  }

  /// Sincroniza uma entidade específica.
  ///
  /// Em caso de erro, grava `lastError` no `sync_state` (para diagnóstico) e
  /// re-lança a `AppException` — o chamador decide o que fazer.
  Future<void> pull(SyncEntity entity) async {
    try {
      await _doPull(entity);
      await _clearSyncError(entity.name);
    } catch (e) {
      final appError = e is AppException ? e : mapError(e);
      await _setSyncError(entity.name, appError.code.name);
      throw appError;
    }
  }

  Future<void> _doPull(SyncEntity entity) async {
    final state = await _getSyncState(entity.name);
    final lastSyncedAt = state?.lastSyncedAt;

    List<Map<String, dynamic>> rows;

    if (entity.mode == SyncMode.incremental) {
      // `lastSyncedAt == null` significa primeira sync: puxa tudo.
      // A janela de 2min é aplicada sempre, inclusive na primeira (onde é
      // inofensiva — não há lastSyncedAt para desviar).
      final cutoff = (lastSyncedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .subtract(safetyWindow);
      rows = await remote.fetch(
        table: entity.remoteTable,
        gtColumn: 'updated_at',
        gtValue: cutoff.toUtc().toIso8601String(),
        orderColumn: 'updated_at',
      );
    } else {
      // fullReplace: baixa tudo, sem filtro.
      rows = await remote.fetch(table: entity.remoteTable);
    }

    if (entity.mode == SyncMode.fullReplace) {
      // Transação: clear + insert devem ser atômicos. Se o app crashar depois
      // do clear, o cache fica vazio e a próxima sync re-popula — mas durante
      // o crash a tela mostra vazio, o que é pior do que mostrar dado antigo.
      // A transação garante que ou tudo é aplicado ou nada.
      await db.transaction(() async {
        await entity.clear(db);
        for (final j in rows) {
          // **Lápide nunca entra no cache, nem no fullReplace.**
          //
          // O desenho era o servidor filtrar: as policies de leitura destas
          // tabelas têm `deleted_at is null`, então a linha apagada só
          // desapareceria da resposta e o clear+repopula bastaria. Só que a
          // policy de escrita do admin é `for all`, e no Postgres o `using`
          // de uma policy `FOR ALL` **também vale para SELECT** — policies
          // permissivas se somam com OR. Para quem é admin, `is_admin()`
          // sozinho libera a leitura e o filtro de `deleted_at` da outra
          // policy deixa de importar.
          //
          // O efeito era um arquivo excluído que voltava a cada pull, **só na
          // tela do admin**: o `deleted_at` chegava preenchido e era gravado
          // como linha viva (o cache não tem essa coluna — ver `tables.dart`).
          // Quem não é admin nunca viu o problema, e por isso ele passou pelo
          // harness de RLS, que media a visibilidade pelo obreiro comum.
          //
          // Filtrar aqui é a correção certa mesmo que a policy mude: o cliente
          // não deve depender de o servidor lembrar de esconder a lápide.
          if (j['deleted_at'] != null) continue;
          await entity.upsert(db, j);
        }
        await _setSyncState(
          entity.name,
          _maxUpdatedAt(rows) ?? DateTime.now(),
        );
      });
    } else {
      // incremental: upserts idempotentes, sem transação. Se o app crashar
      // mid-sync, a próxima sync reprocessa as mesmas linhas (sync_state não
      // foi atualizado) — inofensivo.
      for (final j in rows) {
        // Linha com `deleted_at != null` foi apagada no servidor. O cache
        // local não guarda `deleted_at` (ver comentário em tables.dart): a
        // linha é removida fisicamente do cache, para que nenhuma query de
        // leitura precise lembrar de filtrar.
        if (j['deleted_at'] != null) {
          await entity.remove(db, j['id'] as String);
        } else {
          await entity.upsert(db, j);
        }
      }
      await _setSyncState(
        entity.name,
        _maxUpdatedAt(rows) ?? lastSyncedAt ?? DateTime.now(),
      );
    }
  }

  // --- sync_state helpers --------------------------------------------------

  Future<SyncStateRow?> _getSyncState(String entity) async {
    final result = await (db.select(db.syncStates)
          ..where((t) => t.entity.equals(entity)))
        .getSingleOrNull();
    return result;
  }

  Future<void> _setSyncState(String entity, DateTime lastSyncedAt) async {
    await db.into(db.syncStates).insertOnConflictUpdate(
          SyncStatesCompanion.insert(
            entity: entity,
            lastSyncedAt: Value(lastSyncedAt),
            lastError: const Value(null),
          ),
        );
  }

  Future<void> _clearSyncError(String entity) async {
    final existing = await _getSyncState(entity);
    if (existing != null && existing.lastError != null) {
      await (db.update(db.syncStates)..where((t) => t.entity.equals(entity)))
          .write(const SyncStatesCompanion(lastError: Value(null)));
    }
  }

  Future<void> _setSyncError(String entity, String error) async {
    await db.into(db.syncStates).insertOnConflictUpdate(
          SyncStatesCompanion.insert(
            entity: entity,
            lastError: Value(error),
          ),
        );
  }

  /// Extrai o maior `updated_at` das linhas recebidas.
  ///
  /// O PostgREST devolve `updated_at` como String ISO-8601. A comparação é
  /// lexicográfica (Strings ISO-8601 são ordenáveis), mas converter para
  /// `DateTime` é mais seguro — lida com variações de precisão (".123Z" vs
  /// "+00:00") que quebram a comparação de strings.
  DateTime? _maxUpdatedAt(List<Map<String, dynamic>> rows) {
    DateTime? max;
    for (final j in rows) {
      final raw = j['updated_at'];
      if (raw == null) continue;
      final dt = raw is DateTime ? raw : DateTime.parse(raw as String);
      if (max == null || dt.isAfter(max)) max = dt;
    }
    return max;
  }
}
