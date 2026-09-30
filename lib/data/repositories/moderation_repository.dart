import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/local/tables.dart' show hiddenAuthorId;
import 'package:veredas/data/models/report_reason.dart';
import 'package:veredas/data/repositories/outbox_helper.dart';

/// Denúncia de pedido de oração e bloqueio de usuário (App Store, Guideline
/// 1.2). Escrita pela outbox, como o resto do app: denunciar e bloquear
/// precisam valer na hora, mesmo sem sinal — o post some do feed no toque.
class ModerationRepository {
  ModerationRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  /// Denuncia um post. Devolve `false` se a pessoa já o tinha denunciado.
  ///
  /// A checagem local evita o 23505 do índice único
  /// `content_reports_unique_idx`: sem ela, a segunda denúncia sairia
  /// otimista, voltaria como conflito e seria revertida com uma mensagem de
  /// erro para algo que não é erro.
  Future<bool> reportPost({
    required String postId,
    required String reporterId,
    required ReportReason reason,
  }) async {
    final existing = await (_db.select(_db.contentReportRows)
          ..where(
            (t) => t.postId.equals(postId) & t.reporterId.equals(reporterId),
          ))
        .getSingleOrNull();
    if (existing != null) return false;

    final post = await (_db.select(_db.prayerFeedRows)
          ..where((t) => t.id.equals(postId)))
        .getSingleOrNull();
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();

    await OutboxHelper.insert(
      db: _db,
      entity: 'content_reports',
      rowId: id,
      // Só o que o servidor aceita do app. A cópia do post é o trigger
      // `fill_report_snapshot` que tira, da linha real.
      payload: {
        'id': id,
        'reporter_id': reporterId,
        'post_id': postId,
        'reason': reason.wire,
      },
      applyChange: () async {
        // A cópia local é só para o cache ter a linha completa até o próximo
        // pull trazer a versão do servidor.
        await _db.into(_db.contentReportRows).insert(
              ContentReportRowsCompanion.insert(
                id: id,
                reporterId: reporterId,
                postId: postId,
                reason: reason.wire,
                postTitle: Value(post?.title),
                postBody: Value(post?.body),
                postAuthorId: Value(post?.authorId),
                postIsAnonymous: Value(post?.isAnonymous ?? false),
                createdAt: now,
                updatedAt: now,
              ),
            );
      },
    );
    return true;
  }

  /// Marca a denúncia como resolvida (só admin — a policy recusa os outros).
  Future<void> resolveReport({
    required String reportId,
    required String resolvedBy,
  }) async {
    final now = DateTime.now().toUtc();

    await OutboxHelper.update(
      db: _db,
      entity: 'content_reports',
      rowId: reportId,
      payload: {
        'resolved_at': now.toIso8601String(),
        'resolved_by': resolvedBy,
      },
      applyChange: () async {
        await (_db.update(_db.contentReportRows)
              ..where((t) => t.id.equals(reportId)))
            .write(ContentReportRowsCompanion(
          resolvedAt: Value(now),
          updatedAt: Value(now),
        ));
      },
      queryExisting: () async {
        final row = await (_db.select(_db.contentReportRows)
              ..where((t) => t.id.equals(reportId)))
            .getSingleOrNull();
        return row?.toJson();
      },
    );
  }

  /// Bloqueia [blockedId]. Não faz nada se já estava bloqueado, nem se o
  /// autor é o [hiddenAuthorId] de um pedido anônimo — a FK recusaria no
  /// servidor, e a tela já não oferece bloquear nesse caso.
  Future<void> blockUser({
    required String blockerId,
    required String blockedId,
  }) async {
    if (blockedId == hiddenAuthorId) return;
    final existing = await (_db.select(_db.userBlockRows)
          ..where((t) => t.blockedId.equals(blockedId)))
        .getSingleOrNull();
    if (existing != null) return;

    await OutboxHelper.insert(
      db: _db,
      entity: 'user_blocks',
      rowId: blockedId,
      payload: {
        'blocker_id': blockerId,
        'blocked_id': blockedId,
      },
      applyChange: () async {
        await _db.into(_db.userBlockRows).insert(
              UserBlockRowsCompanion.insert(
                blockedId: blockedId,
                createdAt: DateTime.now().toUtc(),
              ),
            );
      },
    );
  }

  /// Desfaz o bloqueio. Os posts da pessoa voltam ao feed no próximo pull —
  /// o cache não os guardou enquanto ela esteve bloqueada.
  Future<void> unblockUser(String blockedId) async {
    await OutboxHelper.delete(
      db: _db,
      entity: 'user_blocks',
      rowId: blockedId,
      applyChange: () async {
        await (_db.delete(_db.userBlockRows)
              ..where((t) => t.blockedId.equals(blockedId)))
            .go();
      },
      queryExisting: () async {
        final row = await (_db.select(_db.userBlockRows)
              ..where((t) => t.blockedId.equals(blockedId)))
            .getSingleOrNull();
        return row?.toJson();
      },
    );
  }
}
