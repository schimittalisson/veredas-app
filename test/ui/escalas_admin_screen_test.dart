// `OrderingTerm` vem do drift; o `hide` evita a colisão com os matchers.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/ui/screens/admin/escalas_screen.dart';

import '../helpers/test_helpers.dart';
import '../helpers/widget_test_helpers.dart';

// Administração das escalas: a lista que define as abas da tela Escalas.
//
// O arrasto é a parte que só um teste de widget pega: o `onReorderItem` entrega
// o índice de destino já ajustado, e trocar isso por um `onReorder` (deprecado)
// reintroduz um erro de 1 que passa despercebido na leitura do código.

void main() {
  late AppDatabase db;

  setUp(() {
    db = createTestDatabase();
  });

  Future<void> seedType({
    required String id,
    required String name,
    required int ordering,
    bool isActive = true,
  }) async {
    await db.into(db.scaleTypeRows).insert(
          ScaleTypeRow(
            id: id,
            slug: id,
            name: name,
            cadence: 'weekly',
            slots: const [],
            ordering: ordering,
            isActive: isActive,
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
        );
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      buildTestWidgetWithRouter(
        initialLocation: '/admin/escalas',
        child: const EscalasScreen(),
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

  testWidgets('lista as escalas na ordem das abas, ocultas inclusive',
      (tester) async {
    await seedType(id: 'a', name: 'Servir ao Todo', ordering: 1);
    await seedType(id: 'b', name: 'Almoço', ordering: 2, isActive: false);

    await pumpScreen(tester);

    // A tela Escalas esconde a inativa; aqui ela precisa aparecer, marcada —
    // senão não há como reativá-la.
    expect(find.text('Servir ao Todo'), findsOneWidget);
    expect(find.text('Almoço'), findsOneWidget);
    expect(find.textContaining('oculta'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('arrastar a alça grava a nova ordem', (tester) async {
    await seedType(id: 'a', name: 'Primeira', ordering: 1);
    await seedType(id: 'b', name: 'Segunda', ordering: 2);
    await seedType(id: 'c', name: 'Terceira', ordering: 3);

    await pumpScreen(tester);

    // Arrasta a primeira para baixo de duas linhas. O gesto é feito à mão
    // (e não com `tester.drag`) porque o ReorderableList só entra em modo de
    // arrasto depois que o ponteiro se move com o dedo ainda na tela.
    final handle = find.byIcon(CupertinoIcons.line_horizontal_3).first;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.moveBy(const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final rows = await (db.select(db.scaleTypeRows)
          ..orderBy([(t) => OrderingTerm.asc(t.ordering)]))
        .get();
    expect(rows.map((r) => r.name), ['Segunda', 'Primeira', 'Terceira']);

    // E a escrita foi para a fila, não direto ao servidor.
    final entries = await db.select(db.outboxEntries).get();
    expect(entries.map((e) => e.entity).toSet(), {'scale_types'});

    await unmount(tester);
  });
}
