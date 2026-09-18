import 'package:flutter/cupertino.dart';
// `TabController`/`TabBarView` moram na biblioteca Material e não têm
// equivalente Cupertino. Importamos só esses dois nomes: eles são pura
// mecânica de troca de página (nenhum pixel de Material aparece na tela), e
// trocá-los por um PageController exigiria mexer no estado da tela — o que
// esta migração de apresentação não deve fazer.
import 'package:flutter/material.dart' show TabBarView, TabController;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/ui/navigation/app_router.dart';
import 'package:veredas/ui/screens/agenda/events_tab.dart';
import 'package:veredas/ui/screens/agenda/schedule_tab.dart';

/// Tela Agenda — segunda tab.
///
/// Duas seções: **Eventos** | **Cronograma** (`docs/TELAS.md` §2), alternadas por um
/// `CupertinoSlidingSegmentedControl` logo abaixo da navigation bar — é assim
/// que o iOS troca de conteúdo dentro de uma mesma tela, já que não existe
/// `TabBar` no topo. Ação de criar só para admin, na aba ativa.
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
      // O destino da ação de criar e a posição do segmented control dependem
      // da aba ativa. Sem este listener, arrastar entre as páginas não
      // rebuilda e o controle continua marcando a aba anterior.
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
    final colors = context.colors;
    final isAdmin = ref.watch(isAdminProvider);

    final isEventsTab = _tabController.index == 0;
    final createLabel = isEventsTab ? l.agenda_new_event : l.agenda_new_slot;

    return CupertinoPageScaffold(
      backgroundColor: colors.groupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(l.tab_agenda),
        backgroundColor: colors.elevatedSurface,
        // O iOS não tem FAB: a ação primária da tela vive no canto direito da
        // navigation bar. `Semantics` preserva o texto que antes era o tooltip
        // do FAB, para o leitor de tela continuar anunciando o destino.
        trailing: isAdmin
            ? Semantics(
                button: true,
                label: createLabel,
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: () {
                    if (_tabController.index == 0) {
                      context.push(Routes.eventoNovo);
                    } else {
                      context.push(Routes.slotNovo);
                    }
                  },
                  child: const Icon(CupertinoIcons.add),
                ),
              )
            : null,
      ),
      child: SafeArea(
        // `bottom` fica ligado: o RootScaffold soma o espaço da barra
        // flutuante ao MediaQuery, e é isso que impede o último item da
        // lista de ficar escondido atrás dela.
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoSlidingSegmentedControl<int>(
                  groupValue: _tabController.index,
                  backgroundColor: colors.fill,
                  thumbColor: colors.surface,
                  onValueChanged: (value) {
                    if (value != null) _tabController.animateTo(value);
                  },
                  children: {
                    0: _SegmentLabel(text: l.agenda_tab_events),
                    1: _SegmentLabel(text: l.agenda_tab_schedule),
                  },
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  EventsTab(),
                  ScheduleTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _SegmentLabel
// ---------------------------------------------------------------------------

/// Rótulo de um segmento. Existe só para não repetir o padding vertical, que é
/// o que dá ao controle a altura de toque de 32 dp do iOS.
class _SegmentLabel extends StatelessWidget {
  const _SegmentLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        text,
        style: AppTypography.subheadlineEmphasis
            .copyWith(color: context.colors.label),
      ),
    );
  }
}
