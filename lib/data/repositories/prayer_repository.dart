import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/repositories/outbox_helper.dart';

/// Repositório do mural de oração — escrita de posts e toggle de "orando".
///
/// O cache local espelha a **view** `prayer_feed`, não a tabela `prayer_posts`.
/// Escritas de posts ajustam o cache da view otimistamente e enfileiram na
/// outbox o INSERT/UPDATE/DELETE na tabela `prayer_posts` remota.
///
/// O toggle de "estou orando" é especial: `prayer_interactions` não é cacheada
/// (é DELETE físico). O toggle ajusta `prayingCount`/`isPraying` direto na
/// linha do feed e enfileira um INSERT ou DELETE em `prayer_interactions`.
/// O próximo pull `fullReplace` da view `prayer_feed` corrige qualquer
/// divergência entre o contador otimista e o real.
class PrayerRepository {
  PrayerRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  // --- Prayer posts ---------------------------------------------------------

  /// Cria um pedido de oração.
  ///
  /// [authorId], [authorName], [authorAvatarUrl] são do usuário atual —
  /// passados pela UI a partir do `currentProfileProvider`. O servidor
  /// define `author_id` via RLS (`author_id = auth.uid()`), mas o cache
  /// otimista precisa do valor para exibir imediatamente.
  Future<String> createPost({
    required String title,
    required String body,
    bool isAnonymous = false,
    required String authorId,
    String? authorName,
    String? authorAvatarUrl,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();

    await OutboxHelper.insert(
      db: _db,
      entity: 'prayer_feed',
      rowId: id,
      payload: {
        'id': id,
        'title': title,
        'body': body,
        'is_anonymous': isAnonymous,
        // author_id é validado pelo servidor (RLS: author_id = auth.uid()).
        // Enviar para garantir que o INSERT não falhe na validação.
        'author_id': authorId,
      },
      applyChange: () async {
        await _db.into(_db.prayerFeedRows).insertOnConflictUpdate(
              PrayerFeedRow(
                id: id,
                authorId: authorId,
                title: title,
                body: body,
                isAnonymous: isAnonymous,
                authorName: isAnonymous ? null : authorName,
                authorAvatarUrl: isAnonymous ? null : authorAvatarUrl,
                prayingCount: 0,
                commentCount: 0,
                isPraying: false,
                createdAt: now,
                updatedAt: now,
              ),
            );
      },
    );

    return id;
  }

  /// Edita um pedido de oração.
  Future<void> updatePost({
    required String id,
    required String title,
    required String body,
    bool isAnonymous = false,
  }) async {
    await OutboxHelper.update(
      db: _db,
      entity: 'prayer_feed',
      rowId: id,
      payload: {
        'title': title,
        'body': body,
        'is_anonymous': isAnonymous,
      },
      applyChange: () async {
        final existing = await (_db.select(_db.prayerFeedRows)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        if (existing == null) return;

        await _db.into(_db.prayerFeedRows).insertOnConflictUpdate(
              existing.copyWith(
                title: title,
                body: body,
                isAnonymous: isAnonymous,
                // Se ficou anônimo, limpa os dados do autor no cache.
                authorName: isAnonymous
                    ? const Value(null)
                    : Value(existing.authorName),
                authorAvatarUrl: isAnonymous
                    ? const Value(null)
                    : Value(existing.authorAvatarUrl),
                updatedAt: DateTime.now().toUtc(),
              ),
            );
      },
      queryExisting: () async {
        final row = await (_db.select(_db.prayerFeedRows)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        return row?.toJson();
      },
    );
  }

  /// Marca um pedido como respondido.
  Future<void> markAnswered({
    required String id,
    String? answerNote,
  }) async {
    final now = DateTime.now().toUtc();

    await OutboxHelper.update(
      db: _db,
      entity: 'prayer_feed',
      rowId: id,
      payload: {
        'answered_at': now.toIso8601String(),
        'answer_note': ?answerNote,
      },
      applyChange: () async {
        final existing = await (_db.select(_db.prayerFeedRows)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        if (existing == null) return;

        await _db.into(_db.prayerFeedRows).insertOnConflictUpdate(
              existing.copyWith(
                answeredAt: Value(now),
                answerNote: Value(answerNote),
                updatedAt: now,
              ),
            );
      },
      queryExisting: () async {
        final row = await (_db.select(_db.prayerFeedRows)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        return row?.toJson();
      },
    );
  }

  /// Remove um pedido de oração (soft delete no servidor).
  Future<void> deletePost(String id) async {
    await OutboxHelper.delete(
      db: _db,
      entity: 'prayer_feed',
      rowId: id,
      applyChange: () async {
        await (_db.delete(_db.prayerFeedRows)
              ..where((t) => t.id.equals(id)))
            .go();
      },
      queryExisting: () async {
        final row = await (_db.select(_db.prayerFeedRows)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        return row?.toJson();
      },
    );
  }

  // --- Prayer interactions (toggle "estou orando") --------------------------

  /// Alterna o estado de "estou orando" num pedido.
  ///
  /// Como `prayer_interactions` não é cacheada, o toggle:
  /// 1. Ajusta `prayingCount` e `isPraying` otimistamente na linha do feed.
  /// 2. Enfileira um INSERT (se estava orando) ou DELETE (se parou) em
  ///    `prayer_interactions` na outbox.
  ///
  /// O `prayer_feed` é `fullReplace`, então o próximo pull corrige qualquer
  /// divergência entre o contador otimista e o real.
  Future<void> togglePraying({
    required String postId,
    required String userId,
  }) async {
    final row = await (_db.select(_db.prayerFeedRows)
          ..where((t) => t.id.equals(postId)))
        .getSingleOrNull();
    if (row == null) return;

    final isNowPraying = !row.isPraying;

    if (isNowPraying) {
      // INSERT em prayer_interactions.
      await OutboxHelper.insert(
        db: _db,
        entity: 'prayer_interactions',
        rowId: postId,
        payload: {
          'post_id': postId,
          'user_id': userId,
        },
        applyChange: () async {
          await _db.into(_db.prayerFeedRows).insertOnConflictUpdate(
                row.copyWith(
                  isPraying: true,
                  prayingCount: row.prayingCount + 1,
                ),
              );
        },
      );
    } else {
      // DELETE em prayer_interactions. O rowId é o postId — o OutboxWorker
      // usa eqColumn = 'post_id' (configurado no SyncEntity). O RLS garante
      // que só a interação do próprio usuário (user_id = auth.uid()) é
      // deletada.
      await OutboxHelper.delete(
        db: _db,
        entity: 'prayer_interactions',
        rowId: postId,
        applyChange: () async {
          await _db.into(_db.prayerFeedRows).insertOnConflictUpdate(
                row.copyWith(
                  isPraying: false,
                  prayingCount: row.prayingCount - 1,
                ),
              );
        },
        queryExisting: () async => null, // não há cache de prayer_interactions
      );
    }
  }
}
