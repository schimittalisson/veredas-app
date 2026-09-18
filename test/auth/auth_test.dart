import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/core/error/app_exception.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/models/app_role.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/infra_providers.dart';

import '../helpers/test_helpers.dart';

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
  });
  tearDown(() {
    container.dispose();
    auth.dispose();
    db.close();
  });

  group('AuthActions', () {
    test('signIn bem-sucedido emite AuthState autenticado', () async {
      await container.read(authActionsProvider.notifier).signIn(
            email: 'test@veredas.org',
            password: 'password123',
          );

      final state = await waitForAuthState(container, (s) => s.isAuthenticated);
      expect(state.isAuthenticated, true);
    });

    test('signIn com erro mapeia para AppException', () async {
      auth.signInError = makeAuthException(AppErrorCode.invalidCredentials);

      await expectLater(
        container.read(authActionsProvider.notifier).signIn(
              email: 'wrong@veredas.org',
              password: 'wrong',
            ),
        throwsA(predicate<AppException>(
          (e) => e.code == AppErrorCode.invalidCredentials,
        )),
      );
    });

    test('signUpWithInvite com sessão resgata o convite imediatamente',
        () async {
      auth.signUpReturnsSession = true;
      auth.redeemResult = AppRole.obreiro;

      await container.read(authActionsProvider.notifier).signUpWithInvite(
            fullName: 'Maria Silva',
            email: 'maria@veredas.org',
            password: 'password123',
            inviteCode: 'ABC123',
          );

      expect(auth.calls, contains('signUp:maria@veredas.org:ABC123'));
      expect(auth.calls, contains('redeem:ABC123'));
      expect(await auth.getPendingInviteCode(), isNull);
    });

    test('signUpWithInvite sem sessão guarda o convite para depois', () async {
      auth.signUpReturnsSession = false;

      await container.read(authActionsProvider.notifier).signUpWithInvite(
            fullName: 'João Silva',
            email: 'joao@veredas.org',
            password: 'password123',
            inviteCode: 'XYZ789',
          );

      expect(await auth.getPendingInviteCode(), 'XYZ789');
      expect(auth.calls.where((c) => c.startsWith('redeem:')), isEmpty);
    });

    test('verifyEmailOtp confirma e resgata o convite guardado no cadastro',
        () async {
      auth.signUpReturnsSession = false;
      auth.redeemResult = AppRole.obreiro;

      await container.read(authActionsProvider.notifier).signUpWithInvite(
            fullName: 'João Silva',
            email: 'joao@veredas.org',
            password: 'password123',
            inviteCode: 'XYZ789',
          );
      expect(await auth.getPendingInviteCode(), 'XYZ789');

      final role = await container
          .read(authActionsProvider.notifier)
          .verifyEmailOtp(email: 'joao@veredas.org', token: '482913');

      expect(role, AppRole.obreiro);
      expect(auth.calls, contains('verifyOtp:joao@veredas.org:482913'));
      expect(auth.calls, contains('redeem:XYZ789'));
      // O convite foi consumido: um segundo verify não pode resgatá-lo de novo.
      expect(await auth.getPendingInviteCode(), isNull);
    });

    test('verifyEmailOtp com código inválido mapeia para AppException',
        () async {
      auth.verifyOtpError = makeAuthException(AppErrorCode.otpExpired);

      await expectLater(
        container
            .read(authActionsProvider.notifier)
            .verifyEmailOtp(email: 'joao@veredas.org', token: '000000'),
        throwsA(isA<AppException>().having(
          (e) => e.code,
          'code',
          AppErrorCode.otpExpired,
        )),
      );
    });

    test('verifyEmailOtp com convite já expirado não derruba a confirmação',
        () async {
      auth.signUpReturnsSession = false;
      await container.read(authActionsProvider.notifier).signUpWithInvite(
            fullName: 'João Silva',
            email: 'joao@veredas.org',
            password: 'password123',
            inviteCode: 'XYZ789',
          );
      auth.redeemError = makeAuthException(AppErrorCode.inviteExpired);

      // O e-mail já foi confirmado neste ponto: relançar deixaria o usuário
      // preso na tela de código com a conta ativa. Ele segue para /aguardando.
      final role = await container
          .read(authActionsProvider.notifier)
          .verifyEmailOtp(email: 'joao@veredas.org', token: '482913');

      expect(role, isNull);
    });

    test('redeemPendingInvite devolve o papel', () async {
      auth.redeemResult = AppRole.admin;

      final role = await container
          .read(authActionsProvider.notifier)
          .redeemInvite('ADMIN123');

      expect(role, AppRole.admin);
    });

    test('redeemPendingInvite com erro mapeia para AppException', () async {
      auth.redeemError = makeAuthException(AppErrorCode.inviteExpired);

      await expectLater(
        container.read(authActionsProvider.notifier).redeemInvite('OLD'),
        throwsA(predicate<AppException>(
          (e) => e.code == AppErrorCode.inviteExpired,
        )),
      );
    });

    test('signOut emite AuthState não autenticado', () async {
      // Login primeiro.
      auth.simulateAuthenticated();
      await waitForAuthState(container, (s) => s.isAuthenticated);

      await container.read(authActionsProvider.notifier).signOut();

      final state =
          await waitForAuthState(container, (s) => !s.isAuthenticated);
      expect(state.isAuthenticated, false);
    });

    test('deleteOwnAccount encerra a sessão', () async {
      auth.simulateAuthenticated();
      await waitForAuthState(container, (s) => s.isAuthenticated);

      await container.read(authActionsProvider.notifier).deleteOwnAccount();

      // A sessão precisa cair junto com a exclusão: sem isso o usuário fica
      // preso na tela de "aguardando aprovação", porque o perfil já está
      // marcado como removido mas o token continua válido.
      final state =
          await waitForAuthState(container, (s) => !s.isAuthenticated);
      expect(state.isAuthenticated, false);
      expect(auth.calls, contains('deleteOwnAccount'));
    });

    test('deleteOwnAccount do último admin propaga forbidden', () async {
      auth.simulateAuthenticated();
      await waitForAuthState(container, (s) => s.isAuthenticated);

      // A RPC recusa quando sobraria a base sem nenhum admin ativo. A UI
      // depende do código para escolher a mensagem certa, então o erro não
      // pode chegar como PostgrestException cru.
      auth.deleteAccountError = const AppException(AppErrorCode.forbidden);

      await expectLater(
        container.read(authActionsProvider.notifier).deleteOwnAccount(),
        throwsA(isA<AppException>().having(
          (e) => e.code,
          'code',
          AppErrorCode.forbidden,
        )),
      );
    });
  });

  group('currentProfileProvider', () {
    test('devolve null quando não há usuário logado', () async {
      // Aguarda o authState inicial resolver.
      await waitForAuthState(container, (_) => true);
      await Future.delayed(Duration.zero);

      final profile = container.read(currentProfileProvider).value;
      expect(profile, isNull);
    });

    test('devolve o perfil do cache quando há usuário logado', () async {
      final userId = 'test-user-id';
      await db.into(db.profileRows).insert(
            ProfileRowsCompanion.insert(
              id: userId,
              fullName: 'Maria Silva',
              role: AppRole.obreiro,
              isApproved: const Value(true),
              updatedAt: DateTime.utc(2026, 1, 1),
            ),
          );

      // Ativa a subscription no currentProfileProvider antes de emitir.
      container.read(currentProfileProvider);

      auth.simulateAuthenticated(userId: userId);
      await waitForAuthState(container, (s) => s.isAuthenticated);

      final profile = await waitForProfile(container, (p) => p?.id == userId);
      expect(profile?.id, userId);
      expect(profile?.fullName, 'Maria Silva');
      expect(profile?.isApproved, true);
    });

    test('emite null quando o perfil não está no cache ainda', () async {
      auth.simulateAuthenticated(userId: 'no-profile-user');
      await waitForAuthState(container, (s) => s.isAuthenticated);
      await Future.delayed(Duration.zero);

      final profile = container.read(currentProfileProvider).value;
      expect(profile, isNull);
    });
  });

  // O bug: logo após o login numa instalação nova o cache está vazio, o
  // stream do drift emite `null` em milissegundos e o router lia isso como
  // "não aprovado" — mostrando /aguardando por ~2s antes de corrigir para
  // /inicio. Estes testes fixam o contrato que o redirect usa para esperar.
  group('profileBootstrapProvider', () {
    test('sem usuário logado resolve imediatamente e não busca nada', () async {
      await container.read(profileBootstrapProvider.future);

      expect(remote.calls, isEmpty);
    });

    test('perfil já em cache resolve sem ir à rede', () async {
      const userId = 'cached-user';
      await db.into(db.profileRows).insert(
            ProfileRowsCompanion.insert(
              id: userId,
              fullName: 'Maria Silva',
              role: AppRole.obreiro,
              isApproved: const Value(true),
              updatedAt: DateTime.utc(2026, 1, 1),
            ),
          );

      auth.simulateAuthenticated(userId: userId);
      await waitForAuthState(container, (s) => s.isAuthenticated);

      await container.read(profileBootstrapProvider.future);

      // Ir à rede aqui atrasaria a navegação de quem já tem cache — e
      // quebraria o login offline.
      expect(remote.calls, isEmpty);
    });

    test('cache vazio: fica loading até o perfil chegar do servidor', () async {
      const userId = 'fresh-user';
      remote.fetchData['profiles'] = [
        makeProfileJson(id: userId, fullName: 'Maria Silva', isApproved: true),
      ];

      auth.simulateAuthenticated(userId: userId);
      await waitForAuthState(container, (s) => s.isAuthenticated);

      // Estado exato em que o redirect precisa segurar a splash: perfil
      // resolvido como null (não é isLoading) e bootstrap ainda pendente.
      container.read(currentProfileProvider);
      final pending = container.read(profileBootstrapProvider.future);
      expect(container.read(profileBootstrapProvider).isLoading, true);

      await pending;

      final profile = await waitForProfile(container, (p) => p?.id == userId);
      expect(profile?.isApproved, true);
      expect(
        remote.calls.where((c) => c.table == 'profiles' && c.method == 'fetch'),
        hasLength(1),
      );
    });

    // O bug: o resgate do convite (dentro do `verifyEmailOtp`) e este pull
    // disparavam juntos assim que a sessão nascia, e o pull chegava primeiro —
    // cacheando `is_approved = false` um instante depois de o servidor ter
    // aprovado o perfil. Nada fazia um segundo pull, então o obreiro que
    // acabara de confirmar o e-mail ficava preso no /aguardando.
    test('resgata o convite pendente antes de puxar o perfil', () async {
      const userId = 'invited-user';

      // Estado do servidor antes do resgate.
      remote.fetchData['profiles'] = [
        makeProfileJson(id: userId, isApproved: false),
      ];

      // É isto que prova a **ordem**: o fake aprova o perfil "no servidor" no
      // instante do resgate, então o pull só enxerga `is_approved = true` se
      // tiver corrido depois dele. Invertendo a ordem, a expectativa falha.
      final invitedAuth = _AuthApprovingOnRedeem(() {
        remote.fetchData['profiles'] = [
          makeProfileJson(id: userId, isApproved: true),
        ];
      });
      addTearDown(invitedAuth.dispose);

      final invitedContainer = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWithValue(db),
        authServiceProvider.overrideWithValue(invitedAuth),
        remoteSourceProvider.overrideWithValue(remote),
      ]);
      addTearDown(invitedContainer.dispose);

      // Guarda o convite como o cadastro faz quando o e-mail exige confirmação.
      invitedAuth.signUpReturnsSession = false;
      await invitedAuth.signUpWithInvite(
        fullName: 'João Obreiro',
        email: 'joao@veredas.org',
        password: 'password123',
        inviteCode: 'XYZ789',
      );

      invitedAuth.simulateAuthenticated(userId: userId);
      await waitForAuthState(invitedContainer, (s) => s.isAuthenticated);

      await invitedContainer.read(profileBootstrapProvider.future);

      expect(invitedAuth.calls, contains('redeem:XYZ789'));
      expect(await invitedAuth.getPendingInviteCode(), isNull);

      final profile =
          await waitForProfile(invitedContainer, (p) => p?.id == userId);
      expect(profile?.isApproved, true);
    });

    test('cache vazio e rede falhando resolve em vez de travar', () async {
      const userId = 'offline-user';
      remote.fetchErrors['profiles'] = makeSocketException();

      auth.simulateAuthenticated(userId: userId);
      await waitForAuthState(container, (s) => s.isAuthenticated);

      // Não pode lançar nem ficar pendente: prender o usuário na splash por
      // falta de rede é pior do que mandá-lo para /aguardando, que tem o
      // botão "verificar novamente".
      await container.read(profileBootstrapProvider.future);

      expect(container.read(profileBootstrapProvider).hasError, false);
      expect(container.read(currentProfileProvider).value, isNull);
    });
  });

  group('isAdminProvider', () {
    test('true quando o perfil é admin aprovado', () async {
      final userId = 'admin-user';
      await db.into(db.profileRows).insert(
            ProfileRowsCompanion.insert(
              id: userId,
              fullName: 'Admin',
              role: AppRole.admin,
              isApproved: const Value(true),
              updatedAt: DateTime.utc(2026, 1, 1),
            ),
          );

      container.read(currentProfileProvider);
      auth.simulateAuthenticated(userId: userId);
      await waitForAuthState(container, (s) => s.isAuthenticated);
      await waitForProfile(container, (p) => p?.id == userId);

      expect(container.read(isAdminProvider), true);
    });

    test('false quando o perfil é obreiro', () async {
      final userId = 'obreiro-user';
      await db.into(db.profileRows).insert(
            ProfileRowsCompanion.insert(
              id: userId,
              fullName: 'Obreiro',
              role: AppRole.obreiro,
              isApproved: const Value(true),
              updatedAt: DateTime.utc(2026, 1, 1),
            ),
          );

      container.read(currentProfileProvider);
      auth.simulateAuthenticated(userId: userId);
      await waitForAuthState(container, (s) => s.isAuthenticated);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(container.read(isAdminProvider), false);
    });

    test('false quando admin não aprovado', () async {
      final userId = 'unapproved-admin';
      await db.into(db.profileRows).insert(
            ProfileRowsCompanion.insert(
              id: userId,
              fullName: 'Admin Pendente',
              role: AppRole.admin,
              isApproved: const Value(false),
              updatedAt: DateTime.utc(2026, 1, 1),
            ),
          );

      container.read(currentProfileProvider);
      auth.simulateAuthenticated(userId: userId);
      await waitForAuthState(container, (s) => s.isAuthenticated);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(container.read(isAdminProvider), false);
    });
  });
}

/// Fake que aprova o perfil "no servidor" no instante do resgate do convite.
///
/// Serve só ao teste de ordem do `profileBootstrapProvider`: sem um gancho no
/// momento exato do `redeem_invite`, o teste não conseguiria distinguir
/// "resgatou antes do pull" de "resgatou depois".
class _AuthApprovingOnRedeem extends FakeAuthService {
  _AuthApprovingOnRedeem(this.approveOnServer);

  final void Function() approveOnServer;

  @override
  Future<AppRole?> redeemPendingInvite(String inviteCode) {
    approveOnServer();
    return super.redeemPendingInvite(inviteCode);
  }
}
