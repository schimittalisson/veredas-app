import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'package:veredas/data/local/tables.dart';
// Estes dois imports parecem não usados neste arquivo, mas são obrigatórios: o
// `app_database.g.dart` é um `part` desta biblioteca e portanto herda os
// imports dela. Sem eles o gerado não resolve `AppRole` nem
// `StringListConverter` e a compilação falha — o que o `flutter analyze` NÃO
// pega, porque o analysis_options exclui `**/*.g.dart`.
import 'package:veredas/data/local/converters.dart';
import 'package:veredas/data/models/app_role.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    ProfileRows,
    InviteRows,
    ScaleTypeRows,
    ScaleManagerRows,
    ScaleAssignmentRows,
    EventRows,
    WeeklySlotRows,
    PrayerFeedRows,
    PrayerCommentRows,
    AnnouncementRows,
    BaseInfoRows,
    SocialLinkRows,
    DocumentRows,
    SyncStates,
    OutboxEntries,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  /// Construtor para testes, com um executor in-memory.
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // ATENÇÃO: NÃO use `m.createAll()` aqui.
          //
          // O projeto de referência (CalorieMate) faz `onUpgrade: (m, from, to)
          // => m.createAll()`, e isso está errado: `createAll` só cria tabelas
          // que não existem. Uma coluna adicionada ou renomeada é ignorada em
          // SILÊNCIO, e o app quebra em produção com um erro de coluna
          // inexistente — no dispositivo de quem já tinha a versão antiga, que é
          // exatamente quem você não consegue depurar.
          //
          // Escreva um step explícito por versão:
          //
          //   if (from < 2) {
          //     await m.addColumn(eventRows, eventRows.someNewColumn);
          //   }
          //
          // Lembre de subir o `schemaVersion` junto.
          //
          // Como este cache é 100% derivado do servidor, existe uma saída de
          // emergência legítima: apagar tudo e ressincronizar (limpar
          // `syncStates` força um pull completo). Mas isso descarta a outbox
          // pendente, então só vale se a migration for realmente inviável.

          // v2 — cor escolhida pelo usuário em eventos e no cronograma.
          // Nula nas linhas existentes, o que mantém o comportamento antigo
          // (cor derivada da categoria) até alguém escolher uma.
          if (from < 2) {
            await m.addColumn(eventRows, eventRows.colorIndex);
            await m.addColumn(weeklySlotRows, weeklySlotRows.colorIndex);
          }

          // v3 — aba Arquivos. Tabela nova, então `createTable` basta; ela
          // nasce vazia e o primeiro pull a popula (não há `sync_state` para
          // 'documents' ainda, e sem marca d'água o pull traz tudo).
          if (from < 3) {
            await m.createTable(documentRows);
          }
        },
        beforeOpen: (details) async {
          // Sem isto o SQLite ignora as foreign keys — elas são declaradas mas
          // não valem nada, e o cache acumula linhas órfãs (comentário apontando
          // para post que já saiu do cache, por exemplo).
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  static QueryExecutor _open() => driftDatabase(name: 'veredas');
}
