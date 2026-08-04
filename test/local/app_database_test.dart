import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/models/app_role.dart';

import '../helpers/test_helpers.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = createTestDatabase());
  tearDown(() => db.close());

  group('AppDatabase', () {
    test('cria o schema e abre', () async {
      // Força a abertura real (a conexão do drift é lazy).
      final tables = await db
          .customSelect(
            "select name from sqlite_master "
            "where type = 'table' and name not like 'sqlite_%'",
          )
          .get();
      final names = tables.map((r) => r.read<String>('name')).toSet();

      expect(names, contains('profile_rows'));
      expect(names, contains('scale_manager_rows'));
      expect(names, contains('prayer_feed_rows'));
      expect(names, contains('sync_states'));
      expect(names, contains('outbox_entries'));
    });

    test('beforeOpen liga as foreign keys', () async {
      // Se este PRAGMA vier 0, as FKs declaradas não valem nada e o cache
      // acumula linhas órfãs sem nunca dar erro.
      final result = await db.customSelect('pragma foreign_keys').getSingle();
      expect(result.data.values.first, 1);
    });

    test('o conversor de enum grava e lê o papel', () async {
      await db.into(db.profileRows).insert(
            ProfileRowsCompanion.insert(
              id: 'u1',
              fullName: 'Maria Silva',
              role: AppRole.admin,
              updatedAt: DateTime.utc(2026, 1, 1),
            ),
          );

      final row = await db.select(db.profileRows).getSingle();
      expect(row.role, AppRole.admin);

      // O valor persistido tem de ser exatamente o do enum app_role do
      // Postgres — se divergir, o payload enviado ao servidor é inválido.
      final raw = await db
          .customSelect('select role from profile_rows')
          .getSingle();
      expect(raw.read<String>('role'), 'admin');
    });

    test('o conversor de List<String> preserva valores com vírgula', () async {
      // O caso que quebraria um split por separador. Os slots vêm do usuário.
      const slots = ['06:00-07:00', 'Cozinha, área comum', ''];

      await db.into(db.scaleTypeRows).insert(
            ScaleTypeRowsCompanion.insert(
              id: 's1',
              slug: 'servir-ao-todo',
              name: 'Servir ao Todo',
              slots: slots,
              updatedAt: DateTime.utc(2026, 1, 1),
            ),
          );

      final row = await db.select(db.scaleTypeRows).getSingle();
      expect(row.slots, slots);
    });

    test('a PK composta de scale_managers impede duplicata', () async {
      Future<void> insert() => db.into(db.scaleManagerRows).insert(
            ScaleManagerRowsCompanion.insert(
              scaleTypeId: 't1',
              userId: 'u1',
            ),
          );

      await insert();

      // Asserta o invariante (não duplica), não o tipo da exceção: o tipo
      // concreto vem do package:sqlite3, que é dependência transitiva, e o que
      // importa aqui é que o par (escala, obreiro) permaneça único.
      await expectLater(insert(), throwsA(isA<Exception>()));

      final count = await db.scaleManagerRows.count().getSingle();
      expect(count, 1);
    });

    test('a outbox preserva a ordem de inserção', () async {
      // A ordem de drenagem é a ordem em que o usuário fez as edições. Se duas
      // edições da mesma linha subirem fora de ordem, a segunda é sobrescrita.
      for (final op in ['insert', 'update', 'delete']) {
        await db.into(db.outboxEntries).insert(
              OutboxEntriesCompanion.insert(
                entity: 'events',
                op: op,
                rowId: 'e1',
                payload: '{}',
                createdAt: DateTime.utc(2026, 1, 1),
              ),
            );
      }

      final rows = await (db.select(db.outboxEntries)
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get();

      expect(rows.map((r) => r.op).toList(), ['insert', 'update', 'delete']);
      expect(rows.map((r) => r.id).toList(), [1, 2, 3]);
    });

    test('o stream do drift emite quando a tabela muda', () async {
      // É o mecanismo em que toda a UI se apoia: a tela observa o stream local
      // e o sync alimenta o cache.
      final emissions = <int>[];
      final sub = db
          .select(db.announcementRows)
          .watch()
          .listen((rows) => emissions.add(rows.length));

      await pumpEventQueue();
      await db.into(db.announcementRows).insert(
            AnnouncementRowsCompanion.insert(
              id: 'a1',
              body: 'Primeiro aviso',
              createdAt: DateTime.utc(2026, 1, 1),
              updatedAt: DateTime.utc(2026, 1, 1),
            ),
          );
      await pumpEventQueue();

      await sub.cancel();
      expect(emissions, [0, 1]);
    });
  });
}
