import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/models/app_role.dart';
import 'package:veredas/data/sync/sync_entity.dart';
import 'package:veredas/ui/screens/scales/scale_tab_view.dart';

import '../helpers/test_helpers.dart';
import '../helpers/widget_test_helpers.dart';

// A tela de escalas renderizando uma atribuição de equipe.
//
// O que estes testes protegem é a tradução de ids em nomes: a equipe é
// guardada como `member_ids`, e se a resolução pelo cache de perfis quebrar a
// tela passa a mostrar "A definir" — ou, pior, um UUID — no lugar das pessoas.

/// Segunda-feira da semana atual, que é onde o navegador de período abre.
DateTime thisMonday() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - (now.weekday - 1));
}

void main() {
  late AppDatabase db;
  late FakeAuthService auth;

  setUp(() async {
    db = createTestDatabase();
    auth = FakeAuthService()..simulateAuthenticated(userId: 'u1');

    for (final p in [
      ('u1', 'Ana'),
      ('u2', 'Bia'),
      ('u9', 'Gabriel'),
    ]) {
      await db.into(db.profileRows).insert(
            ProfileRow(
              id: p.$1,
              fullName: p.$2,
              role: AppRole.obreiro,
              isApproved: true,
              updatedAt: DateTime.utc(2026, 9, 1),
            ),
          );
    }
  });

  ScaleTypeRow lunchType() => ScaleTypeRow(
        id: 'st-almoco',
        slug: 'almoco',
        name: 'Almoço',
        // Sem slots: a escala do almoço é um grupo por dia, e a tela cai na
        // lista por dia da semana.
        slots: const [],
        cadence: 'weekly',
        ordering: 6,
        isActive: true,
        updatedAt: DateTime.utc(2026, 9, 1),
      );

  Future<void> seedAssignment({
    List<String> memberIds = const [],
    List<String> memberNames = const [],
    String? assigneeId,
  }) async {
    await syncEntityByName('scale_assignments')!.upsert(db, {
      'id': 'sa1',
      'scale_type_id': 'st-almoco',
      'starts_on': thisMonday().toIso8601String(),
      'ends_on': null,
      'slot': null,
      'task': null,
      'assignee_id': assigneeId,
      'assignee_name': null,
      'member_ids': memberIds,
      'member_names': memberNames,
      'notes': null,
      'created_by': null,
      'updated_at': DateTime.utc(2026, 9, 1).toIso8601String(),
    });
  }

  Future<void> pumpTab(WidgetTester tester) async {
    await tester.pumpWidget(
      buildTestWidget(
        db: db,
        auth: auth,
        child: CupertinoPageScaffold(
          child: ScaleTabView(scaleType: lunchType(), canEdit: false),
        ),
      ),
    );
    // Nunca pumpAndSettle: os StreamProviders do drift não assentam.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Desmonta a árvore ainda dentro do teste.
  ///
  /// Cancelar um stream do drift agenda um timer de duração zero
  /// (`StreamQueryStore.markAsClosed`). Sem isto, o ProviderScope só é
  /// descartado quando o teste seguinte monta a sua árvore, e o timer nasce
  /// depois do último frame — o flutter_test então falha com "A Timer is still
  /// pending even after the widget tree was disposed", mesmo com as asserções
  /// todas verdes. Descartando aqui, o `pump` logo abaixo consome o timer.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    // Com duração: um `pump()` sem avanço de tempo não dispara o timer.
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets('mostra a equipe inteira e o responsável geral', (tester) async {
    await seedAssignment(
      memberIds: ['u1', 'u2'],
      memberNames: ['Visitante'],
      assigneeId: 'u9',
    );

    await pumpTab(tester);

    expect(find.text('Ana, Bia, Visitante'), findsOneWidget);
    expect(find.textContaining('Gabriel'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('sem equipe, o responsável ocupa o lugar dela', (tester) async {
    // É a forma das atribuições criadas antes das escalas em grupo: mostrar
    // "responsável: Fulano" sobre uma linha vazia seria só confuso.
    await seedAssignment(assigneeId: 'u9');

    await pumpTab(tester);

    expect(find.text('Gabriel'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('estar na equipe marca a atribuição como sua', (tester) async {
    // 'u1' (Ana) está logada e aparece só dentro da equipe — o destaque não
    // pode depender de ela ser a responsável geral.
    await seedAssignment(memberIds: ['u1', 'u2'], assigneeId: 'u9');

    await pumpTab(tester);

    expect(find.text('Você'), findsOneWidget);
    expect(find.textContaining('Você está escalado 1×'), findsOneWidget);

    await unmount(tester);
  });
}
