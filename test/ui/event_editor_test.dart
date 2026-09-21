import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/models/app_role.dart';
import 'package:veredas/ui/screens/agenda/event_editor_screen.dart';

import '../helpers/test_helpers.dart';
import '../helpers/widget_test_helpers.dart';

// O editor de evento: o campo de fim no dia inteiro e a linha de excluir.
//
// Os dois eram pedidos diretos. O "Fim" era escondido quando "Dia inteiro"
// estava ligado, e com isso um evento de dia inteiro só podia durar um dia.
void main() {
  late AppDatabase db;
  late FakeAuthService auth;

  setUp(() {
    db = createTestDatabase();
    auth = FakeAuthService()..simulateAuthenticated(userId: 'u1');
  });

  /// Perfil de quem está logado. `events_admin_write` exige `is_admin()`, então
  /// a linha de excluir só aparece para admin — ver a nota no editor.
  Future<void> seedProfile({required AppRole role}) async {
    await db.into(db.profileRows).insert(
          ProfileRow(
            id: 'u1',
            fullName: 'Alisson',
            role: role,
            isApproved: true,
            updatedAt: DateTime(2026, 9, 1),
          ),
        );
  }

  Future<void> seedEvent({bool allDay = false, DateTime? endsAt}) async {
    await db.into(db.eventRows).insert(
          EventRow(
            id: 'ev-1',
            title: 'Retiro da base',
            startsAt: DateTime(2026, 9, 21, 19),
            endsAt: endsAt,
            allDay: allDay,
            updatedAt: DateTime(2026, 9, 1),
          ),
        );
  }

  Future<void> pumpEditor(WidgetTester tester, {String? eventId}) async {
    await tester.pumpWidget(
      buildTestWidget(
        db: db,
        auth: auth,
        child: EventEditorScreen(eventId: eventId),
      ),
    );
    // Nunca pumpAndSettle: os StreamProviders do drift não assentam.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Desmonta ainda dentro do teste — cancelar um stream do drift agenda um
  /// timer de duração zero. Ver a nota em `scale_tab_view_test.dart`.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets('dia inteiro mantém o campo de fim, com rótulo de data',
      (tester) async {
    await seedEvent(allDay: true, endsAt: DateTime(2026, 9, 23));

    await pumpEditor(tester, eventId: 'ev-1');

    // Sem o campo de fim não há como cadastrar um retiro de três dias — era
    // este o buraco.
    expect(find.text('Data de início'), findsOneWidget);
    expect(find.text('Data de fim'), findsOneWidget);
    // E o valor carregado é a data, sem hora.
    expect(find.text('23/9/2026'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('sem dia inteiro, os rótulos falam de horário', (tester) async {
    await seedEvent(endsAt: DateTime(2026, 9, 21, 22));

    await pumpEditor(tester, eventId: 'ev-1');

    expect(find.text('Início'), findsOneWidget);
    expect(find.text('Fim'), findsOneWidget);
    expect(find.text('Data de início'), findsNothing);

    await unmount(tester);
  });

  testWidgets('ligar o dia inteiro troca os rótulos sem esconder o fim',
      (tester) async {
    await seedEvent(endsAt: DateTime(2026, 9, 21, 22));

    await pumpEditor(tester, eventId: 'ev-1');
    await tester.tap(find.byType(CupertinoSwitch));
    await tester.pump();

    expect(find.text('Data de início'), findsOneWidget);
    expect(find.text('Data de fim'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('admin editando vê a linha de excluir', (tester) async {
    await seedProfile(role: AppRole.admin);
    await seedEvent();

    await pumpEditor(tester, eventId: 'ev-1');

    expect(find.text('Excluir evento'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('obreiro comum não vê a linha de excluir', (tester) async {
    // O cartão do evento abre este editor para qualquer obreiro. Oferecer
    // "excluir" a quem a policy vai recusar faria o evento sumir e voltar no
    // primeiro sync.
    await seedProfile(role: AppRole.obreiro);
    await seedEvent();

    await pumpEditor(tester, eventId: 'ev-1');

    expect(find.text('Excluir evento'), findsNothing);

    await unmount(tester);
  });

  testWidgets('criando, não há o que excluir', (tester) async {
    await seedProfile(role: AppRole.admin);

    await pumpEditor(tester);

    expect(find.text('Excluir evento'), findsNothing);

    await unmount(tester);
  });
}
