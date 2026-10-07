import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/data/models/app_role.dart';
import 'package:veredas/data/remote/admin_service.dart';
import 'package:veredas/data/remote/syncing_admin_service.dart';

// As ações de admin são RPC e não passam pela outbox: sem um sync depois, a
// tela de Membros (e as outras) não mudava ao remover, aprovar ou convidar.

class _FakeAdminService implements AdminService {
  Object? error;
  final calls = <String>[];

  Future<void> _call(String name) async {
    calls.add(name);
    if (error != null) throw error!;
  }

  @override
  Future<void> softDeleteUser({required String userId}) =>
      _call('softDeleteUser');

  @override
  Future<void> setRole({required String userId, required AppRole role}) =>
      _call('setRole');

  @override
  Future<List<RemovedMember>> listRemovedMembers() async {
    calls.add('listRemovedMembers');
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeAdminService inner;
  late int syncs;
  late SyncingAdminService service;

  setUp(() {
    inner = _FakeAdminService();
    syncs = 0;
    service = SyncingAdminService(inner, () async => syncs++);
  });

  test('ação que deu certo dispara o sync', () async {
    await service.softDeleteUser(userId: 'u1');
    await service.setRole(userId: 'u1', role: AppRole.obreiro);

    expect(inner.calls, ['softDeleteUser', 'setRole']);
    expect(syncs, 2);
  });

  test('ação recusada pelo servidor não sincroniza e repassa o erro',
      () async {
    inner.error = StateError('FORBIDDEN_NOT_ADMIN');

    await expectLater(
      service.softDeleteUser(userId: 'u1'),
      throwsA(isA<StateError>()),
    );
    expect(syncs, 0);
  });

  test('consulta não sincroniza', () async {
    await service.listRemovedMembers();

    expect(syncs, 0);
  });

  test('falha do sync não vira falha da ação', () async {
    service = SyncingAdminService(inner, () async => throw StateError('rede'));

    // A ação já aconteceu no servidor; quem mostra o erro de sync é o banner.
    await service.softDeleteUser(userId: 'u1');
  });
}
