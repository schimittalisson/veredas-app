import 'package:veredas/data/models/app_role.dart';

/// Serviço de administração — operações que só admin pode fazer.
///
/// Todas as operações chamam RPCs do Supabase (security definer) que
/// validam `is_admin()` no servidor. A UI também verifica `isAdminProvider`
/// antes de mostrar os botões, mas a garantia real é a RPC.
abstract interface class AdminService {
  /// Aprova ou revoga o acesso de um obreiro.
  Future<void> setApproval({
    required String userId,
    required bool approved,
  });

  /// Promove a admin ou rebaixa a obreiro.
  ///
  /// O servidor impede que o admin rebaixe a si mesmo se for o único
  /// admin ativo (CANNOT_DEMOTE_LAST_ADMIN).
  Future<void> setRole({
    required String userId,
    required AppRole role,
  });

  /// Marca o perfil como removido (soft delete).
  ///
  /// Não exclui o auth.users — isso exige service_role. A exclusão física
  /// é feita manualmente via SQL Editor (LGPD).
  Future<void> softDeleteUser({required String userId});

  /// Cria um convite. Retorna o registro completo do convite criado.
  ///
  /// Se [code] for null, o servidor gera um automaticamente (6 chars
  /// alfanuméricos maiúsculos, sem 0/O/1/I).
  Future<CreatedInvite> createInvite({
    required AppRole role,
    required int maxUses,
    DateTime? expiresAt,
    String? note,
    String? code,
  });

  /// Revoga um convite (set revoked_at = now()).
  Future<void> revokeInvite({required String inviteId});

  /// Adiciona um obreiro como responsável por um tipo de escala.
  Future<void> addScaleManager({
    required String scaleTypeId,
    required String userId,
  });

  /// Remove um responsável de um tipo de escala.
  Future<void> removeScaleManager({
    required String scaleTypeId,
    required String userId,
  });
}

/// Resultado de `createInvite` — os campos que a UI precisa exibir.
class CreatedInvite {
  const CreatedInvite({
    required this.id,
    required this.code,
    required this.role,
    required this.maxUses,
    this.expiresAt,
    this.note,
  });

  final String id;
  final String code;
  final AppRole role;
  final int maxUses;
  final DateTime? expiresAt;
  final String? note;
}
