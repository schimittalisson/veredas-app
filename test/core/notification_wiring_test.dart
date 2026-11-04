import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/remote/push_messaging.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/providers/notification_providers.dart';

import '../helpers/test_helpers.dart';

// Como as notificações se ligam ao resto: o plano de lembretes sai do cache
// e some no logout, e o logout tira o aparelho do push antes de a sessão cair.

/// Registra a ordem das chamadas, junto com o `signOut` do FakeAuthService.
class _RecordingPush extends NoopPushMessaging {
  _RecordingPush(this.log, {this.id});

  final List<String> log;
  final String? id;

  @override
  String? get currentId => id;

  @override
  Future<void> unregister(String fid) async => log.add('unregister:$fid');

  @override
  Future<void> deleteRegistration() async => log.add('deleteRegistration');
}

class _LoggingAuth extends FakeAuthService {
  _LoggingAuth(this.log);
  final List<String> log;

  @override
  Future<void> signOut() async {
    log.add('signOut');
    await super.signOut();
  }
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = createTestDatabase();
    final ts = DateTime.utc(2026, 11, 1);
    await db.into(db.laundryMachineRows).insert(
          LaundryMachineRow(
            id: 'm1',
            name: 'Máquina grande',
            isActive: true,
            ordering: 0,
            updatedAt: ts,
          ),
        );
    await db.into(db.laundryTimeSlotRows).insert(
          LaundryTimeSlotRow(
            id: 's14',
            startsAtMinutes: 14 * 60,
            isActive: true,
            ordering: 0,
            updatedAt: ts,
          ),
        );
  });
  tearDown(() => db.close());

  Future<void> reserve(String id, String userId, DateTime day) =>
      db.into(db.laundryReservationRows).insert(
            LaundryReservationRow(
              id: id,
              machineId: 'm1',
              timeSlotId: 's14',
              onDate: DateTime(day.year, day.month, day.day),
              userId: userId,
              userName: userId,
              updatedAt: DateTime.utc(2026, 11, 1),
            ),
          );

  ProviderContainer container({required String? userId}) {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        currentUserIdProvider.overrideWithValue(userId),
        reminderClockProvider.overrideWithValue(
          () => DateTime(2026, 11, 4, 10),
        ),
      ],
    );
    addTearDown(c.dispose);
    c.listen(plannedLaundryRemindersProvider, (_, _) {});
    return c;
  }

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  group('plano de lembretes', () {
    test('só as reservas de quem está logado, e reage a reserva nova',
        () async {
      await reserve('minha', 'u-me', DateTime(2026, 11, 5));
      await reserve('alheia', 'u-other', DateTime(2026, 11, 5));
      final c = container(userId: 'u-me');
      await settle();

      expect(
        c.read(plannedLaundryRemindersProvider)!.map((p) => p.reservationId),
        ['minha'],
      );

      // Reserva que chega pelo sync (feita em outro aparelho).
      await reserve('do-outro-celular', 'u-me', DateTime(2026, 11, 6));
      await settle();
      expect(c.read(plannedLaundryRemindersProvider), hasLength(2));
    });

    test('sem login o plano é vazio — e é isso que cancela no logout',
        () async {
      await reserve('minha', 'u-me', DateTime(2026, 11, 5));
      final c = container(userId: null);
      await settle();

      expect(c.read(plannedLaundryRemindersProvider), isEmpty);
    });

    test('nulo enquanto carrega, para não cancelar tudo na abertura', () {
      final c = container(userId: 'u-me');
      // Antes de qualquer emissão do drift.
      expect(c.read(plannedLaundryRemindersProvider), isNull);
    });
  });

  group('logout', () {
    test('tira o aparelho do servidor antes de encerrar a sessão', () async {
      final log = <String>[];
      final c = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          authServiceProvider.overrideWithValue(_LoggingAuth(log)),
          pushMessagingProvider
              .overrideWithValue(_RecordingPush(log, id: 'fid-123')),
        ],
      );
      addTearDown(c.dispose);

      await c.read(authActionsProvider.notifier).signOut();

      // A RPC precisa do usuário logado: depois do signOut ela falharia.
      expect(log, ['unregister:fid-123', 'deleteRegistration', 'signOut']);
    });

    test('falha ao remover no servidor não impede o logout', () async {
      final log = <String>[];
      final c = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          authServiceProvider.overrideWithValue(_LoggingAuth(log)),
          pushMessagingProvider.overrideWithValue(_FailingPush(log)),
        ],
      );
      addTearDown(c.dispose);

      await c.read(authActionsProvider.notifier).signOut();

      expect(log, ['deleteRegistration', 'signOut']);
    });
  });
}

class _FailingPush extends _RecordingPush {
  _FailingPush(super.log) : super(id: 'fid-sem-rede');

  @override
  Future<void> unregister(String fid) =>
      Future.error(const SocketExceptionLike());
}

class SocketExceptionLike implements Exception {
  const SocketExceptionLike();
}
