import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/l10n/app_localizations.dart';

/// Tela de Administração — menu de opções.
///
/// Acessível só para admin (guard no router **e** botão oculto no AppBar).
/// `ListView` de `ListTile` navegando para as sub-telas.
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);

    final options = [
      _AdminOption(
        icon: Icons.people_outline,
        title: l.admin_members,
        subtitle: l.admin_members_desc,
        route: '/admin/membros',
      ),
      _AdminOption(
        icon: Icons.mail_outline,
        title: l.admin_invites,
        subtitle: l.admin_invites_desc,
        route: '/admin/convites',
      ),
      _AdminOption(
        icon: Icons.assignment_ind_outlined,
        title: l.admin_scale_managers,
        subtitle: l.admin_scale_managers_desc,
        route: '/admin/responsaveis',
      ),
      _AdminOption(
        icon: Icons.info_outline,
        title: l.admin_base_data,
        subtitle: l.admin_base_data_desc,
        route: '/admin/base',
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l.admin_title)),
      body: ListView(
        children: options
            .map((opt) => ListTile(
                  leading: Icon(opt.icon),
                  title: Text(opt.title),
                  subtitle: Text(opt.subtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).pushNamed(opt.route),
                ))
            .toList(),
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
