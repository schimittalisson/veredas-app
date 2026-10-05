import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/models/app_role.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/ui/navigation/app_router.dart';

import '../helpers/test_helpers.dart';

// O aluno da ETED vê o app inteiro menos o mural de oração. A aba some da
// barra (ver root_scaffold_student_test.dart); aqui fica a outra metade: o
// router não o deixa chegar ao mural por deep link nem por rota empilhada.

void main() {
  late AppDatabase db;
  late FakeAuthService auth;
  late ProviderContainer container;

  setUp(() {
    db = createTestDatabase();
    auth = FakeAuthService();
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWith((ref) {
        ref.onDispose(db.close);
        return db;
      }),
      authServiceProvider.overrideWithValue(auth),
      remoteSourceProvider.overrideWithValue(FakeRemoteSource()),
    ]);
  });
  tearDown(() {
    container.dispose();
    auth.dispose();
    db.close();
  });

  Future<void> signInAs(AppRole role) async {
    await db.into(db.profileRows).insert(
          ProfileRow(
            id: 'test-user-id',
            fullName: 'Ana',
            role: role,
            isApproved: true,
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );
    auth.simulateAuthenticated();
    await waitForAuthState(container, (s) => s.isAuthenticated);
    await waitForProfile(container, (p) => p?.id == 'test-user-id');
  }

  String? redirect(String location) =>
      redirectForTest(container.read(refProvider), location);

  test('o papel aluno chega do servidor como aluno', () {
    expect(AppRole.fromWire('aluno'), AppRole.aluno);
  });

  group('aluno', () {
    test('não entra no mural, nem pelo editor nem pelos bloqueados',
        () async {
      await signInAs(AppRole.aluno);

      expect(redirect(Routes.oracao), Routes.inicio);
      expect(redirect(Routes.oracaoNovo), Routes.inicio);
      expect(redirect('${Routes.oracaoEditar}?id=x'), Routes.inicio);
      expect(redirect(Routes.bloqueados), Routes.inicio);
    });

    test('entra no resto do app', () async {
      await signInAs(AppRole.aluno);

      expect(redirect(Routes.inicio), isNull);
      expect(redirect(Routes.agenda), isNull);
      expect(redirect(Routes.escalas), isNull);
      expect(redirect(Routes.arquivos), isNull);
    });

    test('não entra na administração', () async {
      await signInAs(AppRole.aluno);

      expect(redirect(Routes.admin), Routes.inicio);
    });
  });

  test('obreiro continua entrando no mural', () async {
    await signInAs(AppRole.obreiro);

    expect(redirect(Routes.oracao), isNull);
    expect(redirect(Routes.bloqueados), isNull);
  });
}
