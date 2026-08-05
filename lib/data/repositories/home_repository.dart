import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/repositories/outbox_helper.dart';

/// Repositório da tela Início — escrita de avisos e dados da base.
///
/// Toda escrita passa pelo `OutboxHelper`: aplica a mudança otimista no cache
/// (a UI atualiza na hora via Stream) e enfileira na outbox para envio ao
/// servidor quando houver conexão.
///
/// O `authorId` dos avisos é preenchido pelo servidor (RLS exige
/// `author_id = auth.uid()` ou `is_admin()`), não pelo cliente — o PostgREST
/// pode omiti-lo no payload e o default/trigger do banco preenche.
class HomeRepository {
  HomeRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  // --- Announcements --------------------------------------------------------

  /// Cria um aviso. O id é gerado no cliente (UUID v4).
  Future<String> createAnnouncement({
    required String body,
    String? title,
    bool pinned = false,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();

    await OutboxHelper.insert(
      db: _db,
      entity: 'announcements',
      rowId: id,
      payload: {
        'id': id,
        'title': title,
        'body': body,
        'pinned': pinned,
        // author_id é definido pelo servidor (RLS). Não enviar para evitar
        // que o cliente forje a autoria.
      },
      applyChange: () async {
        await _db.into(_db.announcementRows).insertOnConflictUpdate(
              AnnouncementRow(
                id: id,
                title: title,
                body: body,
                pinned: pinned,
                createdAt: now,
                updatedAt: now,
              ),
            );
      },
    );

    return id;
  }

  /// Edita um aviso existente.
  Future<void> updateAnnouncement({
    required String id,
    String? title,
    required String body,
    bool pinned = false,
  }) async {
    await OutboxHelper.update(
      db: _db,
      entity: 'announcements',
      rowId: id,
      payload: {
        'title': title,
        'body': body,
        'pinned': pinned,
      },
      applyChange: () async {
        final existing = await (_db.select(_db.announcementRows)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        if (existing == null) return;

        await _db.into(_db.announcementRows).insertOnConflictUpdate(
              existing.copyWith(
                title: Value(title),
                body: body,
                pinned: pinned,
                updatedAt: DateTime.now().toUtc(),
              ),
            );
      },
      queryExisting: () async {
        final row = await (_db.select(_db.announcementRows)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        return row?.toJson();
      },
    );
  }

  /// Remove um aviso (soft delete no servidor).
  Future<void> deleteAnnouncement(String id) async {
    await OutboxHelper.delete(
      db: _db,
      entity: 'announcements',
      rowId: id,
      applyChange: () async {
        await (_db.delete(_db.announcementRows)
              ..where((t) => t.id.equals(id)))
            .go();
      },
      queryExisting: () async {
        final row = await (_db.select(_db.announcementRows)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        return row?.toJson();
      },
    );
  }

  // --- Base info ------------------------------------------------------------

  /// Atualiza um item de "Dados da base".
  Future<void> updateBaseInfo({
    required String id,
    required String value,
  }) async {
    await OutboxHelper.update(
      db: _db,
      entity: 'base_info',
      rowId: id,
      payload: {'value': value},
      applyChange: () async {
        final existing = await (_db.select(_db.baseInfoRows)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        if (existing == null) return;

        await _db.into(_db.baseInfoRows).insertOnConflictUpdate(
              existing.copyWith(
                value: value,
                updatedAt: DateTime.now().toUtc(),
              ),
            );
      },
      queryExisting: () async {
        final row = await (_db.select(_db.baseInfoRows)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        return row?.toJson();
      },
    );
  }
}
