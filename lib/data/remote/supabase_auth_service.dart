import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'package:veredas/core/error/app_exception.dart';
import 'package:veredas/core/error/error_mapper.dart';
import 'package:veredas/data/models/app_role.dart';
import 'package:veredas/data/remote/auth_service.dart';

/// Implementação de [AuthService] sobre o `SupabaseClient`.
///
/// O `supabase_flutter` já persiste a sessão automaticamente (em
/// `SharedPreferences` no Android, Keychain no iOS). Reabrir o app mantém o
/// login sem código extra.
class SupabaseAuthService implements AuthService {
  SupabaseAuthService(this._client, {FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final SupabaseClient _client;
  final FlutterSecureStorage _secureStorage;

  static const _pendingInviteKey = 'pending_invite_code';

  // O Supabase emite o estado inicial imediatamente ao inscrever. O map
  // converte `Session?` em `AuthState` — a UI não precisa saber que `Session`
  // existe.
  @override
  Stream<AuthState> get authStateChanges {
    return _client.auth.onAuthStateChange
        .map(
          (event) => AuthState(
            session: event.session,
            user: event.session?.user,
            event: event.event,
          ),
        )
        // Os erros de link saem por `authLinkErrors`. Aqui eles só fariam o
        // `authStateProvider` virar AsyncError, sem ninguém avisar a pessoa.
        .handleError(
          (Object _) {},
          test: (Object? e) => e != null && isAuthLinkError(e),
        );
  }

  @override
  Stream<AppErrorCode> get authLinkErrors =>
      _linkErrorsOf(_client.auth.onAuthStateChange);

  static Stream<AppErrorCode> _linkErrorsOf<T>(Stream<T> source) {
    return source.transform(
      StreamTransformer<T, AppErrorCode>.fromHandlers(
        handleData: (_, _) {},
        handleError: (error, _, sink) {
          if (isAuthLinkError(error)) sink.add(AppErrorCode.authLinkInvalid);
        },
      ),
    );
  }

  @override
  Session? get currentSession => _client.auth.currentSession;

  /// O `signUp` bateu num e-mail que já tem conta?
  ///
  /// Com a confirmação de e-mail ligada, o Supabase responde a um cadastro de
  /// e-mail existente **como se tivesse dado certo** e não envia e-mail
  /// nenhum — é a proteção dele contra descobrir quais e-mails existem. O
  /// sinal que sobra é o usuário voltar sem nenhuma identidade (forma de
  /// login) associada. Sem esta checagem, o app mostrava "confirme seu
  /// e-mail" e a pessoa esperava um código que nunca chegava — o caso típico
  /// é alguém removido da base tentando voltar.
  static bool signUpHitExistingAccount(User? user) {
    return user != null && (user.identities?.isEmpty ?? false);
  }

  /// Traduz o próprio perfil, lido logo depois do login, num motivo para
  /// barrar a entrada — ou `null` se a conta está ativa.
  ///
  /// `email` nulo distingue quem excluiu a própria conta (o
  /// `delete_own_account` apaga o e-mail) de quem foi removido por um admin.
  static AppErrorCode? removalCodeFor(Map<String, dynamic>? profile) {
    if (profile == null || profile['deleted_at'] == null) return null;
    return profile['email'] == null
        ? AppErrorCode.accountDeleted
        : AppErrorCode.accountRemoved;
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
    } catch (e) {
      throw mapError(e);
    }

    // Conta removida da base. O login no Supabase continua válido — só o
    // perfil foi marcado —, e sem esta checagem a pessoa caía em "aguardando
    // aprovação", esperando algo que nenhum admin ia fazer por ali. Encerra a
    // sessão e explica o que fazer.
    //
    // É a única exceção à regra abaixo de não relançar depois do login, e é
    // deliberada: a sessão é encerrada antes do throw, então a tela não fica
    // com um usuário logado por trás da mensagem de erro.
    final removal = await _removalOfCurrentUser();
    if (removal != null) {
      try {
        await _client.auth.signOut();
      } catch (_) {
        // Sem rede para avisar o servidor: a sessão local sai do mesmo jeito.
      }
      throw AppException(removal);
    }

    // Daqui para baixo o login **já aconteceu**: a sessão existe e o router vai
    // reagir a ela. Por isso nada abaixo pode relançar — um erro aqui viraria
    // "Ocorreu um erro inesperado" na tela de login de um usuário que, na
    // verdade, está autenticado.
    //
    // Foi esse o bug do primeiro beta no TestFlight: `getPendingInviteCode`
    // lê o Keychain, o build iOS não tinha a entitlement de Keychain Sharing,
    // e a PlatformException derrubava o login inteiro. No Android, que usa
    // EncryptedSharedPreferences, nunca aconteceu.
    try {
      final pendingCode = await getPendingInviteCode();
      if (pendingCode != null) {
        await redeemPendingInvite(pendingCode);
        await clearPendingInvite();
      }
    } catch (_) {
      // Convite expirado/revogado, ou storage seguro indisponível. Nos dois
      // casos o usuário está logado mas não aprovado, e a tela /aguardando
      // oferece "Tenho um código de convite" para tentar de novo.
    }
  }

  /// Lê o próprio perfil (a policy `profiles_select_self` deixa ver a linha
  /// mesmo removida) e devolve o motivo para barrar a entrada.
  ///
  /// Falha de rede aqui não barra ninguém: melhor deixar entrar e o perfil
  /// chegar pelo sync do que travar o login de quem está com sinal ruim.
  Future<AppErrorCode?> _removalOfCurrentUser() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    try {
      final row = await _client
          .from('profiles')
          .select('deleted_at, email')
          .eq('id', userId)
          .maybeSingle();
      return removalCodeFor(row);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> signUpWithInvite({
    required String fullName,
    required String email,
    required String password,
    required String inviteCode,
    String? phone,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
        },
      );

      // E-mail que já tem conta: nada foi criado nem enviado. Antes de
      // guardar o convite, que seria resgatado por engano no próximo login.
      if (signUpHitExistingAccount(response.user)) {
        throw const AppException(AppErrorCode.emailAlreadyRegistered);
      }

      final session = response.session;
      if (session != null) {
        // Email confirmation desativado: há sessão imediatamente. Resgata o
        // convite agora e o cadastro termina aqui.
        await _callRedeemInvite(inviteCode);
        return true;
      } else {
        // Email confirmation ativado: não há sessão. Guarda o código para
        // resgatar no primeiro login.
        //
        // Falha de storage aqui não invalida o cadastro — a conta foi criada.
        // Relançar mostraria "erro" para um cadastro que deu certo. O usuário
        // digita o código de novo na tela /aguardando.
        try {
          await _secureStorage.write(key: _pendingInviteKey, value: inviteCode);
        } catch (_) {
          // Sem convite guardado: o /aguardando pede o código de novo.
        }
        return false;
      }
    } catch (e) {
      // Se o signUp falhou, não há nada a limpar — o usuário não foi criado.
      throw mapError(e);
    }
  }

  @override
  Future<AppRole?> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    try {
      await _client.auth.verifyOTP(
        type: OtpType.signup,
        email: email,
        token: token,
      );
    } catch (e) {
      throw mapError(e);
    }

    // Mesma regra do `signIn`: daqui para baixo o e-mail **já foi confirmado**
    // e a sessão existe. Relançar transformaria um convite expirado, ou um
    // Keychain indisponível, em "erro" numa confirmação que deu certo — e o
    // usuário ficaria olhando a tela de código com a conta já ativa.
    try {
      final pendingCode = await getPendingInviteCode();
      if (pendingCode == null) return null;
      final role = await _callRedeemInvite(pendingCode);
      await clearPendingInvite();
      return role;
    } catch (_) {
      // O /aguardando oferece "Tenho um código de convite" para tentar de novo.
      return null;
    }
  }

  @override
  Future<AppRole?> redeemPendingInvite(String inviteCode) async {
    try {
      return await _callRedeemInvite(inviteCode);
    } catch (e) {
      throw mapError(e);
    }
  }

  /// Chama a RPC `redeem_invite` e converte o resultado para `AppRole`.
  ///
  /// A RPC devolve o papel como string ('admin' ou 'obreiro'). Se devolver
  /// null (não deveria acontecer), retorna null — o chamador trata como "não
  /// resgatado".
  Future<AppRole?> _callRedeemInvite(String code) async {
    final result = await _client.rpc(
      'redeem_invite',
      params: {'invite_code': code},
    );
    if (result == null) return null;
    return AppRole.fromWire(result.toString());
  }

  @override
  Future<String?> getPendingInviteCode() {
    return _secureStorage.read(key: _pendingInviteKey);
  }

  @override
  Future<void> clearPendingInvite() {
    return _secureStorage.delete(key: _pendingInviteKey);
  }

  @override
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  @override
  Future<void> deleteOwnAccount() async {
    try {
      await _client.rpc('delete_own_account');
    } catch (e) {
      // CANNOT_DELETE_LAST_ADMIN vem como PostgrestException com a mensagem
      // crua do `raise exception`. Traduzir aqui, e não na tela, mantém a
      // regra do AGENTS.md §6.6: exceção do Postgres não chega à UI.
      if (e.toString().contains('CANNOT_DELETE_LAST_ADMIN')) {
        throw const AppException(AppErrorCode.forbidden);
      }
      rethrow;
    }
    // A sessão precisa cair junto: o perfil já está marcado como removido, e
    // continuar logado deixaria o usuário preso na tela de "aguardando
    // aprovação" sem entender por quê.
    await _client.auth.signOut();
  }

  @override
  Future<void> resetPassword(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'br.com.veredas.app://login-callback/',
      );
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<void> verifyRecoveryOtp({
    required String email,
    required String token,
  }) async {
    try {
      // O gotrue emite `passwordRecovery` quando o tipo é `recovery` — é o que
      // liga o `passwordRecoveryProvider` e leva para /nova-senha.
      await _client.auth.verifyOTP(
        type: OtpType.recovery,
        email: email,
        token: token,
      );
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<void> resendEmailConfirmation(String email) async {
    try {
      await _client.auth.resend(
        type: OtpType.signup,
        email: email,
      );
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<void> updateProfile({
    String? fullName,
    String? phone,
    String? bio,
    String? avatarUrl,
  }) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        throw const AppException(AppErrorCode.notAuthenticated);
      }

      final updates = <String, dynamic>{};
      if (fullName != null) updates['full_name'] = fullName;
      if (phone != null) updates['phone'] = phone;
      if (bio != null) updates['bio'] = bio;
      if (avatarUrl != null) updates['avatar_url'] = avatarUrl;
      updates['updated_at'] = DateTime.now().toUtc().toIso8601String();

      if (updates.length == 1) return; // só updated_at, nada a mudar.

      await _client.from('profiles').update(updates).eq('id', userId);
    } catch (e) {
      throw mapError(e);
    }
  }
}
