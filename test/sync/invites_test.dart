// `Migrator`/`TableMigration` vêm do drift; o `hide` evita a colisão com os
// matchers do teste.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/sync/sync_entity.dart';
import 'package:veredas/data/sync/sync_service.dart';

import '../helpers/test_helpers.dart';

// Convite sem limite de usos.
//
// O convite da base nasceu com `max_uses = 20` ("um por obreiro") e a base
// passou de 30 pessoas. No servidor, "sem limite" virou `max_uses null`
// (migration 20260921000100); aqui do lado do cache o que importa é que o
// null atravesse o pull e a migration do drift sem virar 1 — um teto de 1 uso
// num convite aberto tranca a base inteira do lado de fora.

void main() {
  late AppDatabase db;
  late SyncService syncService;
  late FakeRemoteSource remote;

  setUp(() {
    db = createTestDatabase();
    remote = FakeRemoteSource();
    syncService = SyncService(db: db, remote: remote);
  });
  tearDown(() => db.close());

  Map<String, dynamic> inviteJson({
    required String id,
    required String code,
    Object? maxUses,
    int uses = 0,
  }) =>
      {
        'id': id,
        'code': code,
        'role': 'obreiro',
        'note': null,
        'max_uses': maxUses,
        'uses': uses,
        'expires_at': null,
        'revoked_at': null,
        'created_by': null,
        'created_at': '2026-09-21T10:00:00Z',
        'updated_at': '2026-09-21T10:00:00Z',
      };

  group('pull', () {
    test('max_uses null chega ao cache como null (sem limite)', () async {
      remote.fetchData['invites'] = [
        inviteJson(id: 'i1', code: 'VEREDAS2026', maxUses: null, uses: 27),
      ];

      await syncService.pull(syncEntityByName('invites')!);

      final row = await db.select(db.inviteRows).getSingle();
      expect(row.maxUses, isNull);
      expect(row.uses, 27);
    });

    test('max_uses com valor continua chegando inteiro', () async {
      remote.fetchData['invites'] = [
        inviteJson(id: 'i2', code: 'ABC234', maxUses: 3),
      ];

      await syncService.pull(syncEntityByName('invites')!);

      final row = await db.select(db.inviteRows).getSingle();
      expect(row.maxUses, 3);
    });

    test('o convite deixa de ter limite quando o admin tira o teto', () async {
      remote.fetchData['invites'] = [
        inviteJson(id: 'i1', code: 'VEREDAS2026', maxUses: 20, uses: 20),
      ];
      await syncService.pull(syncEntityByName('invites')!);
      expect((await db.select(db.inviteRows).getSingle()).maxUses, 20);

      // Segundo pull: o mesmo convite, agora ilimitado. O upsert precisa
      // GRAVAR o null — se ele fosse omitido por ser nulo, o cache guardaria
      // o teto antigo e a tela continuaria dizendo "Esgotado".
      remote.fetchData['invites'] = [
        inviteJson(id: 'i1', code: 'VEREDAS2026', maxUses: null, uses: 20),
      ];
      await syncService.pull(syncEntityByName('invites')!);

      expect((await db.select(db.inviteRows).getSingle()).maxUses, isNull);
    });
  });

  group('migration v5 -> v6', () {
    test('afrouxar o NOT NULL de max_uses preserva as linhas', () async {
      // Recria a tabela no formato v5 (max_uses NOT NULL DEFAULT 1) e põe uma
      // linha dentro, como estaria no aparelho de quem já tem o app.
      await db.customStatement('DROP TABLE invite_rows');
      await db.customStatement('''
        CREATE TABLE invite_rows (
          id TEXT NOT NULL,
          code TEXT NOT NULL,
          role TEXT NOT NULL,
          note TEXT NULL,
          max_uses INTEGER NOT NULL DEFAULT 1,
          uses INTEGER NOT NULL DEFAULT 0,
          expires_at INTEGER NULL,
          revoked_at INTEGER NULL,
          created_by TEXT NULL,
          created_at INTEGER NULL,
          updated_at INTEGER NOT NULL,
          PRIMARY KEY (id)
        )
      ''');
      await db.customStatement(
        "INSERT INTO invite_rows (id, code, role, max_uses, uses, updated_at) "
        "VALUES ('i1', 'VEREDAS2026', 'obreiro', 20, 7, 0)",
      );

      await Migrator(db).alterTable(TableMigration(db.inviteRows));

      // A linha sobreviveu com o teto que tinha — a migration não reinterpreta
      // dado, só abre espaço para o null.
      final row = await db.select(db.inviteRows).getSingle();
      expect(row.maxUses, 20);
      expect(row.uses, 7);

      // E agora a coluna aceita null, que é o ponto da v6.
      await db.customStatement(
        "UPDATE invite_rows SET max_uses = NULL WHERE id = 'i1'",
      );
      expect((await db.select(db.inviteRows).getSingle()).maxUses, isNull);
    });
  });
}
