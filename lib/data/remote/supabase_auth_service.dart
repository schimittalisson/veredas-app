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
    return _client.auth.onAuthStateChange.map(
      (event) => AuthState(
        session: event.session,
        user: event.session?.user,
        event: event.event,
      ),
    );
  }

  @override
  Session? get currentSession => _client.auth.currentSession;

  @override
  Future<void> signIn({required String email, required String password}) async {
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
    } catch (e) {
      throw mapError(e);
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
