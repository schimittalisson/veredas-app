import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/ui/widgets/empty_state.dart';

/// Mural de Oração — skeleton da Fase 2.
///
/// Conteúdo real na Fase 8 (`TELAS.md` §4): feed estilo Twitter, busca por
/// título com debounce e contador "estou orando".
class PrayerWallScreen extends ConsumerWidget {
  const PrayerWallScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.tab_oracao)),
      body: EmptyState(
        title: l.tab_oracao,
        message: l.empty_default_message,
        icon: Icons.favorite_outline,
      ),
    );
  }
}
