import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'package:veredas/core/error/app_exception.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/models/app_role.dart';
import 'package:veredas/data/models/profile.dart';
import 'package:veredas/data/remote/auth_service.dart';
import 'package:veredas/data/remote/supabase_auth_service.dart';
import 'package:veredas/data/sync/sync_entity.dart';
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

/// Resgata o convite pendente e espera o perfil do usuário logado chegar ao
/// cache, antes de o router decidir entre `/aguardando` e `/inicio`.
///
/// **O bug que isto corrige.** O `currentProfileProvider` observa o drift, que
/// responde em milissegundos; o pull do servidor leva ~1-2s. Numa instalação
/// nova o cache está vazio no momento do login, então o stream emite `null` —
/// e `null` não é `isLoading`, é um dado. O router lia isso como "não
/// aprovado", mandava para `/aguardando`, e corrigia para `/inicio` quando o
/// pull terminava: a tela "aguardando aprovação" piscava por ~2 segundos para
/// um usuário aprovado.
///
/// Enquanto este provider está `isLoading`, o router mantém a splash.
///
/// Puxa só `profiles`, e não `pullAll()`: as 11 entidades são pulled em
/// sequência e a decisão de rota não depende das outras. O `SyncCoordinator`
/// continua responsável pelo pull completo.
final profileBootstrapProvider = FutureProvider<void>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return;

  final db = ref.watch(appDatabaseProvider);
  final cached = await (db.select(db.profileRows)
        ..where((t) => t.id.equals(userId)))
      .getSingleOrNull();
  // Já há perfil em cache: decidir na hora é correto, inclusive offline.
  if (cached != null) return;

  // Convite pendente do cadastro: resgatar **antes** do pull.
  //
  // O `redeem_invite` aprova o perfil no servidor, mas quem decide a rota é o
  // cache. Sem esta ordem, os dois disparam juntos assim que a sessão nasce —
  // o pull começa aqui, o resgate acontece dentro do `verifyEmailOtp` — e o
  // pull quase sempre chega primeiro, cacheando a linha ainda com
  // `is_approved = false`. Nada faz um segundo pull depois, então o obreiro
  // recém-aprovado ficava preso no /aguardando.
  //
  // Resgatar aqui também evita o piscar: enquanto este provider está
  // `isLoading` o router segura a splash, em vez de mostrar /aguardando e
  // corrigir para /inicio um instante depois.
  //
  // Duplicar o resgate com o do `verifyEmailOtp` é seguro: a RPC é idempotente
  // (se já aprovado, devolve o papel sem consumir outro uso do convite), e o
  // `clearPendingInvite` só roda depois de um resgate que deu certo — então
  // código ausente aqui significa resgate já concluído.
  final auth = ref.read(authServiceProvider);
  try {
    final pendingCode = await auth.getPendingInviteCode();
    if (pendingCode != null) {
      await auth.redeemPendingInvite(pendingCode);
      await auth.clearPendingInvite();
    }
  } catch (_) {
    // Convite expirado/revogado, ou storage seguro indisponível. Segue para o
    // pull: o usuário entra como não aprovado e o /aguardando oferece
    // "Tenho um código de convite".
  }

  final entity = syncEntityByName('profiles');
  if (entity == null) return;

  try {
    await ref.read(syncServiceProvider).pull(entity);
  } on AppException {
    // Offline, ou o servidor negou. Não sabemos se está aprovado, e prender o
    // usuário na splash por falha de rede é pior do que deixar o router
    // decidir com o cache que existe — o /aguardando tem "verificar novamente".
  }
  // retry desabilitado: este provider é um portão de navegação. Um retry com
  // backoff manteria `isLoading` alternando e a splash presa na tela.
}, retry: (count, error) => null);

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

  /// Devolve `true` se o cadastro já terminou (convite resgatado, sessão
  /// ativa); `false` se ainda falta confirmar o e-mail.
  Future<bool> signUpWithInvite({
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

  /// Confirma o e-mail com o código de 6 dígitos e resgata o convite pendente.
  Future<AppRole?> verifyEmailOtp({
    required String email,
    required String token,
  }) {
    return _auth.verifyEmailOtp(email: email, token: token);
  }

  Future<AppRole?> redeemInvite(String code) {
    return _auth.redeemPendingInvite(code);
  }

  Future<void> signOut() => _auth.signOut();

  /// Apaga a conta do usuário logado. O redirect do router leva para /login
  /// assim que a sessão cai.
  Future<void> deleteOwnAccount() => _auth.deleteOwnAccount();

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
