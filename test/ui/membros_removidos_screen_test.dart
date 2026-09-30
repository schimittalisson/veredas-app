import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/remote/admin_service.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/ui/screens/admin/membros_removidos_screen.dart';

import '../helpers/test_helpers.dart';
import '../helpers/widget_test_helpers.dart';

// Restaurar quem foi removido. A lista vem do servidor (os removidos não
// entram no cache), e depois de restaurar a pessoa precisa voltar ao cache,
// senão a tela de Membros não a mostraria até o próximo sync.

class _FakeAdminService implements AdminService {
  final List<RemovedMember> removed = [
    RemovedMember(
      id: 'u-julia',
      fullName: 'Julia Fernandes',
      email: 'julia@teste.com',
      deletedAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
  ];
  final List<String> restored = [];

  @override
  Future<List<RemovedMember>> listRemovedMembers() async => List.of(removed);

  @override
  Future<void> restoreMember({required String userId}) async {
    restored.add(userId);
    removed.removeWhere((m) => m.id == userId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;
  late _FakeAdminService admin;
  late FakeRemoteSource remote;

  setUp(() {
    db = createTestDatabase();
    admin = _FakeAdminService();
    remote = FakeRemoteSource();
  });

  testWidgets('restaurar pede confirmação, some da lista e volta ao cache',
      (tester) async {
    // O que o servidor devolve no pull de profiles depois da restauração.
    remote.fetchData['profiles'] = [
      makeProfileJson(
        id: 'u-julia',
        fullName: 'Julia Fernandes',
        role: 'obreiro',
        isApproved: true,
      ),
    ];

    await tester.pumpWidget(
      buildTestWidgetWithRouter(
        initialLocation: '/admin/membros/removidos',
        child: const MembrosRemovidosScreen(),
        db: db,
        additionalOverrides: [
          adminServiceProvider.overrideWithValue(admin),
          remoteSourceProvider.overrideWithValue(remote),
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Julia Fernandes'), findsOneWidget);

    await tester.tap(find.text('Restaurar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Restaurar Julia Fernandes?'), findsOneWidget);
    expect(admin.restored, isEmpty);

    await tester.tap(find.widgetWithText(CupertinoDialogAction, 'Restaurar'));
    // Restaurar, puxar `profiles` para o drift e recarregar a lista leva
    // várias voltas do event loop; espera pela condição, não por um tempo.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('Nenhum membro removido.').evaluate().isNotEmpty) break;
    }

    expect(admin.restored, ['u-julia']);
    expect(find.text('Acesso restaurado.'), findsOneWidget);
    expect(find.text('Nenhum membro removido.'), findsOneWidget);
    final cached = await db.select(db.profileRows).get();
    expect(cached.map((p) => p.id), ['u-julia']);

    await tester.pump(const Duration(seconds: 4)); // timer do toast
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
