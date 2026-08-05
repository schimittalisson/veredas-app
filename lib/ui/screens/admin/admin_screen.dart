import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/l10n/app_localizations.dart';

/// Tela de Administração — menu de opções.
///
/// Acessível só para admin (guard no router **e** botão oculto na navigation
/// bar). É uma lista agrupada no estilo dos Ajustes do iPhone: cada linha leva
/// a uma sub-tela, com o chevron indicando a navegação.
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;

    final options = [
      _AdminOption(
        icon: CupertinoIcons.person_2,
        title: l.admin_members,
        subtitle: l.admin_members_desc,
        route: '/admin/membros',
      ),
      _AdminOption(
        icon: CupertinoIcons.mail,
        title: l.admin_invites,
        subtitle: l.admin_invites_desc,
        route: '/admin/convites',
      ),
      _AdminOption(
        icon: CupertinoIcons.person_badge_plus,
        title: l.admin_scale_managers,
        subtitle: l.admin_scale_managers_desc,
        route: '/admin/responsaveis',
      ),
      _AdminOption(
        icon: CupertinoIcons.info_circle,
        title: l.admin_base_data,
        subtitle: l.admin_base_data_desc,
        route: '/admin/base',
      ),
    ];

    return CupertinoPageScaffold(
      backgroundColor: colors.groupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(l.admin_title),
        backgroundColor: colors.elevatedSurface,
      ),
      child: SafeArea(
        bottom: false,
        child: ListView(
          children: [
            CupertinoListSection.insetGrouped(
              backgroundColor: colors.groupedBackground,
              separatorColor: colors.separator,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              children: options
                  .map((opt) => CupertinoListTile(
                        leading: Icon(opt.icon, color: colors.tint),
                        title: Text(
                          opt.title,
                          style: AppTypography.body.copyWith(
                            color: colors.label,
                          ),
                        ),
                        subtitle: Text(
                          opt.subtitle,
                          style: AppTypography.footnote.copyWith(
                            color: colors.secondaryLabel,
                          ),
                        ),
                        trailing: const CupertinoListTileChevron(),
                        onTap: () =>
                            // context.push, não Navigator.pushNamed: o app
                            // usa go_router, que não registra rotas nomeadas
                            // no Navigator — pushNamed lançaria
                            // "Could not find a generator for route".
                            context.push(opt.route),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminOption {
  const _AdminOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
}
