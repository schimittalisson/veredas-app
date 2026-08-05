import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veredas/core/error/app_exception.dart';
import 'package:veredas/core/error/error_mapper.dart';
import 'package:veredas/data/models/app_role.dart';
import 'package:veredas/data/remote/admin_service.dart';

/// Implementação de `AdminService` usando o cliente Supabase.
///
/// Todas as chamadas são RPCs (`supabase.rpc().invoke()`) que rodam como
/// `security definer` no servidor. Erros do Postgrest são convertidos para
/// `AppException` pelo `error_mapper`.
class SupabaseAdminService implements AdminService {
  SupabaseAdminService(this._client);

  final SupabaseClient _client;

  @override
  Future<void> setApproval({
    required String userId,
    required bool approved,
  }) async {
    try {
      await _client.rpc('set_approval', params: {
        'p_user_id': userId,
        'p_approved': approved,
      });
    } catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<void> setRole({
    required String userId,
    required AppRole role,
  }) async {
    try {
      await _client.rpc('set_role', params: {
        'p_user_id': userId,
        'p_role': role.name,
      });
    } catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<void> softDeleteUser({required String userId}) async {
    try {
      await _client.rpc('soft_delete_user', params: {
        'p_user_id': userId,
      });
    } catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<CreatedInvite> createInvite({
    required AppRole role,
    required int maxUses,
    DateTime? expiresAt,
    String? note,
    String? code,
  }) async {
    try {
      final result = await _client.rpc('create_invite', params: {
        'p_role': role.name,
        'p_max_uses': maxUses,
        'p_expires_at': expiresAt?.toIso8601String(),
        'p_note': note,
        'p_code': code,
      }) as Map<String, dynamic>;

      return CreatedInvite(
        id: result['id'] as String,
        code: result['code'] as String,
        role: AppRole.values.byName(result['role'] as String),
        maxUses: result['max_uses'] as int,
        expiresAt: result['expires_at'] != null
            ? DateTime.parse(result['expires_at'] as String)
            : null,
        note: result['note'] as String?,
      );
    } catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<void> revokeInvite({required String inviteId}) async {
    try {
      await _client.rpc('revoke_invite', params: {
        'p_invite_id': inviteId,
      });
    } catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<void> addScaleManager({
    required String scaleTypeId,
    required String userId,
  }) async {
    try {
      await _client.rpc('add_scale_manager', params: {
        'p_scale_type_id': scaleTypeId,
        'p_user_id': userId,
      });
    } catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<void> removeScaleManager({
    required String scaleTypeId,
    required String userId,
  }) async {
    try {
      await _client.rpc('remove_scale_manager', params: {
        'p_scale_type_id': scaleTypeId,
        'p_user_id': userId,
      });
    } catch (e) {
      throw _mapError(e);
    }
  }

  /// Converte erros do Postgrest/Supabase em `AppException`.
  ///
  /// As RPCs de admin levantam exceções com códigos específicos
  /// (FORBIDDEN_NOT_ADMIN, CANNOT_DEMOTE_LAST_ADMIN, etc.) que vêm no
  /// `message` do PostgrestException.
  AppException _mapError(Object e) {
    if (e is PostgrestException) {
      // O Postgrest coloca a mensagem da exceção PL/pgSQL no campo message.
      final msg = e.message;

      // Mapeia códigos específicos das RPCs de admin.
      if (msg.contains('FORBIDDEN_NOT_ADMIN')) {
        return const AppException(
          AppErrorCode.forbidden,
          debugMessage: 'Apenas administradores podem realizar esta operação.',
        );
      }
      if (msg.contains('CANNOT_DEMOTE_LAST_ADMIN')) {
        return const AppException(
          AppErrorCode.forbidden,
          debugMessage: 'Você não pode rebaixar a si mesmo se for o único admin.',
        );
      }
      if (msg.contains('CANNOT_DELETE_LAST_ADMIN')) {
        return const AppException(
          AppErrorCode.forbidden,
          debugMessage: 'Você não pode remover a si mesmo se for o único admin.',
        );
      }
      if (msg.contains('USER_NOT_FOUND')) {
        return const AppException(
          AppErrorCode.notFound,
          debugMessage: 'Usuário não encontrado.',
        );
      }
      if (msg.contains('USER_NOT_APPROVED')) {
        return const AppException(
          AppErrorCode.validation,
          debugMessage: 'O usuário selecionado não está aprovado.',
        );
      }
      if (msg.contains('INVITE_NOT_FOUND')) {
        return const AppException(
          AppErrorCode.notFound,
          debugMessage: 'Convite não encontrado.',
        );
      }
      if (msg.contains('SCALE_MANAGER_NOT_FOUND')) {
        return const AppException(
          AppErrorCode.notFound,
          debugMessage: 'Responsável não encontrado.',
        );
      }
      if (msg.contains('INVALID_MAX_USES')) {
        return const AppException(
          AppErrorCode.validation,
          debugMessage: 'Número de usos deve ser maior que zero.',
        );
      }
    }
    return mapError(e);
  }
}
