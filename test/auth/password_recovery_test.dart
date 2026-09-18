import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/models/app_role.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/ui/navigation/app_router.dart';

import '../helpers/test_helpers.dart';

// O bug: o link de recuperação de senha cria uma sessão (é ela que autoriza a
// troca), mas o app descartava o `AuthChangeEvent` e não sabia distinguir essa
// sessão de um login normal. Quem clicava no link caía logado em /inicio, sem
// nunca definir senha nova — a senha antiga seguia válida, e o acesso obtido
// pelo e-mail não expirava junto com o link.

void main() {
  late AppDatabase db;
  late FakeAuthService auth;
  late FakeRemoteSource remote;
  late ProviderContainer container;

  setUp(() {
    db = createTestDatabase();
    auth = FakeAuthService();
    remote = FakeRemoteSource();
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWith((ref) {
        ref.onDispose(db.close);
        return db;
      }),
      authServiceProvider.overrideWithValue(auth),
      remoteSourceProvider.overrideWithValue(remote),
    ]);
    // O router mantém este provider vivo desde o start do app; nos testes o
    // listen abaixo faz o mesmo papel.
    container.listen(passwordRecoveryProvider, (_, _) {},
        fireImmediately: true);
  });
  tearDown(() {
    container.dispose();
    auth.dispose();
    db.close();
  });

  Future<void> seedProfile({required bool isApproved}) async {
    await db.into(db.profileRows).insert(
          ProfileRow(
            id: 'test-user-id',
            fullName: 'Maria Silva',
            role: AppRole.obreiro,
            isApproved: isApproved,
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );
  }

  group('passwordRecoveryProvider', () {
    test('liga quando a sessão vem de um link de recuperação', () async {
      expect(container.read(passwordRecoveryProvider), false);

      auth.simulatePasswordRecovery();
      await waitForAuthState(container, (s) => s.isAuthenticated);

      expect(container.read(passwordRecoveryProvider), true);
    });

    test('continua ligado depois de um evento comum de sessão', () async {
      auth.simulatePasswordRecovery();
      await waitForAuthState(container, (s) => s.isAuthenticated);
      expect(container.read(passwordRecoveryProvider), true);

      // É o caso que derrubaria a proteção: o `passwordRecovery` chega uma vez
      // só, e o refresh de token acontece sozinho. Se o estado não grudasse, o
      // usuário seria jogado para /inicio no meio da digitação da senha nova.
      auth.simulateAuthenticated();
      await Future<void>.delayed(Duration.zero);

      expect(container.read(passwordRecoveryProvider), true);
    });

    test('desliga quando a sessão cai', () async {
      auth.simulatePasswordRecovery();
      await waitForAuthState(container, (s) => s.isAuthenticated);

      auth.simulateUnauthenticated();
      await waitForAuthState(container, (s) => !s.isAuthenticated);

      expect(container.read(passwordRecoveryProvider), false);
    });

    test('desliga depois de a senha ser trocada com sucesso', () async {
      auth.simulatePasswordRecovery();
      await waitForAuthState(container, (s) => s.isAuthenticated);

      await container
          .read(authActionsProvider.notifier)
          .updatePassword('senha-nova-123');

      expect(auth.calls, contains('updatePassword'));
      expect(container.read(passwordRecoveryProvider), false);
    });

    test('continua ligado se o servidor recusar a senha nova', () async {
      auth.simulatePasswordRecovery();
      await waitForAuthState(container, (s) => s.isAuthenticated);
      auth.updatePasswordError = makeSocketException();

      await expectLater(
        container.read(authActionsProvider.notifier).updatePassword('curta'),
        throwsA(anything),
      );

      // Falhou: o usuário precisa continuar na tela de senha nova.
      expect(container.read(passwordRecoveryProvider), true);
    });
  });

  group('redirect em modo recuperação', () {
    test('manda para /nova-senha vindo de qualquer rota', () async {
      await seedProfile(isApproved: true);
      auth.simulatePasswordRecovery();
      await waitForAuthState(container, (s) => s.isAuthenticated);
      await waitForProfile(container, (p) => p?.id == 'test-user-id');

      expect(redirectForTest(container.read(refProvider), Routes.inicio), Routes.novaSenha);
      expect(redirectForTest(container.read(refProvider), Routes.escalas), Routes.novaSenha);
      expect(redirectForTest(container.read(refProvider), Routes.admin), Routes.novaSenha);
    });

    test('deixa ficar quando já está em /nova-senha', () async {
      await seedProfile(isApproved: true);
      auth.simulatePasswordRecovery();
      await waitForAuthState(container, (s) => s.isAuthenticated);
      await waitForProfile(container, (p) => p?.id == 'test-user-id');

      expect(redirectForTest(container.read(refProvider), Routes.novaSenha), isNull);
    });

    test('não aprovado vai para /nova-senha, e não para /aguardando',
        () async {
      // A ordem das regras importa: mandar para /aguardando esconderia
      // justamente a tela que a pessoa precisa usar.
      await seedProfile(isApproved: false);
      auth.simulatePasswordRecovery();
      await waitForAuthState(container, (s) => s.isAuthenticated);
      await waitForProfile(container, (p) => p?.id == 'test-user-id');

      expect(redirectForTest(container.read(refProvider), Routes.inicio), Routes.novaSenha);
    });

    test('depois da troca, a rota volta ao normal', () async {
      await seedProfile(isApproved: true);
      auth.simulatePasswordRecovery();
      await waitForAuthState(container, (s) => s.isAuthenticated);
      await waitForProfile(container, (p) => p?.id == 'test-user-id');

      await container
          .read(authActionsProvider.notifier)
          .updatePassword('senha-nova-123');

      expect(redirectForTest(container.read(refProvider), Routes.inicio), isNull);
      expect(redirectForTest(container.read(refProvider), Routes.novaSenha), Routes.inicio);
    });

    test('login normal não desvia para /nova-senha', () async {
      await seedProfile(isApproved: true);
      auth.simulateAuthenticated();
      await waitForAuthState(container, (s) => s.isAuthenticated);
      await waitForProfile(container, (p) => p?.id == 'test-user-id');

      expect(redirectForTest(container.read(refProvider), Routes.inicio), isNull);
    });
  });
}
