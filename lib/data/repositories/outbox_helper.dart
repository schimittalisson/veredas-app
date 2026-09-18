import 'package:drift/drift.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/sync/sync_entity.dart';

/// Helper para a transação otimista+outbox que toda escrita do app usa.
///
/// O padrão (docs/PLANO.md §2.5): numa **única transação drift**, o repositório
/// aplica a mudança no cache local (a UI atualiza na hora via Stream) e insere
/// a entrada na outbox. O `OutboxWorker` envia ao servidor depois.
///
/// Sem isto, uma escrita offline seria duas operações separadas: se o app
/// crashasse entre aplicar o cache e inserir na outbox, a UI mostraria um dado
/// que nunca chegaria ao servidor — e o usuário não saberia.
class OutboxHelper {
  const OutboxHelper._();

  /// Executa uma escrita otimista numa transação.
  ///
  /// [entity] — nome da entidade em `sync_entity.dart` (ex.: 'announcements').
  /// [op] — insert, update ou delete.
  /// [rowId] — id da linha afetada (UUID, ou "scaleTypeId|userId" para PK
  /// composta).
  /// [payload] — corpo JSON enviado ao servidor (formato PostgREST:
  /// snake_case, ISO strings). Para delete, pode ser vazio.
  /// [applyChange] — aplica a mudança otimista no cache (ex.: insertOnConflictUpdate).
  /// [capturePrevious] — devolve o snapshot da linha antes da mudança, para
  /// rollback. Para insert, devolve null. Para update/delete, devolve
  /// `row.toJson()` da linha atual (ou null se não existe).
  static Future<void> write({
    required AppDatabase db,
    required String entity,
    required OutboxOp op,
    required String rowId,
    required Map<String, dynamic> payload,
    required Future<void> Function() applyChange,
    required Future<Map<String, dynamic>?> Function() capturePrevious,
  }) async {
    await db.transaction(() async {
      // 1. Captura o estado anterior (para rollback).
      final previousRow = await capturePrevious();

      // 2. Aplica a mudança otimista no cache.
      await applyChange();

      // 3. Insere na outbox.
      await db.into(db.outboxEntries).insert(
            OutboxEntriesCompanion.insert(
              entity: entity,
              op: op.name,
              rowId: rowId,
              payload: encodePayload(payload),
              previousRow: previousRow != null
                  ? Value(_encodeDriftJson(previousRow))
                  : const Value.absent(),
              createdAt: DateTime.now(),
            ),
          );
    });
  }

  /// Atalho para insert: não há estado anterior.
  static Future<void> insert({
    required AppDatabase db,
    required String entity,
    required String rowId,
    required Map<String, dynamic> payload,
    required Future<void> Function() applyChange,
  }) {
    return write(
      db: db,
      entity: entity,
      op: OutboxOp.insert,
      rowId: rowId,
      payload: payload,
      applyChange: applyChange,
      capturePrevious: () async => null,
    );
  }

  /// Atalho para update: captura o estado anterior da linha pelo id.
  ///
  /// [queryExisting] — busca a linha atual no cache (ex.:
  /// `db.select(db.announcementRows)..where((t) => t.id.equals(id))`).
  /// Devolve `row.toJson()` ou null se a linha não existe.
  static Future<void> update({
    required AppDatabase db,
    required String entity,
    required String rowId,
    required Map<String, dynamic> payload,
    required Future<void> Function() applyChange,
    required Future<Map<String, dynamic>?> Function() queryExisting,
  }) {
    return write(
      db: db,
      entity: entity,
      op: OutboxOp.update,
      rowId: rowId,
      payload: payload,
      applyChange: applyChange,
      capturePrevious: queryExisting,
    );
  }

  /// Atalho para delete: captura o estado anterior e remove do cache.
  static Future<void> delete({
    required AppDatabase db,
    required String entity,
    required String rowId,
    required Future<void> Function() applyChange,
    required Future<Map<String, dynamic>?> Function() queryExisting,
  }) {
    return write(
      db: db,
      entity: entity,
      op: OutboxOp.delete,
      rowId: rowId,
      payload: const {},
      applyChange: applyChange,
      capturePrevious: queryExisting,
    );
  }

  /// Serializa drift JSON para a coluna `previousRow`.
  ///
  /// O `row.toJson()` do drift devolve um `Map` onde `DateTime` é `int` (ms
  /// desde epoch) e `List<String>` é `List` — o `RowClass.fromJson()` faz o
  /// inverso. O `jsonEncode` precisa de tipos primitivos, e os valores do
  /// drift já são primitivos (int, String, bool, List), então funciona direto.
  static String _encodeDriftJson(Map<String, dynamic> json) {
    // O drift toJson já devolve tipos serializáveis. Só precisa do jsonEncode.
    return encodePayload(json);
  }
}
