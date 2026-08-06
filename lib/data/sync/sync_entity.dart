import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/models/app_role.dart';

/// Modo de sincronização de uma entidade.
///
/// [incremental] — pull por `updated_at > lastSyncedAt - 2min`, com soft delete
/// (linhas com `deleted_at != null` são removidas do cache). É eficiente para
/// tabelas que crescem, mas só funciona quando o servidor nunca faz `DELETE`
/// físico — senão uma remoção é invisível ao incremental.
///
/// [fullReplace] — a cada sync, apaga tudo do cache local e re-insere as linhas
/// vindas do servidor. É trivial e sempre correto, mas baixa a tabela inteira a
/// cada vez. Adequado para tabelas pequenas que sofrem `DELETE` físico.
enum SyncMode { incremental, fullReplace }

/// Operação guardada na outbox. Os valores são strings minúsculas, idênticas
/// ao que vai na coluna `op` — `byName` faz a conversão.
enum OutboxOp { insert, update, delete }

/// Descrição declarativa de uma entidade sincronizada.
///
/// Cada entidade registra:
/// - [name]: identificador usado em `sync_state` e `outbox.entity`.
/// - [remoteTable]: nome da tabela/view no Supabase (PostgREST).
/// - [mode]: estratégia de sync.
/// - [order]: ordem de sincronização (FKs primeiro). Não é estritamente
///   necessário porque o drift não declara FKs entre tabelas de cache, mas
///   mantém consistência lógica — um `scale_assignment` não deveria aparecer
///   antes do seu `scale_type`.
/// - [upsert]: converte JSON do Supabase (snake_case, ISO strings) e faz
///   `insertOnConflictUpdate` no drift.
/// - [remove]: apaga a linha local pelo id.
/// - [clear]: apaga todas as linhas locais (usado no `fullReplace`).
/// - [restore]: reconstrói uma linha a partir do snapshot drift JSON
///   (`row.toJson()`) — usado pelo `OutboxWorker` para reverter o cache
///   otimista quando o servidor recusa a escrita.
class SyncEntity {
  final String name;
  final String remoteTable;
  final SyncMode mode;
  final int order;

  /// Coluna usada pelo OutboxWorker para filtrar UPDATE/DELETE.
  /// Default: `'id'`. Entidades com PK composta ou chave diferente
  /// (ex.: `prayer_interactions` filtra por `post_id`) precisam sobrescrever.
  final String eqColumn;

  final Future<void> Function(AppDatabase db, Map<String, dynamic> json) upsert;
  final Future<void> Function(AppDatabase db, String id) remove;
  final Future<void> Function(AppDatabase db) clear;
  final Future<void> Function(AppDatabase db, Map<String, dynamic> driftJson)
      restore;

  const SyncEntity({
    required this.name,
    required this.remoteTable,
    required this.mode,
    required this.order,
    required this.upsert,
    required this.remove,
    required this.clear,
    required this.restore,
    this.eqColumn = 'id',
  });
}

// ---------------------------------------------------------------------------
// Helpers de conversão — JSON do PostgREST para tipos Dart.
//
// O PostgREST devolve:
// - text, uuid: String
// - timestamptz: String ISO-8601 (ex.: "2026-08-04T12:00:00+00:00")
// - date: String "YYYY-MM-DD"
// - time: String "HH:MM:SS"
// - boolean: bool
// - integer, smallint: int
// - text[]: List<String>
// ---------------------------------------------------------------------------

DateTime? _dt(dynamic j) {
  if (j == null) return null;
  if (j is DateTime) return j;
  return DateTime.parse(j as String);
}

DateTime _dtReq(dynamic j) {
  if (j is DateTime) return j;
  return DateTime.parse(j as String);
}

bool _bool(dynamic j, {bool d = false}) {
  if (j is bool) return j;
  if (j == null) return d;
  return d;
}

int _intReq(dynamic j, {int d = 0}) {
  if (j is int) return j;
  if (j is String) return int.tryParse(j) ?? d;
  return d;
}

/// Inteiro opcional. Distingue "veio nulo" de "veio zero" — em `color_index`,
/// nulo significa "sem cor escolhida" e 0 é a primeira cor da paleta.
int? _int(dynamic j) {
  if (j == null) return null;
  if (j is int) return j;
  if (j is String) return int.tryParse(j);
  return null;
}

/// "06:00:00" ou "06:00:00.123456" → 360 (minutos desde meia-noite).
int _timeToMinutes(dynamic j) {
  if (j is int) return j;
  final s = j as String;
  final parts = s.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

int? _timeToMinutesOpt(dynamic j) {
  if (j == null) return null;
  return _timeToMinutes(j);
}

List<String> _strList(dynamic j) {
  if (j == null) return const [];
  if (j is List) return j.map((e) => e.toString()).toList(growable: false);
  return const [];
}

// ---------------------------------------------------------------------------
// Conversores por entidade.
//
// Cada par upsert/remove/clear/restore fecha o ciclo:
//
//   pull (servidor → cache)     → upsert / remove
//   fullReplace (servidor → cache) → clear + upsert
//   rollback (outbox → cache)   → restore / remove
//
// O `restore` usa `RowClass.fromJson(driftJson)`, que é o inverso de
// `row.toJson()`. O drift serializa DateTime como int (ms desde epoch) e
// List<String> via o JsonTypeConverter2 do StringListConverter — o round-trip
// é exato.
// ---------------------------------------------------------------------------

Future<void> _upsertProfile(AppDatabase db, Map<String, dynamic> j) async {
  await db.into(db.profileRows).insertOnConflictUpdate(
        ProfileRow(
          id: j['id'] as String,
          fullName: j['full_name'] as String,
          email: j['email'] as String?,
          phone: j['phone'] as String?,
          avatarUrl: j['avatar_url'] as String?,
          bio: j['bio'] as String?,
          role: AppRole.fromWire(j['role'] as String?),
          isApproved: _bool(j['is_approved']),
          createdAt: _dt(j['created_at']),
          updatedAt: _dtReq(j['updated_at']),
        ),
      );
}

Future<void> _removeProfile(AppDatabase db, String id) async {
  await (db.delete(db.profileRows)..where((t) => t.id.equals(id))).go();
}

Future<void> _clearProfile(AppDatabase db) async {
  await db.delete(db.profileRows).go();
}

Future<void> _restoreProfile(AppDatabase db, Map<String, dynamic> j) async {
  await db.into(db.profileRows).insertOnConflictUpdate(
        ProfileRow.fromJson(j),
      );
}

// --- invites ---------------------------------------------------------------

Future<void> _upsertInvite(AppDatabase db, Map<String, dynamic> j) async {
  await db.into(db.inviteRows).insertOnConflictUpdate(
        InviteRow(
          id: j['id'] as String,
          code: j['code'] as String,
          role: AppRole.fromWire(j['role'] as String?),
          note: j['note'] as String?,
          maxUses: _intReq(j['max_uses'], d: 1),
          uses: _intReq(j['uses']),
          expiresAt: _dt(j['expires_at']),
          revokedAt: _dt(j['revoked_at']),
          createdBy: j['created_by'] as String?,
          createdAt: _dt(j['created_at']),
          updatedAt: _dtReq(j['updated_at']),
        ),
      );
}

Future<void> _removeInvite(AppDatabase db, String id) async {
  await (db.delete(db.inviteRows)..where((t) => t.id.equals(id))).go();
}

Future<void> _clearInvite(AppDatabase db) async {
  await db.delete(db.inviteRows).go();
}

Future<void> _restoreInvite(AppDatabase db, Map<String, dynamic> j) async {
  await db.into(db.inviteRows).insertOnConflictUpdate(InviteRow.fromJson(j));
}

// --- scale_types -----------------------------------------------------------

Future<void> _upsertScaleType(AppDatabase db, Map<String, dynamic> j) async {
  await db.into(db.scaleTypeRows).insertOnConflictUpdate(
        ScaleTypeRow(
          id: j['id'] as String,
          slug: j['slug'] as String,
          name: j['name'] as String,
          description: j['description'] as String?,
          icon: j['icon'] as String?,
          cadence: (j['cadence'] as String?) ?? 'weekly',
          slots: _strList(j['slots']),
          ordering: _intReq(j['ordering']),
          isActive: _bool(j['is_active'], d: true),
          updatedAt: _dtReq(j['updated_at']),
        ),
      );
}

Future<void> _removeScaleType(AppDatabase db, String id) async {
  await (db.delete(db.scaleTypeRows)..where((t) => t.id.equals(id))).go();
}

Future<void> _clearScaleType(AppDatabase db) async {
  await db.delete(db.scaleTypeRows).go();
}

Future<void> _restoreScaleType(AppDatabase db, Map<String, dynamic> j) async {
  await db.into(db.scaleTypeRows)
      .insertOnConflictUpdate(ScaleTypeRow.fromJson(j));
}

// --- scale_managers (fullReplace, PK composta) -----------------------------
//
// O `remove` recebe o rowId no formato "scaleTypeId|userId" — é assim que o
// repositório codifica a PK composta ao criar a entrada da outbox. O SyncService
// nunca chama `remove` para fullReplace, mas o OutboxWorker chama para reverter
// um insert recusado.

Future<void> _upsertScaleManager(AppDatabase db, Map<String, dynamic> j) async {
  await db.into(db.scaleManagerRows).insertOnConflictUpdate(
        ScaleManagerRow(
          scaleTypeId: j['scale_type_id'] as String,
          userId: j['user_id'] as String,
          updatedAt: _dt(j['updated_at']),
        ),
      );
}

Future<void> _removeScaleManager(AppDatabase db, String rowId) async {
  final parts = rowId.split('|');
  await (db.delete(db.scaleManagerRows)
        ..where(
          (t) => t.scaleTypeId.equals(parts[0]) & t.userId.equals(parts[1]),
        ))
      .go();
}

Future<void> _clearScaleManager(AppDatabase db) async {
  await db.delete(db.scaleManagerRows).go();
}

Future<void> _restoreScaleManager(AppDatabase db, Map<String, dynamic> j) async {
  await db.into(db.scaleManagerRows)
      .insertOnConflictUpdate(ScaleManagerRow.fromJson(j));
}

// --- scale_assignments -----------------------------------------------------

Future<void> _upsertScaleAssignment(
  AppDatabase db,
  Map<String, dynamic> j,
) async {
  await db.into(db.scaleAssignmentRows).insertOnConflictUpdate(
        ScaleAssignmentRow(
          id: j['id'] as String,
          scaleTypeId: j['scale_type_id'] as String,
          startsOn: _dtReq(j['starts_on']),
          endsOn: _dt(j['ends_on']),
          slot: j['slot'] as String?,
          task: j['task'] as String?,
          assigneeId: j['assignee_id'] as String?,
          assigneeName: j['assignee_name'] as String?,
          notes: j['notes'] as String?,
          createdBy: j['created_by'] as String?,
          updatedAt: _dtReq(j['updated_at']),
        ),
      );
}

Future<void> _removeScaleAssignment(AppDatabase db, String id) async {
  await (db.delete(db.scaleAssignmentRows)..where((t) => t.id.equals(id))).go();
}

Future<void> _clearScaleAssignment(AppDatabase db) async {
  await db.delete(db.scaleAssignmentRows).go();
}

Future<void> _restoreScaleAssignment(
  AppDatabase db,
  Map<String, dynamic> j,
) async {
  await db.into(db.scaleAssignmentRows)
      .insertOnConflictUpdate(ScaleAssignmentRow.fromJson(j));
}

// --- events ----------------------------------------------------------------

Future<void> _upsertEvent(AppDatabase db, Map<String, dynamic> j) async {
  await db.into(db.eventRows).insertOnConflictUpdate(
        EventRow(
          id: j['id'] as String,
          title: j['title'] as String,
          description: j['description'] as String?,
          startsAt: _dtReq(j['starts_at']),
          endsAt: _dt(j['ends_at']),
          allDay: _bool(j['all_day']),
          location: j['location'] as String?,
          category: j['category'] as String?,
          coverImageUrl: j['cover_image_url'] as String?,
          createdBy: j['created_by'] as String?,
          colorIndex: _int(j['color_index']),
          updatedAt: _dtReq(j['updated_at']),
        ),
      );
}

Future<void> _removeEvent(AppDatabase db, String id) async {
  await (db.delete(db.eventRows)..where((t) => t.id.equals(id))).go();
}

Future<void> _clearEvent(AppDatabase db) async {
  await db.delete(db.eventRows).go();
}

Future<void> _restoreEvent(AppDatabase db, Map<String, dynamic> j) async {
  await db.into(db.eventRows).insertOnConflictUpdate(EventRow.fromJson(j));
}

// --- weekly_slots ----------------------------------------------------------
//
// `starts_at` e `ends_at` são `time` no Postgres ("HH:MM:SS"), guardados como
// minutos desde meia-noite no drift.

Future<void> _upsertWeeklySlot(AppDatabase db, Map<String, dynamic> j) async {
  await db.into(db.weeklySlotRows).insertOnConflictUpdate(
        WeeklySlotRow(
          id: j['id'] as String,
          weekday: _intReq(j['weekday']),
          startsAtMinutes: _timeToMinutes(j['starts_at']),
          endsAtMinutes: _timeToMinutesOpt(j['ends_at']),
          title: j['title'] as String,
          location: j['location'] as String?,
          category: j['category'] as String?,
          notes: j['notes'] as String?,
          isActive: _bool(j['is_active'], d: true),
          ordering: _intReq(j['ordering']),
          colorIndex: _int(j['color_index']),
          updatedAt: _dtReq(j['updated_at']),
        ),
      );
}

Future<void> _removeWeeklySlot(AppDatabase db, String id) async {
  await (db.delete(db.weeklySlotRows)..where((t) => t.id.equals(id))).go();
}

Future<void> _clearWeeklySlot(AppDatabase db) async {
  await db.delete(db.weeklySlotRows).go();
}

Future<void> _restoreWeeklySlot(AppDatabase db, Map<String, dynamic> j) async {
  await db.into(db.weeklySlotRows)
      .insertOnConflictUpdate(WeeklySlotRow.fromJson(j));
}

// --- prayer_feed (view, fullReplace) ---------------------------------------
//
// A view não tem `deleted_at` — ela já filtra `where p.deleted_at is null`.
// Por isso fullReplace: uma post apagada simplesmente desaparece dos
// resultados, e o clear+reinsert reflete isso automaticamente.

Future<void> _upsertPrayerFeed(AppDatabase db, Map<String, dynamic> j) async {
  await db.into(db.prayerFeedRows).insertOnConflictUpdate(
        PrayerFeedRow(
          id: j['id'] as String,
          authorId: j['author_id'] as String,
          title: j['title'] as String,
          body: j['body'] as String,
          isAnonymous: _bool(j['is_anonymous']),
          answeredAt: _dt(j['answered_at']),
          answerNote: j['answer_note'] as String?,
          authorName: j['author_name'] as String?,
          authorAvatarUrl: j['author_avatar_url'] as String?,
          prayingCount: _intReq(j['praying_count']),
          commentCount: _intReq(j['comment_count']),
          isPraying: _bool(j['is_praying']),
          createdAt: _dtReq(j['created_at']),
          updatedAt: _dtReq(j['updated_at']),
        ),
      );
}

Future<void> _removePrayerFeed(AppDatabase db, String id) async {
  await (db.delete(db.prayerFeedRows)..where((t) => t.id.equals(id))).go();
}

Future<void> _clearPrayerFeed(AppDatabase db) async {
  await db.delete(db.prayerFeedRows).go();
}

Future<void> _restorePrayerFeed(AppDatabase db, Map<String, dynamic> j) async {
  await db.into(db.prayerFeedRows)
      .insertOnConflictUpdate(PrayerFeedRow.fromJson(j));
}

// --- prayer_comments -------------------------------------------------------

Future<void> _upsertPrayerComment(AppDatabase db, Map<String, dynamic> j) async {
  await db.into(db.prayerCommentRows).insertOnConflictUpdate(
        PrayerCommentRow(
          id: j['id'] as String,
          postId: j['post_id'] as String,
          authorId: j['author_id'] as String,
          body: j['body'] as String,
          createdAt: _dtReq(j['created_at']),
          updatedAt: _dtReq(j['updated_at']),
        ),
      );
}

Future<void> _removePrayerComment(AppDatabase db, String id) async {
  await (db.delete(db.prayerCommentRows)..where((t) => t.id.equals(id))).go();
}

Future<void> _clearPrayerComment(AppDatabase db) async {
  await db.delete(db.prayerCommentRows).go();
}

Future<void> _restorePrayerComment(
  AppDatabase db,
  Map<String, dynamic> j,
) async {
  await db.into(db.prayerCommentRows)
      .insertOnConflictUpdate(PrayerCommentRow.fromJson(j));
}

// --- announcements ---------------------------------------------------------

Future<void> _upsertAnnouncement(AppDatabase db, Map<String, dynamic> j) async {
  // Denormaliza author_name do cache de profiles. Como profiles é sincronizado
  // antes (order: 0), o nome já está disponível aqui. Se o profile ainda não
  // foi sincronizado, authorName fica null — o próximo sync corrigirá.
  String? authorName;
  final authorId = j['author_id'] as String?;
  if (authorId != null) {
    final profile = await (db.select(db.profileRows)
          ..where((t) => t.id.equals(authorId)))
        .getSingleOrNull();
    authorName = profile?.fullName;
  }

  await db.into(db.announcementRows).insertOnConflictUpdate(
        AnnouncementRow(
          id: j['id'] as String,
          authorId: authorId,
          authorName: authorName,
          title: j['title'] as String?,
          body: j['body'] as String,
          pinned: _bool(j['pinned']),
          createdAt: _dtReq(j['created_at']),
          updatedAt: _dtReq(j['updated_at']),
        ),
      );
}

Future<void> _removeAnnouncement(AppDatabase db, String id) async {
  await (db.delete(db.announcementRows)..where((t) => t.id.equals(id))).go();
}

Future<void> _clearAnnouncement(AppDatabase db) async {
  await db.delete(db.announcementRows).go();
}

Future<void> _restoreAnnouncement(
  AppDatabase db,
  Map<String, dynamic> j,
) async {
  await db.into(db.announcementRows)
      .insertOnConflictUpdate(AnnouncementRow.fromJson(j));
}

// --- base_info -------------------------------------------------------------

Future<void> _upsertBaseInfo(AppDatabase db, Map<String, dynamic> j) async {
  await db.into(db.baseInfoRows).insertOnConflictUpdate(
        BaseInfoRow(
          id: j['id'] as String,
          key: j['key'] as String,
          label: j['label'] as String,
          value: j['value'] as String,
          ordering: _intReq(j['ordering']),
          updatedAt: _dtReq(j['updated_at']),
        ),
      );
}

Future<void> _removeBaseInfo(AppDatabase db, String id) async {
  await (db.delete(db.baseInfoRows)..where((t) => t.id.equals(id))).go();
}

Future<void> _clearBaseInfo(AppDatabase db) async {
  await db.delete(db.baseInfoRows).go();
}

Future<void> _restoreBaseInfo(AppDatabase db, Map<String, dynamic> j) async {
  await db.into(db.baseInfoRows)
      .insertOnConflictUpdate(BaseInfoRow.fromJson(j));
}

// --- social_links ----------------------------------------------------------

Future<void> _upsertSocialLink(AppDatabase db, Map<String, dynamic> j) async {
  await db.into(db.socialLinkRows).insertOnConflictUpdate(
        SocialLinkRow(
          id: j['id'] as String,
          platform: j['platform'] as String,
          url: j['url'] as String,
          label: j['label'] as String?,
          ordering: _intReq(j['ordering']),
          isActive: _bool(j['is_active'], d: true),
          updatedAt: _dtReq(j['updated_at']),
        ),
      );
}

Future<void> _removeSocialLink(AppDatabase db, String id) async {
  await (db.delete(db.socialLinkRows)..where((t) => t.id.equals(id))).go();
}

Future<void> _clearSocialLink(AppDatabase db) async {
  await db.delete(db.socialLinkRows).go();
}

Future<void> _restoreSocialLink(AppDatabase db, Map<String, dynamic> j) async {
  await db.into(db.socialLinkRows)
      .insertOnConflictUpdate(SocialLinkRow.fromJson(j));
}

// ---------------------------------------------------------------------------
// Registro das entidades — ordem respeita dependências de FK.
//
// perfis e scale_types primeiro (sem FKs). Depois quem depende deles.
// prayer_feed (view) antes de prayer_comments, pois comments referencia
// posts que aparecem no feed.
// ---------------------------------------------------------------------------

final List<SyncEntity> syncEntities = [
  const SyncEntity(
    name: 'profiles',
    remoteTable: 'profiles',
    mode: SyncMode.incremental,
    order: 0,
    upsert: _upsertProfile,
    remove: _removeProfile,
    clear: _clearProfile,
    restore: _restoreProfile,
  ),
  const SyncEntity(
    name: 'scale_types',
    remoteTable: 'scale_types',
    mode: SyncMode.incremental,
    order: 0,
    upsert: _upsertScaleType,
    remove: _removeScaleType,
    clear: _clearScaleType,
    restore: _restoreScaleType,
  ),
  const SyncEntity(
    name: 'invites',
    remoteTable: 'invites',
    mode: SyncMode.incremental,
    order: 1,
    upsert: _upsertInvite,
    remove: _removeInvite,
    clear: _clearInvite,
    restore: _restoreInvite,
  ),
  const SyncEntity(
    name: 'scale_managers',
    remoteTable: 'scale_managers',
    mode: SyncMode.fullReplace,
    order: 2,
    upsert: _upsertScaleManager,
    remove: _removeScaleManager,
    clear: _clearScaleManager,
    restore: _restoreScaleManager,
  ),
  const SyncEntity(
    name: 'scale_assignments',
    remoteTable: 'scale_assignments',
    mode: SyncMode.incremental,
    order: 2,
    upsert: _upsertScaleAssignment,
    remove: _removeScaleAssignment,
    clear: _clearScaleAssignment,
    restore: _restoreScaleAssignment,
  ),
  const SyncEntity(
    name: 'events',
    remoteTable: 'events',
    mode: SyncMode.incremental,
    order: 1,
    upsert: _upsertEvent,
    remove: _removeEvent,
    clear: _clearEvent,
    restore: _restoreEvent,
  ),
  const SyncEntity(
    name: 'weekly_slots',
    remoteTable: 'weekly_slots',
    mode: SyncMode.incremental,
    order: 0,
    upsert: _upsertWeeklySlot,
    remove: _removeWeeklySlot,
    clear: _clearWeeklySlot,
    restore: _restoreWeeklySlot,
  ),
  const SyncEntity(
    name: 'prayer_feed',
    remoteTable: 'prayer_feed',
    mode: SyncMode.fullReplace,
    order: 1,
    upsert: _upsertPrayerFeed,
    remove: _removePrayerFeed,
    clear: _clearPrayerFeed,
    restore: _restorePrayerFeed,
  ),
  const SyncEntity(
    name: 'prayer_comments',
    remoteTable: 'prayer_comments',
    mode: SyncMode.incremental,
    order: 2,
    upsert: _upsertPrayerComment,
    remove: _removePrayerComment,
    clear: _clearPrayerComment,
    restore: _restorePrayerComment,
  ),
  const SyncEntity(
    name: 'announcements',
    remoteTable: 'announcements',
    mode: SyncMode.incremental,
    order: 1,
    upsert: _upsertAnnouncement,
    remove: _removeAnnouncement,
    clear: _clearAnnouncement,
    restore: _restoreAnnouncement,
  ),
  const SyncEntity(
    name: 'base_info',
    remoteTable: 'base_info',
    mode: SyncMode.incremental,
    order: 0,
    upsert: _upsertBaseInfo,
    remove: _removeBaseInfo,
    clear: _clearBaseInfo,
    restore: _restoreBaseInfo,
  ),
  const SyncEntity(
    name: 'social_links',
    remoteTable: 'social_links',
    mode: SyncMode.incremental,
    order: 0,
    upsert: _upsertSocialLink,
    remove: _removeSocialLink,
    clear: _clearSocialLink,
    restore: _restoreSocialLink,
  ),
  // prayer_interactions não é cacheada (é DELETE físico, sem tombstones).
  // Está registrada apenas para o OutboxWorker saber enviá-la. As funções
  // upsert/remove/clear/restore são no-ops porque não há cache local desta
  // tabela — o toggle ajusta prayingCount/isPraying direto na linha do
  // prayer_feed (view) e o próximo pull fullReplace corrige qualquer
  // divergência.
  //
  // eqColumn = 'post_id': o RLS garante que só a interação do próprio
  // usuário (user_id = auth.uid()) é afetada, então filtrar só por post_id
  // é suficiente.
  const SyncEntity(
    name: 'prayer_interactions',
    remoteTable: 'prayer_interactions',
    mode: SyncMode.fullReplace,
    order: 99,
    upsert: _noopUpsert,
    remove: _noopRemove,
    clear: _noopClear,
    restore: _noopUpsert,
    eqColumn: 'post_id',
  ),
];

// --- No-ops para entidades não-cacheadas -----------------------------------

Future<void> _noopUpsert(AppDatabase db, Map<String, dynamic> j) async {}
Future<void> _noopRemove(AppDatabase db, String id) async {}
Future<void> _noopClear(AppDatabase db) async {}

final Map<String, SyncEntity> _entityByName = {
  for (final e in syncEntities) e.name: e,
};

/// Busca entidade pelo nome usado em `sync_state` e `outbox.entity`.
SyncEntity? syncEntityByName(String name) => _entityByName[name];

/// Codifica o rowId de uma PK composta (scale_managers) como string.
String encodeCompositeId(String scaleTypeId, String userId) =>
    '$scaleTypeId|$userId';

/// Decodifica o rowId composto. Lança se o formato for inválido.
List<String> decodeCompositeId(String rowId) {
  final parts = rowId.split('|');
  if (parts.length != 2) {
    throw FormatException('rowId composto inválido: "$rowId"');
  }
  return parts;
}

/// Serializa um payload para a coluna `outbox.payload`.
String encodePayload(Map<String, dynamic> payload) => jsonEncode(payload);

/// Desserializa o payload da coluna `outbox.payload`.
Map<String, dynamic> decodePayload(String payload) =>
    jsonDecode(payload) as Map<String, dynamic>;

/// Desserializa o `previousRow` da outbox (drift JSON).
Map<String, dynamic>? decodePreviousRow(String? previousRow) {
  if (previousRow == null) return null;
  return jsonDecode(previousRow) as Map<String, dynamic>;
}
