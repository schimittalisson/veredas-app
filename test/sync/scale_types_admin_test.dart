import 'dart:convert';

// `count()` vem do drift; o `hide` evita a colisão com os matchers do teste.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/data/daos/scales_dao.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/repositories/scales_repository.dart';

import '../helpers/test_helpers.dart';

// Administração dos tipos de escala — as abas da tela Escalas.
//
// A barra de abas é gerada de `scale_types`, então tudo aqui é visível para
// toda a base assim que sincroniza: um slug duplicado ou uma ordenação com
// buracos aparecem na tela de todo mundo.

void main() {
  late AppDatabase db;
  late ScalesRepository repo;
  late ScalesDao dao;

  setUp(() {
    db = createTestDatabase();
    repo = ScalesRepository(db);
    dao = ScalesDao(db);
  });
  tearDown(() => db.close());

  Future<void> seedType({
    required String id,
    required String slug,
    required String name,
    int ordering = 1,
  }) async {
    await db.into(db.scaleTypeRows).insert(
          ScaleTypeRow(
            id: id,
            slug: slug,
            name: name,
            cadence: 'weekly',
            slots: const [],
            ordering: ordering,
            isActive: true,
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
        );
  }

  Future<List<Map<String, dynamic>>> outboxPayloads() async {
    final entries = await db.select(db.outboxEntries).get();
    return [
      for (final e in entries) jsonDecode(e.payload) as Map<String, dynamic>,
    ];
  }

  group('criar', () {
    test('deriva o slug do nome, sem acento nem espaço', () async {
      final id = await repo.createScaleType(
        name: 'Café da Gratidão',
        cadence: 'adhoc',
      );

      final row = (await dao.getScaleType(id))!;
      expect(row.slug, 'cafe-da-gratidao');
      expect(row.name, 'Café da Gratidão');
      expect(row.isActive, isTrue);
    });

    test('slug repetido ganha sufixo em vez de estourar no servidor', () async {
      // O índice único de `slug` recusaria a segunda linha — e a viagem só
      // falharia depois que a escala já tivesse aparecido na tela.
      await seedType(id: 't1', slug: 'almoco', name: 'Almoço');

      final id = await repo.createScaleType(name: 'Almoço', cadence: 'weekly');

      expect((await dao.getScaleType(id))!.slug, 'almoco-2');
    });

    test('entra no fim da barra de abas', () async {
      await seedType(id: 't1', slug: 'lixo', name: 'Lixo', ordering: 2);
      await seedType(id: 't2', slug: 'almoco', name: 'Almoço', ordering: 6);

      final id = await repo.createScaleType(name: 'Jardim', cadence: 'weekly');

      expect((await dao.getScaleType(id))!.ordering, 7);
    });

    test('enfileira o insert com o corpo que o servidor espera', () async {
      await repo.createScaleType(
        name: 'Jardim',
        cadence: 'monthly',
        slots: ['Manhã', 'Tarde'],
      );

      final entry = await db.select(db.outboxEntries).getSingle();
      expect(entry.entity, 'scale_types');
      expect(entry.op, 'insert');
      final payload = jsonDecode(entry.payload) as Map<String, dynamic>;
      expect(payload['slug'], 'jardim');
      expect(payload['cadence'], 'monthly');
      expect(payload['slots'], ['Manhã', 'Tarde']);
    });
  });

  group('editar', () {
    test('renomear não mexe no slug', () async {
      // O slug é a chave estável do tipo: mudá-lo ao renomear quebraria
      // qualquer coisa que dependa dele.
      final id = await repo.createScaleType(name: 'Almoço', cadence: 'weekly');
      await db.delete(db.outboxEntries).go();

      await repo.updateScaleType(
        id: id,
        name: 'Almoço da base',
        cadence: 'weekly',
        slots: const [],
        isActive: true,
      );

      final row = (await dao.getScaleType(id))!;
      expect(row.name, 'Almoço da base');
      expect(row.slug, 'almoco');

      final payload = (await outboxPayloads()).single;
      expect(payload.containsKey('slug'), isFalse);
    });

    test('desativar esconde a aba sem apagar a escala', () async {
      final id = await repo.createScaleType(name: 'Jardim', cadence: 'weekly');

      await repo.updateScaleType(
        id: id,
        name: 'Jardim',
        cadence: 'weekly',
        slots: const [],
        isActive: false,
      );

      // A tela Escalas lê as ativas; a linha continua no cache.
      expect(await dao.watchActiveScaleTypes().first, isEmpty);
      expect(await dao.getScaleType(id), isNotNull);
    });
  });

  test('remover é update de deleted_at, não DELETE', () async {
    final id = await repo.createScaleType(name: 'Jardim', cadence: 'weekly');
    await db.delete(db.outboxEntries).go();

    await repo.deleteScaleType(id);

    // Um DELETE físico levaria junto as atribuições (FK on delete cascade) e
    // não deixaria lápide para os outros aparelhos.
    final entry = await db.select(db.outboxEntries).getSingle();
    expect(entry.op, 'update');
    expect(jsonDecode(entry.payload)['deleted_at'], isNotNull);
    expect(await dao.getScaleType(id), isNull);
  });

  group('reordenar', () {
    setUp(() async {
      await seedType(id: 't1', slug: 'a', name: 'A', ordering: 1);
      await seedType(id: 't2', slug: 'b', name: 'B', ordering: 2);
      await seedType(id: 't3', slug: 'c', name: 'C', ordering: 3);
    });

    test('grava a nova posição de cada escala que mudou', () async {
      await repo.reorderScaleTypes(['t3', 't1', 't2']);

      final rows = await dao.watchAllScaleTypes().first;
      expect(rows.map((r) => r.id), ['t3', 't1', 't2']);
      expect(rows.map((r) => r.ordering), [1, 2, 3]);
    });

    test('não enfileira escrita para quem ficou no mesmo lugar', () async {
      // Trocar as duas últimas mexe em duas linhas; a primeira não tem por que
      // ir para a fila.
      await repo.reorderScaleTypes(['t1', 't3', 't2']);

      final entries = await db.select(db.outboxEntries).get();
      expect(entries.map((e) => e.rowId), ['t3', 't2']);
      expect(entries.every((e) => e.op == 'update'), isTrue);
    });

    test('a ordem já correta não gera escrita nenhuma', () async {
      await repo.reorderScaleTypes(['t1', 't2', 't3']);
      expect(await db.outboxEntries.count().getSingle(), 0);
    });
  });
}
