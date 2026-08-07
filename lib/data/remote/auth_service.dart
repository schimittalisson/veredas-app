import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veredas/data/models/app_role.dart';

/// Estado de autenticação emitido pelo [AuthService].
///
/// `user` é null quando não há sessão. O `currentSession` dá acesso ao token
/// (necessário para chamadas autenticadas ao Supabase), mas a UI trabalha com
/// `user` — é o que determina "está logado".
class AuthState {
  const AuthState({this.session, this.user});

  final Session? session;
  final User? user;

  bool get isAuthenticated => user != null;

  static const AuthState unauthenticated =
      AuthState(session: null, user: null);
}

/// Serviço de autenticação abstrato.
///
/// O `PLANO.md §2.4` exige que cada fonte remota fique atrás de uma interface.
/// Isto torna os testes viáveis com uma `FakeAuthService` (sem rede) e permite
/// trocar a implementação sem tocar nas telas.
///
/// **Erros:** nenhum método devolve `AuthException` ou `PostgrestException` —
/// tudo é convertido para `AppException` pelo `error_mapper`. A UI escolhe a
/// mensagem do l10n a partir do `code`.
abstract class AuthService {
  /// Stream de mudanças de sessão. Emite o estado atual imediatamente ao
  /// inscrever, e depois a cada login/logout/refresh/token-expired.
  Stream<AuthState> get authStateChanges;

  /// Sessão atual, ou null se não logado.
  Session? get currentSession;

  /// Login com e-mail e senha.
  ///
  /// Se o e-mail não estiver confirmado e "Confirm email" estiver ativo no
  /// Supabase, o gotrue devolve `emailNotConfirmed` — o chamador decide se
  /// mostra "reenviar confirmação".
  Future<void> signIn({required String email, required String password});

  /// Cadastro com convite.
  ///
  /// Fluxo (PLANO.md Fase 3):
  /// 1. `auth.signUp(email, password, userMetadata: {'full_name': fullName})`
  ///    — o trigger `handle_new_user` cria o profile em `public.profiles`.
  /// 2. Se o `signUp` devolver sessão (email confirmation desativado), chama
  ///    `redeem_invite(code)` imediatamente → usuário aprovado.
  /// 3. Se o `signUp` **não** devolver sessão (email confirmation ativado),
  ///    o código do convite é guardado em `flutter_secure_storage` e resgatado
  ///    no primeiro `signIn` bem-sucedido.
  ///
  /// [phone] é opcional — guardado em `user_metadata` e copiado para o profile
  /// pelo app após o primeiro login (o trigger não lê phone).
  Future<void> signUpWithInvite({
    required String fullName,
    required String email,
    required String password,
    required String inviteCode,
    String? phone,
  });

  /// Resgata um convite pendente (guardado em secure storage do cadastro).
  ///
  /// Chamado no primeiro `signIn` bem-sucedido quando há um código pendente.
  /// Se o código for inválido, o usuário continua logado mas não aprovado —
  /// a tela `/aguardando` oferece "Tenho um código de convite" para tentar
  /// de novo.
  Future<AppRole?> redeemPendingInvite(String inviteCode);

  /// Há um convite pendente guardado no secure storage?
  Future<String?> getPendingInviteCode();

  /// Limpa o convite pendente (após resgate bem-sucedido ou desistência).
  Future<void> clearPendingInvite();

  /// Logout.
  Future<void> signOut();

  /// Apaga a conta do usuário logado e encerra a sessão.
  ///
  /// Exigência da Google Play para apps com cadastro: o usuário precisa
  /// conseguir sair do sistema sem depender de um administrador.
  ///
  /// Chama a RPC `delete_own_account`, que faz soft delete do perfil e do
  /// conteúdo autoral (ver a migration e o `PRIVACIDADE.md` §6). Lança
  /// `AppException` com `AppErrorCode.forbidden` quando o usuário é o único
  /// administrador ativo — a base não pode ficar sem quem aprove novos
  /// obreiros.
  Future<void> deleteOwnAccount();

  /// Envia e-mail de recuperação de senha.
  ///
  /// O e-mail contém um deep link de volta para o app
  /// (`br.com.veredas.app://login-callback/`).
  Future<void> resetPassword(String email);

  /// Reenvia o e-mail de confirmação de cadastro.
  Future<void> resendEmailConfirmation(String email);

  /// Atualiza o perfil do usuário logado no Supabase (nome, telefone, bio).
  ///
  /// Não passa pela outbox — é uma escrita direta ao `profiles` via RLS
  /// (policy `profiles_update_self`). A exceção ao "toda escrita passa pela
  /// outbox" é consciente: o profile é do próprio usuário, o conflito é
  /// impossível, e cachear otimistamente o próprio profile adiciona
  /// complexidade sem benefício.
  Future<void> updateProfile({
    String? fullName,
    String? phone,
    String? bio,
    String? avatarUrl,
  });
}
