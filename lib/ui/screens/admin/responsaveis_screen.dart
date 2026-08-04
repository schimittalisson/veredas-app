import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/admin_providers.dart';
import 'package:veredas/ui/widgets/empty_state.dart';

/// Tela de Responsáveis por escala — um ExpansionTile por scale_type.
///
/// Lista os responsáveis atuais com botão de remover, e "Adicionar
/// responsável" abrindo um seletor de obreiros aprovados.
class ResponsaveisScreen extends ConsumerWidget {
  const ResponsaveisScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final scaleTypes = ref.watch(allScaleTypesProvider);
    final managersByType = ref.watch(scaleManagersByTypeProvider);
    final profiles = ref.watch(approvedProfilesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.admin_scale_managers)),
      body: scaleTypes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_,_) => EmptyState(
          title: l.admin_managers_no_types,
          icon: Icons.assignment_ind_outlined,
        ),
        data: (types) {
          if (types.isEmpty) {
            return EmptyState(
              title: l.admin_managers_no_types,
              icon: Icons.assignment_ind_outlined,
            );
          }

          return ListView(
            children: types
                .map((type) => _ScaleTypeSection(
                      scaleType: type,
                      managers: managersByType[type.id] ?? const [],
                      profiles: profiles,
                    ))
                .toList(),
          );
        },
      ),
    );
  }
}

class _ScaleTypeSection extends ConsumerWidget {
  const _ScaleTypeSection({
    required this.scaleType,
    required this.managers,
    required this.profiles,
  });

  final ScaleTypeRow scaleType;
  final List<ScaleManagerRow> managers;
  final List<ProfileRow> profiles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);

    // Nomes dos responsáveis atuais.
    final managerProfiles = <ProfileRow>[];
    for (final m in managers) {
      final p = profiles.where((p) => p.id == m.userId).firstOrNull;
      if (p != null) managerProfiles.add(p);
    }

    return ExpansionTile(
      title: Text(scaleType.name),
      initiallyExpanded: true,
      children: [
        if (managerProfiles.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              l.admin_managers_none,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ...managerProfiles.map((p) => ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  _initials(p.fullName),
                  style: TextStyle(
                    color:
                        Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              title: Text(p.fullName),
              trailing: IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                tooltip: l.admin_managers_remove,
                onPressed: () {
                  // TODO: chamar RPC remove_scale_manager.
                },
              ),
            )),
        ListTile(
          leading: const Icon(Icons.add_circle_outline),
          title: Text(l.admin_managers_add),
          onTap: () => _showAddDialog(context, ref),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Future<void> _showAddDialog(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);

    // Obreiros aprovados que ainda não são responsáveis.
    final currentManagerIds = managers.map((m) => m.userId).toSet();
    final candidates = profiles
        .where((p) => !currentManagerIds.contains(p.id))
        .toList();

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.admin_managers_select)),
      );
      return;
    }

    await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.admin_managers_add),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: candidates
                .map((p) => ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            Theme.of(context).colorScheme.primaryContainer,
                        child: Text(
                          _initials(p.fullName),
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                        ),
                      ),
                      title: Text(p.fullName),
                      onTap: () {
                        // TODO: chamar RPC add_scale_manager.
                        Navigator.of(context).pop(p.id);
                      },
                    ))
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.action_cancel),
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    final first = parts.first.substring(0, 1);
    if (parts.length == 1) return first.toUpperCase();
    return (first + parts.last.substring(0, 1)).toUpperCase();
  }
}
