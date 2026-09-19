import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/ui/screens/scales/laundry_tab.dart';

import '../helpers/test_helpers.dart';
import '../helpers/widget_test_helpers.dart';

// Aba Lavanderia.
//
// O bug que estes testes fixam: o estado vazio era um `RefreshableBox` dentro
// de uma lista de `slivers`. `RefreshableBox` é um `CustomScrollView`
// completo, não um sliver — compila, estoura no layout, e a aba aparecia em
// branco no aparelho. Nenhum teste de unidade pegaria isso; só montar a tela.

void main() {
  late AppDatabase db;

  setUp(() {
    db = createTestDatabase();
  });

  Future<void> seedMachine(String id, String name, {String? note}) async {
    await db.into(db.laundryMachineRows).insert(
          LaundryMachineRow(
            id: id,
            name: name,
            note: note,
            isActive: true,
            ordering: 1,
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
        );
  }

  Future<void> seedTimeSlot(String id, int startsAtMinutes) async {
    await db.into(db.laundryTimeSlotRows).insert(
          LaundryTimeSlotRow(
            id: id,
            startsAtMinutes: startsAtMinutes,
            endsAtMinutes: null,
            isActive: true,
            ordering: startsAtMinutes,
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
        );
  }

  Future<void> pumpTab(WidgetTester tester) async {
    await tester.pumpWidget(
      buildTestWidgetWithRouter(
        initialLocation: '/escalas',
        child: const LaundryTab(),
        db: db,
      ),
    );
    // Nunca pumpAndSettle: os StreamProviders do drift não assentam.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Ver a nota em `scale_tab_view_test.dart`: sem desmontar aqui, o timer que
  /// o drift agenda ao cancelar o stream vaza para fora do teste.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets('sem cadastro, mostra o aviso em vez de tela em branco',
      (tester) async {
    await pumpTab(tester);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('não foi configurada'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('com cadastro, desenha a grade de horários e máquinas',
      (tester) async {
    await seedMachine('m1', 'Máquina 1', note: 'grande');
    await seedMachine('m2', 'Máquina 2', note: 'pequena');
    await seedTimeSlot('t1', 5 * 60 + 30);
    await seedTimeSlot('t2', 7 * 60 + 30);

    await pumpTab(tester);

    expect(tester.takeException(), isNull);
    // Cabeçalho: as máquinas viram colunas.
    expect(find.text('Máquina 1'), findsOneWidget);
    expect(find.text('grande'), findsOneWidget);
    // Coluna da esquerda: os horários viram linhas.
    expect(find.text('05:30'), findsOneWidget);
    expect(find.text('07:30'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('célula sem reserva aparece como livre', (tester) async {
    await seedMachine('m1', 'Máquina 1');
    await seedTimeSlot('t1', 5 * 60 + 30);

    await pumpTab(tester);

    expect(find.text('Livre'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('horário marcado como intervalo não aparece como livre',
      (tester) async {
    await seedMachine('m1', 'Máquina 1');
    await seedTimeSlot('t1', 5 * 60 + 30);
    // O bloqueio é por dia da semana, e a grade abre no dia de hoje.
    await db.into(db.laundryBlockRows).insert(
          LaundryBlockRow(
            id: 'b1',
            machineId: 'm1',
            timeSlotId: 't1',
            weekday: DateTime.now().weekday,
            reason: null,
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
        );

    await pumpTab(tester);

    expect(find.text('Intervalo'), findsOneWidget);
    expect(find.text('Livre'), findsNothing);

    await unmount(tester);
  });
}
