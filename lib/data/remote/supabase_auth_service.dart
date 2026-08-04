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
      ),
    );
  }

  @override
  Session? get currentSession => _client.auth.currentSession;

  @override
  Future<void> signIn({required String email, required String password}) async {
    try {
      await _client.auth.signInWithPassword(email: email, password: password);

      // Após o login bem-sucedido, verifica se há um convite pendente
      // (cadastro que exigiu confirmação de e-mail).
      final pendingCode = await getPendingInviteCode();
      if (pendingCode != null) {
        try {
          await redeemPendingInvite(pendingCode);
          await clearPendingInvite();
        } on AppException {
          // O convite pendente falhou (expirou, foi revogado etc.). O usuário
          // está logado mas não aprovado — a tela /aguardando oferece
          // "Tenho um código de convite" para tentar de novo. Não relança:
          // o login em si foi bem-sucedido.
        }
      }
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<void> signUpWithInvite({
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
        // Email confirmation desativado: há sessão imediatamente.
        // Resgata o convite agora.
        await _callRedeemInvite(inviteCode);
      } else {
        // Email confirmation ativado: não há sessão. Guarda o código para
        // resgatar no primeiro login.
        await _secureStorage.write(key: _pendingInviteKey, value: inviteCode);
      }
    } catch (e) {
      // Se o signUp falhou, não há nada a limpar — o usuário não foi criado.
      throw mapError(e);
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
