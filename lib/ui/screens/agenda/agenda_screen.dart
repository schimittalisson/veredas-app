import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/ui/widgets/empty_state.dart';

/// Tela Agenda — skeleton da Fase 2.
///
/// Conteúdo real na Fase 6 (`TELAS.md` §2): abas Eventos (com `TableCalendar`)
/// e Cronograma (a grade semanal em formato de planilha).
class AgendaScreen extends ConsumerWidget {
  const AgendaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.tab_agenda)),
      body: EmptyState(
        title: l.tab_agenda,
        message: l.empty_default_message,
        icon: Icons.calendar_month_outlined,
      ),
    );
  }
}
