import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/ui/widgets/empty_state.dart';
import 'package:veredas/ui/widgets/pull_to_refresh.dart';

import '../helpers/test_helpers.dart';
import '../helpers/widget_test_helpers.dart';

void main() {
  late AppDatabase db;
  late FakeRemoteSource remote;

  setUp(() {
    db = createTestDatabase();
    remote = FakeRemoteSource();
  });
  tearDown(() => db.close());

  List<dynamic> overrides() => [
        remoteSourceProvider.overrideWithValue(remote),
        connectivityCheckProvider.overrideWithValue(() async => true),
        connectivityStreamProvider.overrideWith(
          (ref) => Stream.value([ConnectivityResult.wifi]),
        ),
        // `hasPendingOutboxProvider` é um stream de query do drift, e o drift
        // agenda um timer de limpeza ao cancelar a subscription. Como isso
        // acontece no dispose do ProviderScope — depois do corpo do teste — o
        // binding acusa "A Timer is still pending" e a suíte trava. Trocar por
        // um stream simples evita o timer sem mudar o que está sob teste: o
        // valor só alimenta o rótulo do banner, não o gesto.
        hasPendingOutboxProvider.overrideWith((ref) => Stream.value(false)),
      ];

  /// Arrasta para baixo o suficiente para passar do limiar do
  /// `CupertinoSliverRefreshControl` (100 dp por padrão).
  Future<void> pullDown(WidgetTester tester, Finder target) async {
    await tester.drag(target, const Offset(0, 300), touchSlopY: 0);
    // Sem pumpAndSettle: os StreamProviders do drift nunca assentam
    // (ver widget_test_helpers.dart).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('RefreshableBox dispara o sync no arrasto', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      db: db,
      additionalOverrides: overrides(),
      child: const RefreshableBox(
        child: EmptyState(title: 'Nada aqui', icon: CupertinoIcons.heart),
      ),
    ));
    await tester.pump();

    expect(remote.calls, isEmpty);

    await pullDown(tester, find.text('Nada aqui'));

    // O sync buscou dados do servidor: é o efeito que o usuário espera do
    // gesto, e o que faltava quando a tela vazia não rolava.
    expect(
      remote.calls.where((c) => c.method == 'fetch'),
      isNotEmpty,
      reason: 'o arrasto deveria ter disparado o pull',
    );
  });

  testWidgets('SyncRefreshControl dispara o sync numa lista', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      db: db,
      additionalOverrides: overrides(),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SyncRefreshControl(),
          SliverList.list(
            children: const [
              SizedBox(height: 80, child: Text('item')),
            ],
          ),
        ],
      ),
    ));
    await tester.pump();

    await pullDown(tester, find.text('item'));

    expect(remote.calls.where((c) => c.method == 'fetch'), isNotEmpty);
  });

  testWidgets('sem arrasto, nenhum sync acontece', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      db: db,
      additionalOverrides: overrides(),
      child: const RefreshableBox(
        child: EmptyState(title: 'Nada aqui', icon: CupertinoIcons.heart),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Guarda contra o oposto do bug: o controle não deve sincronizar só por
    // existir na árvore — isso faria um pull a cada troca de aba.
    expect(remote.calls, isEmpty);
  });
}
