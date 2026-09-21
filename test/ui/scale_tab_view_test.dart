import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/models/app_role.dart';
import 'package:veredas/data/sync/sync_entity.dart';
import 'package:veredas/ui/navigation/app_router.dart';
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
    String? slot,
  }) async {
    await syncEntityByName('scale_assignments')!.upsert(db, {
      'id': 'sa1',
      'scale_type_id': slot == null ? 'st-almoco' : 'st-lixo',
      'starts_on': thisMonday().toIso8601String(),
      'ends_on': null,
      'slot': slot,
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

  ScaleTypeRow choreType() => ScaleTypeRow(
        id: 'st-lixo',
        slug: 'lixo',
        name: 'Lixo',
        // Com slots: a tela cai na grade (linhas = slots, colunas = dias).
        slots: const ['Recolher'],
        cadence: 'weekly',
        ordering: 5,
        isActive: true,
        updatedAt: DateTime.utc(2026, 9, 1),
      );

  /// Guarda a rota que o toque abriu, para as asserções de navegação.
  String? openedUri;

  Future<void> pumpTab(
    WidgetTester tester, {
    bool canEdit = false,
    ScaleTypeRow? scaleType,
  }) async {
    openedUri = null;
    await tester.pumpWidget(
      buildTestWidgetWithRouter(
        db: db,
        auth: auth,
        initialLocation: '/escalas',
        child: CupertinoPageScaffold(
          child: ScaleTabView(
            scaleType: scaleType ?? lunchType(),
            canEdit: canEdit,
          ),
        ),
        destinationPath: Routes.escalaAtribuicaoEditar,
        destination: Builder(
          builder: (context) {
            openedUri = GoRouterState.of(context).uri.toString();
            return const Text('EDITOR');
          },
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

  // O pedido: "após salvar uma escala não há a opção de editar nem de remover".
  // O editor e o `deleteAssignment` já existiam — faltava o caminho até eles.
  group('toque abre o editor', () {
    testWidgets('na lista, quem pode editar abre a atribuição', (tester) async {
      await seedAssignment(memberIds: ['u1', 'u2']);

      await pumpTab(tester, canEdit: true);

      // O chevron é o que anuncia que a célula abre algo.
      expect(
        find.descendant(
          of: find.byType(CupertinoListTile),
          matching: find.byIcon(CupertinoIcons.chevron_right),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Ana, Bia'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('EDITOR'), findsOneWidget);
      // O id da atribuição E o do tipo: sem o segundo o editor não sabe quais
      // slots oferecer, e a rota exige o parâmetro.
      expect(openedUri, contains('id=sa1'));
      expect(openedUri, contains('scaleTypeId=st-almoco'));

      await unmount(tester);
    });

    testWidgets('na grade de slots também', (tester) async {
      await seedAssignment(memberIds: ['u1'], slot: 'Recolher');

      await pumpTab(tester, canEdit: true, scaleType: choreType());
      await tester.tap(find.text('Ana'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('EDITOR'), findsOneWidget);
      expect(openedUri, contains('id=sa1'));

      await unmount(tester);
    });

    testWidgets('quem não pode editar não abre nada', (tester) async {
      await seedAssignment(memberIds: ['u1', 'u2']);

      await pumpTab(tester, canEdit: false);
      await tester.tap(find.text('Ana, Bia'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('EDITOR'), findsNothing);
      expect(openedUri, isNull);
      // E a célula não promete o que não cumpre: sem chevron.
      // O finder é ancorado na célula porque o navegador de período tem um
      // chevron próprio (avançar a semana) que aparece nos dois casos.
      expect(
        find.descendant(
          of: find.byType(CupertinoListTile),
          matching: find.byIcon(CupertinoIcons.chevron_right),
        ),
        findsNothing,
        reason: 'chevron em célula que não abre nada engana o usuário',
      );

      await unmount(tester);
    });
  });
}
