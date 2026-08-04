import 'package:drift/drift.dart';

import 'package:veredas/data/local/converters.dart';
import 'package:veredas/data/models/app_role.dart';

// ===========================================================================
// Tabelas de cache — espelham o servidor.
//
// Regras que valem para todas (PLANO.md §2.5):
//
// 1. A PK é `text()`, não `autoIncrement`. Os ids são UUIDs gerados pelo
//    servidor; um id local auto-incremental não teria como ser reconciliado
//    com a linha remota.
// 2. Toda tabela sincronizada tem `updatedAt`, que é a marca d'água do pull
//    incremental.
// 3. Não guardamos `deletedAt`: o pull REMOVE do cache local a linha que vem
//    com `deleted_at != null`. O soft delete existe no servidor para que um
//    dispositivo offline descubra a remoção; localmente a linha simplesmente
//    deixa de existir, e assim nenhuma query de leitura precisa lembrar de
//    filtrar `deletedAt is null` — um filtro esquecido mostraria dado apagado.
//
// O sufixo `Row` nos @DataClassName é obrigatório: sem ele o drift geraria uma
// classe `Profile`, colidindo com o modelo de domínio `Profile` do freezed.
// ===========================================================================

/// Espelho de `public.profiles`.
@DataClassName('ProfileRow')
class ProfileRows extends Table {
  TextColumn get id => text()();
  TextColumn get fullName => text()();
  TextColumn get email => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get avatarUrl => text().nullable()();
  TextColumn get bio => text().nullable()();

  /// `textEnum` grava `AppRole.name`, que é idêntico ao valor do enum
  /// `app_role` no Postgres ('admin' / 'obreiro').
  TextColumn get role => textEnum<AppRole>()();

  BoolColumn get isApproved =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Espelho de `public.invites`. Só admin recebe linhas aqui (o RLS filtra),
/// então para um obreiro comum esta tabela fica vazia — e isso é o correto.
@DataClassName('InviteRow')
class InviteRows extends Table {
  TextColumn get id => text()();
  TextColumn get code => text()();
  TextColumn get role => textEnum<AppRole>()();
  TextColumn get note => text().nullable()();
  IntColumn get maxUses => integer().withDefault(const Constant(1))();
  IntColumn get uses => integer().withDefault(const Constant(0))();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  DateTimeColumn get revokedAt => dateTime().nullable()();
  TextColumn get createdBy => text().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Espelho de `public.scale_types`. Alimenta a TabBar da tela Escalas — que é
/// gerada a partir daqui justamente para que adicionar uma escala nova seja um
/// INSERT no banco, não um release do app.
@DataClassName('ScaleTypeRow')
class ScaleTypeRows extends Table {
  TextColumn get id => text()();
  TextColumn get slug => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get icon => text().nullable()();
  TextColumn get cadence => text().withDefault(const Constant('weekly'))();
  TextColumn get slots => text().map(const StringListConverter())();
  IntColumn get ordering => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Espelho de `public.scale_managers` — quem pode editar cada escala.
///
/// PK composta, igual ao servidor. Sincronizada por **substituição total**
/// (`SyncMode.fullReplace`): a tabela remota não tem `deleted_at` e sofre
/// DELETE físico, então o pull incremental jamais perceberia que um
/// responsável foi removido — e a pessoa continuaria vendo o FAB de edição.
@DataClassName('ScaleManagerRow')
class ScaleManagerRows extends Table {
  TextColumn get scaleTypeId => text()();
  TextColumn get userId => text()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {scaleTypeId, userId};
}

/// Espelho de `public.scale_assignments`.
@DataClassName('ScaleAssignmentRow')
class ScaleAssignmentRows extends Table {
  TextColumn get id => text()();
  TextColumn get scaleTypeId => text()();

  /// `date` no servidor. Guardado como `DateTime` à meia-noite local — as
  /// comparações do app são sempre por dia, nunca por instante.
  DateTimeColumn get startsOn => dateTime()();
  DateTimeColumn get endsOn => dateTime().nullable()();
  TextColumn get slot => text().nullable()();
  TextColumn get task => text().nullable()();
  TextColumn get assigneeId => text().nullable()();

  /// Para quem não tem conta no app. O servidor exige que ao menos um entre
  /// `assigneeId` e `assigneeName` esteja preenchido.
  TextColumn get assigneeName => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get createdBy => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Espelho de `public.events`.
@DataClassName('EventRow')
class EventRows extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();

  /// `timestamptz` no servidor. Guardado em UTC e exibido no fuso local, o que
  /// trata horário de verão sem código extra.
  DateTimeColumn get startsAt => dateTime()();
  DateTimeColumn get endsAt => dateTime().nullable()();
  BoolColumn get allDay => boolean().withDefault(const Constant(false))();
  TextColumn get location => text().nullable()();
  TextColumn get category => text().nullable()();
  TextColumn get coverImageUrl => text().nullable()();
  TextColumn get createdBy => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Espelho de `public.weekly_slots` — o cronograma semanal fixo (a "planilha").
@DataClassName('WeeklySlotRow')
class WeeklySlotRows extends Table {
  TextColumn get id => text()();

  /// ISO-8601: 1 = segunda ... 7 = domingo. Igual a `DateTime.weekday` do Dart,
  /// de propósito — evita uma conversão que é fonte clássica de erro de 1 dia.
  IntColumn get weekday => integer()();

  /// `time` no servidor, guardado como minutos desde a meia-noite.
  ///
  /// Um `DateTime` exigiria inventar uma data qualquer para carregar a hora, e
  /// aí toda comparação teria de normalizar essa data fantasma. Minutos são
  /// ordenáveis, comparáveis e imunes a fuso.
  IntColumn get startsAtMinutes => integer()();
  IntColumn get endsAtMinutes => integer().nullable()();

  TextColumn get title => text()();
  TextColumn get location => text().nullable()();
  TextColumn get category => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get ordering => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Espelho da **view** `public.prayer_feed`, não da tabela `prayer_posts`.
///
/// A view já traz `prayingCount`, `commentCount` e `isPraying` agregados. A
/// tabela `prayer_interactions` não é cacheada: "desmarcar estou orando" é um
/// DELETE físico, e cachear a tabela crua exigiria tombstones sem ganho algum.
///
/// Escritas otimistas de "estou orando" ajustam `prayingCount`/`isPraying`
/// direto nesta linha.
@DataClassName('PrayerFeedRow')
class PrayerFeedRows extends Table {
  TextColumn get id => text()();
  TextColumn get authorId => text()();
  TextColumn get title => text()();
  TextColumn get body => text()();
  BoolColumn get isAnonymous =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get answeredAt => dateTime().nullable()();
  TextColumn get answerNote => text().nullable()();

  /// Nulos quando o post é anônimo — a própria view esconde o autor, então o
  /// nome nunca chega ao dispositivo. Anonimato garantido no servidor, não na UI.
  TextColumn get authorName => text().nullable()();
  TextColumn get authorAvatarUrl => text().nullable()();

  IntColumn get prayingCount => integer().withDefault(const Constant(0))();
  IntColumn get commentCount => integer().withDefault(const Constant(0))();
  BoolColumn get isPraying => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Espelho de `public.prayer_comments`.
@DataClassName('PrayerCommentRow')
class PrayerCommentRows extends Table {
  TextColumn get id => text()();
  TextColumn get postId => text()();
  TextColumn get authorId => text()();
  TextColumn get body => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Espelho de `public.announcements`.
@DataClassName('AnnouncementRow')
class AnnouncementRows extends Table {
  TextColumn get id => text()();
  TextColumn get authorId => text().nullable()();
  TextColumn get title => text().nullable()();
  TextColumn get body => text()();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Espelho de `public.base_info` — o acordeão "Dados da Base".
@DataClassName('BaseInfoRow')
class BaseInfoRows extends Table {
  TextColumn get id => text()();
  TextColumn get key => text()();
  TextColumn get label => text()();
  TextColumn get value => text()();
  IntColumn get ordering => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Espelho de `public.social_links`.
@DataClassName('SocialLinkRow')
class SocialLinkRows extends Table {
  TextColumn get id => text()();
  TextColumn get platform => text()();
  TextColumn get url => text()();
  TextColumn get label => text().nullable()();
  IntColumn get ordering => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ===========================================================================
// Tabelas de controle — não existem no servidor.
// ===========================================================================

/// Marca d'água do pull incremental, uma linha por entidade.
///
/// O pull consulta `updated_at > lastSyncedAt - 2 min`. A janela de 2 minutos
/// cobre desvio de relógio entre servidor e dispositivo; reprocessar linhas é
/// inofensivo porque o upsert é idempotente.
@DataClassName('SyncStateRow')
class SyncStates extends Table {
  /// Valor de `SyncEntity.name`.
  TextColumn get entity => text()();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  /// Última falha de sync desta entidade, para diagnóstico. Não é exibida crua
  /// ao usuário — a UI mostra a mensagem do l10n a partir do código do erro.
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {entity};
}

/// Fila de escrita. **Toda** escrita do app passa por aqui.
///
/// A gravação é uma transação única: aplica a mudança otimista na tabela de
/// cache e insere a linha na outbox. Como as telas observam o `Stream` do
/// drift, a UI atualiza na hora, com ou sem rede.
@DataClassName('OutboxRow')
class OutboxEntries extends Table {
  /// Aqui o autoIncrement é correto e necessário: a ordem de inserção é a ordem
  /// de drenagem. Duas edições da mesma linha têm de subir na sequência em que
  /// o usuário as fez, senão a segunda seria sobrescrita pela primeira.
  IntColumn get id => integer().autoIncrement()();

  /// Valor de `SyncEntity.name`.
  TextColumn get entity => text()();

  /// Valor de `OutboxOp.name`: insert | update | delete.
  TextColumn get op => text()();

  /// Id da linha afetada (UUID gerado no cliente para inserts).
  TextColumn get rowId => text()();

  /// Corpo JSON enviado ao servidor.
  TextColumn get payload => text()();

  /// Snapshot JSON da linha local **antes** da mudança, ou null se ela não
  /// existia.
  ///
  /// É o que permite reverter o cache quando o servidor recusa a escrita. Sem
  /// isso, um 403 deixaria a UI mostrando para sempre um dado que o servidor
  /// nunca aceitou.
  TextColumn get previousRow => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// Quando a próxima tentativa é permitida (backoff exponencial).
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();

  TextColumn get lastError => text().nullable()();
}
