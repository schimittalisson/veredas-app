import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/ui/widgets/empty_state.dart';

/// Tela Início — skeleton da Fase 2.
///
/// Conteúdo real na Fase 5 (`TELAS.md` §1): aviso fixado, redes sociais,
/// acordeão de dados da base e avisos anteriores.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.tab_inicio)),
      body: EmptyState(
        title: l.tab_inicio,
        message: l.empty_default_message,
        icon: Icons.home_outlined,
      ),
    );
  }
}
