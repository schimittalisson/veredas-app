import 'dart:async';

import 'package:veredas/data/models/app_role.dart';
import 'package:veredas/data/remote/admin_service.dart';

/// [AdminService] que dispara um sync depois de cada ação que deu certo.
///
/// **Por que existe.** As ações de admin são RPC, não outbox: o servidor muda
/// e o cache do aparelho não fica sabendo. Antes disto, aprovar, remover ou
/// convidar alguém não mudava nada na tela até o próximo sync — que só vinha
/// ao reabrir o app ou ao arrastar para atualizar numa das abas. Ficar num
/// decorador, e não em cada tela, garante que uma ação nova não esqueça.
///
/// O sync roda **sem `await`**: a ação devolve assim que o servidor confirma,
/// e a lista se atualiza quando o pull termina. Uma falha de sync não é falha
/// da ação, que já aconteceu — quem a mostra é o banner de sincronização.
/// Consultas (`listRemovedMembers`) não disparam nada.
class SyncingAdminService implements AdminService {
  SyncingAdminService(this._inner, this._sync);

  final AdminService _inner;
  final Future<void> Function() _sync;

  Future<T> _thenSync<T>(Future<T> action) async {
    final result = await action;
    // O erro é engolido aqui porque ninguém espera este Future: sem o
    // handler, uma falha de rede viraria exceção não tratada na zona. O
    // `pullAll()` já registra a falha no estado que o banner mostra.
    unawaited(_sync().then((_) {}, onError: (_) {}));
    return result;
  }

  @override
  Future<void> setApproval({required String userId, required bool approved}) =>
      _thenSync(_inner.setApproval(userId: userId, approved: approved));

  @override
  Future<void> setRole({required String userId, required AppRole role}) =>
      _thenSync(_inner.setRole(userId: userId, role: role));

  @override
  Future<void> softDeleteUser({required String userId}) =>
      _thenSync(_inner.softDeleteUser(userId: userId));

  @override
  Future<List<RemovedMember>> listRemovedMembers() =>
      _inner.listRemovedMembers();

  @override
  Future<void> restoreMember({required String userId}) =>
      _thenSync(_inner.restoreMember(userId: userId));

  @override
  Future<CreatedInvite> createInvite({
    required AppRole role,
    int? maxUses,
    DateTime? expiresAt,
    String? note,
    String? code,
  }) =>
      _thenSync(_inner.createInvite(
        role: role,
        maxUses: maxUses,
        expiresAt: expiresAt,
        note: note,
        code: code,
      ));

  @override
  Future<CreatedInvite> updateInvite({
    required String inviteId,
    required String code,
    required AppRole role,
    int? maxUses,
    DateTime? expiresAt,
    String? note,
  }) =>
      _thenSync(_inner.updateInvite(
        inviteId: inviteId,
        code: code,
        role: role,
        maxUses: maxUses,
        expiresAt: expiresAt,
        note: note,
      ));

  @override
  Future<void> revokeInvite({required String inviteId}) =>
      _thenSync(_inner.revokeInvite(inviteId: inviteId));

  @override
  Future<void> addScaleManager({
    required String scaleTypeId,
    required String userId,
  }) =>
      _thenSync(
        _inner.addScaleManager(scaleTypeId: scaleTypeId, userId: userId),
      );

  @override
  Future<void> removeScaleManager({
    required String scaleTypeId,
    required String userId,
  }) =>
      _thenSync(
        _inner.removeScaleManager(scaleTypeId: scaleTypeId, userId: userId),
      );

  @override
  Future<void> addScheduleManager({
    required String schedule,
    required String userId,
  }) =>
      _thenSync(
        _inner.addScheduleManager(schedule: schedule, userId: userId),
      );

  @override
  Future<void> removeScheduleManager({
    required String schedule,
    required String userId,
  }) =>
      _thenSync(
        _inner.removeScheduleManager(schedule: schedule, userId: userId),
      );
}
