import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/ui/widgets/empty_state.dart';

/// Tela Escalas — skeleton da Fase 2.
///
/// Conteúdo real na Fase 7 (`TELAS.md` §3): `TabBar` gerada dinamicamente a
/// partir de `scale_types`, com FAB visível só para quem gerencia o tipo.
class ScalesScreen extends ConsumerWidget {
  const ScalesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.tab_escalas)),
      body: EmptyState(
        title: l.tab_escalas,
        message: l.empty_default_message,
        icon: Icons.assignment_outlined,
      ),
    );
  }
}
