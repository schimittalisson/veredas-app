import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/models/app_role.dart';
import 'package:veredas/data/models/profile.dart';
import 'package:veredas/data/remote/auth_service.dart';
import 'package:veredas/data/remote/supabase_auth_service.dart';
import 'package:veredas/providers/infra_providers.dart';

/// Provider do [AuthService]. Em testes, override com `FakeAuthService`.
final authServiceProvider = Provider<AuthService>((ref) {
  return SupabaseAuthService(ref.watch(supabaseClientProvider));
});

/// Stream do estado de autenticação.
///
/// Emite `AuthState.unauthenticated` como valor inicial e depois cada mudança
/// de sessão. A UI e o router observam este provider.
final authStateProvider = StreamProvider<AuthState>((ref) {
  final auth = ref.watch(authServiceProvider);
  // O Supabase emite o estado atual imediatamente ao inscrever em
  // onAuthStateChange, mas o StreamProvider precisa de um valor inicial
  // enquanto a primeira emissão não chega.
  return auth.authStateChanges;
});

/// O usuário logado, ou null.
///
/// Derivado do `authStateProvider` — não é um provider separado porque o
/// `User` já vem no `AuthState`.
final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authStateProvider).value?.user;
});

/// O ID do usuário logado, ou null. Conveniência para evitar `?.id` espalhado.
final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(currentUserProvider)?.id;
});

/// O perfil do usuário logado, lido do cache drift.
///
/// **Por que do cache e não do Supabase direto?** O app é offline-first: o
/// `SyncService` alimenta o cache, e a UI lê do cache. Se o dispositivo está
/// offline, o perfil ainda está disponível. O sync puxa `profiles`
/// incrementalmente, então o perfil local pode estar desatualizado por alguns
/// minutos — mas para a decisão "está aprovado?" isso é aceitável: a aprovação
/// é feita por um admin, e o usuário descobre no próximo sync.
///
/// Emite null quando não há usuário logado ou o perfil ainda não foi
/// sincronizado. O router trata esses casos.
final currentProfileProvider = StreamProvider<Profile?>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  final db = ref.watch(appDatabaseProvider);

  if (userId == null) {
    return Stream.value(null);
  }

  // Observa a linha do profile no drift. Quando o sync atualiza o cache,
  // este stream emite o novo perfil — e o router reavalia o redirect.
  return (db.select(db.profileRows)..where((t) => t.id.equals(userId)))
      .watchSingleOrNull()
      .map((row) => row?.toDomain());
});

/// Extensão que converte `ProfileRow` (drift) para `Profile` (freezed, domínio).
///
/// Fica aqui em vez de em `profile.dart` porque depende de `ProfileRow`, que é
/// gerado pelo drift — manter o modelo de domínio livre de dependências de
/// drift é mais limpo.
extension ProfileRowX on ProfileRow {
  Profile toDomain() {
    return Profile(
      id: id,
      fullName: fullName,
      email: email,
      phone: phone,
      avatarUrl: avatarUrl,
      bio: bio,
      role: role,
      isApproved: isApproved,
      updatedAt: updatedAt,
    );
  }
}

/// Notifier para ações de autenticação (login, cadastro, logout).
///
/// Não mantém estado — os métodos são ações que disparam mudanças no
/// `authStateProvider`. A UI chama e trata o erro com `try/catch`.
class AuthActions extends Notifier<void> {
  AuthService get _auth => ref.read(authServiceProvider);

  @override
  void build() {}

  Future<void> signIn({required String email, required String password}) {
    return _auth.signIn(email: email, password: password);
  }

  Future<void> signUpWithInvite({
    required String fullName,
    required String email,
    required String password,
    required String inviteCode,
    String? phone,
  }) {
    return _auth.signUpWithInvite(
      fullName: fullName,
      email: email,
      password: password,
      inviteCode: inviteCode,
      phone: phone,
    );
  }

  Future<AppRole?> redeemInvite(String code) {
    return _auth.redeemPendingInvite(code);
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> resetPassword(String email) => _auth.resetPassword(email);

  Future<void> resendEmailConfirmation(String email) =>
      _auth.resendEmailConfirmation(email);

  Future<void> updateProfile({
    String? fullName,
    String? phone,
    String? bio,
    String? avatarUrl,
  }) {
    return _auth.updateProfile(
      fullName: fullName,
      phone: phone,
      bio: bio,
      avatarUrl: avatarUrl,
    );
  }
}

final authActionsProvider =
    NotifierProvider<AuthActions, void>(AuthActions.new);

/// `true` se o usuário logado é admin aprovado. Conveniência para a UI
/// esconder/mostrar botões de admin.
final isAdminProvider = Provider<bool>((ref) {
  final profile = ref.watch(currentProfileProvider).value;
  return profile?.isAdmin ?? false;
});
