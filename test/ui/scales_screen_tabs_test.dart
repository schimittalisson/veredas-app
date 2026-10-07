import 'package:drift/drift.dart' show Value;
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/ui/screens/scales/scales_screen.dart';

import '../helpers/test_helpers.dart';
import '../helpers/widget_test_helpers.dart';

// O bug: com a Lavanderia aberta, puxar para sincronizar devolvia a tela para
// uma das escalas. O pull reescreve `scale_types` no cache, o stream emite uma
// lista nova (mesmo conteúdo), e o `didUpdateWidget` realinhava o controller
// com a última escala memorizada — que continuava valendo enquanto a
// Lavanderia estava aberta, porque ela não é uma escala.

void main() {
  late AppDatabase db;

  setUp(() => db = createTestDatabase());

  Future<void> seedType(String id, String name, int ordering) => db
      .into(db.scaleTypeRows)
      .insertOnConflictUpdate(
        ScaleTypeRow(
          id: id,
          slug: id,
          name: name,
          cadence: 'weekly',
          slots: const [],
          ordering: ordering,
          isActive: true,
          updatedAt: DateTime.utc(2026, 9, 1),
        ),
      );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets('a Lavanderia continua aberta quando o sync reemite as escalas', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await seedType('lixo', 'Lixo', 1);
    await seedType('almoco', 'Almoço', 2);

    await tester.pumpWidget(
      buildTestWidgetWithRouter(
        initialLocation: '/escalas',
        child: const ScalesScreen(),
        db: db,
      ),
    );
    await settle(tester);

    await tester.tap(find.text('Lavanderia'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('não foi configurada'), findsOneWidget);

    // O que o pull faz: regrava a linha, e o stream emite de novo.
    await (db.update(
      db.scaleTypeRows,
    )..where((t) => t.id.equals('lixo'))).write(
      ScaleTypeRowsCompanion(updatedAt: Value(DateTime.utc(2026, 10, 7))),
    );
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.textContaining('não foi configurada'), findsOneWidget);

    await unmount(tester);
  });
}
