import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/models/app_role.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/admin_providers.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/ui/widgets/empty_state.dart';

/// Tela de Membros — lista de perfis com busca e ações administrativas.
///
/// Seção "Pendentes de aprovação" fixa no topo quando houver — é a ação
/// mais urgente do admin.
class MembrosScreen extends ConsumerStatefulWidget {
  const MembrosScreen({super.key});

  @override
  ConsumerState<MembrosScreen> createState() => _MembrosScreenState();
}

class _MembrosScreenState extends ConsumerState<MembrosScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _search = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      setState(() => _search = value.trim().toLowerCase());
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final profiles = ref.watch(allProfilesProvider).value ?? const [];
    final pending = ref.watch(pendingProfilesProvider);
    final currentUserId = ref.watch(currentUserIdProvider);

    // Filtra por busca.
    final filtered = _search.isEmpty
        ? profiles
        : profiles
            .where((p) => p.fullName.toLowerCase().contains(_search))
            .toList();

    // Conta admins ativos (para proteção de auto-rebaixamento).
    final activeAdmins =
        profiles.where((p) => p.role == AppRole.admin && p.isApproved).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.admin_members),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: l.admin_members_search,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
              ),
            ),
          ),
        ),
      ),
      body: profiles.isEmpty
          ? EmptyState(
              title: l.admin_no_members,
              icon: Icons.people_outline,
            )
          : ListView(
              children: [
                // Seção de pendentes no topo.
                if (pending.isNotEmpty && _search.isEmpty) ...[
                  _SectionHeader(title: l.admin_pending_section),
                  ...pending.map((p) => _MemberTile(
                        profile: p,
                        isSelf: p.id == currentUserId,
                        activeAdmins: activeAdmins,
                      )),
                  const Divider(),
                ],
                // Lista de todos os membros.
                ...filtered.map((p) => _MemberTile(
                      profile: p,
                      isSelf: p.id == currentUserId,
                      activeAdmins: activeAdmins,
                    )),
              ],
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({
    required this.profile,
    required this.isSelf,
    required this.activeAdmins,
  });

  final ProfileRow profile;
  final bool isSelf;
  final int activeAdmins;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final isAdmin = profile.role == AppRole.admin;
    // Proteção: não deixar o admin rebaixar/revogar a si mesmo se for o
    // único admin ativo. Isto trancaria a base fora da administração.
    final selfProtection = isSelf && isAdmin && activeAdmins <= 1;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Text(
          _initials(profile.fullName),
          style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
        ),
      ),
      title: Row(
        children: [
          Text(profile.fullName),
          if (!profile.isApproved) ...[
            const SizedBox(width: 8),
            Chip(
              label: Text(
                l.admin_pending_badge,
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onPrimary,
                ),
              ),
              backgroundColor: theme.colorScheme.primary,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
          ],
        ],
      ),
      subtitle: Text(profile.email ?? ''),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Chip(
            label: Text(
              isAdmin ? l.admin_role_admin : l.admin_role_obreiro,
              style: const TextStyle(fontSize: 11),
            ),
            visualDensity: VisualDensity.compact,
          ),
          PopupMenuButton<String>(
            onSelected: (value) => _handleAction(context, ref, value),
            itemBuilder: (context) => [
              if (!profile.isApproved)
                PopupMenuItem(
                  value: 'approve',
                  child: Text(l.admin_action_approve),
                ),
              if (profile.isApproved)
                PopupMenuItem(
                  value: 'revoke',
                  child: Text(l.admin_action_revoke),
                ),
              if (!isAdmin)
                PopupMenuItem(
                  value: 'promote',
                  child: Text(l.admin_action_promote),
                ),
              if (isAdmin && !selfProtection)
                PopupMenuItem(
                  value: 'demote',
                  child: Text(l.admin_action_demote),
                ),
              PopupMenuItem(
                value: 'remove',
                child: Text(l.admin_action_remove),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _handleAction(BuildContext context, WidgetRef ref, String action) {
    final l = AppLocalizations.of(context);

    final isAdmin = profile.role == AppRole.admin;
    final selfProtection = isSelf && isAdmin && activeAdmins <= 1;

    if (action == 'demote' || action == 'revoke') {
      if (selfProtection) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.admin_action_self_protection)),
        );
        return;
      }
    }

    // TODO: chamar RPCs do Supabase (set_approval, set_role, soft_delete).
    // Por ora, só mostra um SnackBar com a ação.
    final actionLabel = switch (action) {
      'approve' => l.admin_action_approve,
      'revoke' => l.admin_action_revoke,
      'promote' => l.admin_action_promote,
      'demote' => l.admin_action_demote,
      'remove' => l.admin_action_remove,
      _ => action,
    };

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$actionLabel: ${profile.fullName}')),
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
