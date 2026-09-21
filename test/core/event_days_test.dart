import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/providers/agenda_providers.dart';
import 'package:veredas/providers/infra_providers.dart';

import '../helpers/test_helpers.dart';

/// Em quais dias um evento acontece.
///
/// O pedido: "caso um evento inicie em um dia e acabe somente em outro, ele
/// deve marcar, no calendário, todos os dias em que ocorre". Antes, a bolinha
/// e a lista do dia liam só `startsAt`, então os dias do meio e o último
/// ficavam vazios.
EventRow event({
  required DateTime startsAt,
  DateTime? endsAt,
  bool allDay = false,
}) {
  return EventRow(
    id: 'e1',
    title: 'Retiro',
    startsAt: startsAt,
    endsAt: endsAt,
    allDay: allDay,
    updatedAt: DateTime(2026, 9, 1),
  );
}

void main() {
  group('eventDayRange', () {
    test('sem fim, ocupa só o dia do início', () {
      final r = eventDayRange(event(startsAt: DateTime(2026, 9, 21, 19, 30)));
      expect(r.first, DateTime(2026, 9, 21));
      expect(r.last, DateTime(2026, 9, 21));
    });

    test('fim no mesmo dia, ocupa só aquele dia', () {
      final r = eventDayRange(event(
        startsAt: DateTime(2026, 9, 21, 19),
        endsAt: DateTime(2026, 9, 21, 22),
      ));
      expect(r.last, DateTime(2026, 9, 21));
    });

    test('atravessa dias e ocupa todos eles', () {
      final r = eventDayRange(event(
        startsAt: DateTime(2026, 9, 21, 19),
        endsAt: DateTime(2026, 9, 23, 8),
      ));
      expect(r.first, DateTime(2026, 9, 21));
      expect(r.last, DateTime(2026, 9, 23));
    });

    test('fim exatamente à meia-noite não alcança o dia seguinte', () {
      // 20:00 → 00:00 termina no instante em que o outro dia começa. Marcar o
      // dia 22 poria uma bolinha num dia em que nada acontece.
      final r = eventDayRange(event(
        startsAt: DateTime(2026, 9, 21, 20),
        endsAt: DateTime(2026, 9, 22),
      ));
      expect(r.last, DateTime(2026, 9, 21));
    });

    test('no dia inteiro, a meia-noite do fim É o último dia', () {
      // O editor grava a data de fim de um evento de dia inteiro à meia-noite
      // (a roda não pede hora). Descontar um dia aqui encurtaria um retiro de
      // 21 a 23 para 21 a 22.
      final r = eventDayRange(event(
        startsAt: DateTime(2026, 9, 21),
        endsAt: DateTime(2026, 9, 23),
        allDay: true,
      ));
      expect(r.first, DateTime(2026, 9, 21));
      expect(r.last, DateTime(2026, 9, 23));
    });

    test('fim antes do início não inverte o intervalo', () {
      final r = eventDayRange(event(
        startsAt: DateTime(2026, 9, 21, 10),
        endsAt: DateTime(2026, 9, 19, 10),
      ));
      expect(r.first, DateTime(2026, 9, 21));
      expect(r.last, DateTime(2026, 9, 21));
    });

    test('intervalo absurdo é capado em um ano', () {
      // Erro de digitação na data não pode pontilhar o calendário por anos:
      // "tem algo todo dia" não é informação.
      final r = eventDayRange(event(
        startsAt: DateTime(2026, 9, 21),
        endsAt: DateTime(2126, 9, 21),
      ));
      expect(r.last, DateTime(2027, 9, 21));
    });

    test('atravessa a virada do mês', () {
      final r = eventDayRange(event(
        startsAt: DateTime(2026, 9, 30, 8),
        endsAt: DateTime(2026, 10, 2, 18),
      ));
      expect(r.last, DateTime(2026, 10, 2));
    });
  });

  group('eventOccursOn', () {
    final retiro = event(
      startsAt: DateTime(2026, 9, 21, 19),
      endsAt: DateTime(2026, 9, 23, 8),
    );

    test('o dia do meio conta', () {
      expect(eventOccursOn(retiro, DateTime(2026, 9, 22)), isTrue);
    });

    test('o último dia conta', () {
      expect(eventOccursOn(retiro, DateTime(2026, 9, 23)), isTrue);
    });

    test('o dia anterior e o seguinte não contam', () {
      expect(eventOccursOn(retiro, DateTime(2026, 9, 20)), isFalse);
      expect(eventOccursOn(retiro, DateTime(2026, 9, 24)), isFalse);
    });

    test('a hora do dia consultado é ignorada', () {
      expect(eventOccursOn(retiro, DateTime(2026, 9, 22, 23, 59)), isTrue);
    });
  });

  group('daysWithEventsProvider', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() {
      db = createTestDatabase();
      container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
      ]);
    });
    tearDown(() {
      container.dispose();
      db.close();
    });

    Future<Set<DateTime>> daysAfterSeeding(List<EventRow> rows) async {
      for (final r in rows) {
        await db.into(db.eventRows).insert(r);
      }
      // Um StreamProvider sem ouvinte é descartado logo após o `read`, e então
      // `.future` nunca resolve.
      final sub = container.listen(allEventsProvider, (_, _) {});
      await container.read(allEventsProvider.future);
      final days = container.read(daysWithEventsProvider);
      sub.close();
      return days;
    }

    test('um evento de três dias marca os três', () async {
      final days = await daysAfterSeeding([
        event(
          startsAt: DateTime(2026, 9, 21, 19),
          endsAt: DateTime(2026, 9, 23, 8),
        ),
      ]);

      expect(days, {
        DateTime(2026, 9, 21),
        DateTime(2026, 9, 22),
        DateTime(2026, 9, 23),
      });
    });

    test('evento de um dia marca um dia só', () async {
      final days = await daysAfterSeeding([
        event(startsAt: DateTime(2026, 9, 21, 19)),
      ]);

      expect(days, {DateTime(2026, 9, 21)});
    });

    test('a expansão atravessa a virada do mês', () async {
      final days = await daysAfterSeeding([
        event(
          startsAt: DateTime(2026, 9, 30, 8),
          endsAt: DateTime(2026, 10, 2, 18),
        ),
      ]);

      expect(days, {
        DateTime(2026, 9, 30),
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 2),
      });
    });
  });
}
