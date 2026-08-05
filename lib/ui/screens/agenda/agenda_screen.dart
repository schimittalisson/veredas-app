import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/ui/navigation/app_router.dart';
import 'package:veredas/ui/screens/agenda/events_tab.dart';
import 'package:veredas/ui/screens/agenda/schedule_tab.dart';

/// Tela Agenda — segunda tab.
///
/// `TabBar` de 2 abas no `AppBar` (`bottom`): **Eventos** | **Cronograma**
/// (`TELAS.md` §2). FAB só para admin, criando na aba ativa.
class AgendaScreen extends ConsumerStatefulWidget {
  const AgendaScreen({super.key});

  @override
  ConsumerState<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends ConsumerState<AgendaScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      // O tooltip e o destino do FAB dependem da aba ativa. Sem este
      // listener, trocar de aba não rebuilda e o tooltip fica descrevendo
      // a aba anterior.
      ..addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isAdmin = ref.watch(isAdminProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.tab_agenda),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l.agenda_tab_events),
            Tab(text: l.agenda_tab_schedule),
          ],
        ),
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton(
              onPressed: () {
                if (_tabController.index == 0) {
                  context.push(Routes.eventoNovo);
                } else {
                  context.push(Routes.slotNovo);
                }
              },
              tooltip: _tabController.index == 0
                  ? l.agenda_new_event
                  : l.agenda_new_slot,
              child: const Icon(Icons.add),
            )
          : null,
      body: TabBarView(
        controller: _tabController,
        children: [
          const EventsTab(),
          const ScheduleTab(),
        ],
      ),
    );
  }
}
