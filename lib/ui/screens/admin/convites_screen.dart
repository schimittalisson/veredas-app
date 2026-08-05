import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/models/app_role.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/admin_providers.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/ui/widgets/empty_state.dart';

/// Tela de Convites — lista + FAB criar diálogo.
///
/// Código gerado automaticamente (6 caracteres alfanuméricos maiúsculos,
/// sem 0/O/1/I para evitar confusão ao ditar por telefone) e editável.
class ConvitesScreen extends ConsumerWidget {
  const ConvitesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final invites = ref.watch(allInvitesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.admin_invites)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateDialog(context, ref),
        tooltip: l.admin_invites_new,
        child: const Icon(Icons.add),
      ),
      body: invites.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_,_) => EmptyState(
          title: l.admin_no_invites,
          icon: Icons.mail_outline,
        ),
        data: (data) {
          if (data.isEmpty) {
            return EmptyState(
              title: l.admin_no_invites,
              icon: Icons.mail_outline,
            );
          }
          return ListView(
            children: data.map((invite) => _InviteTile(invite: invite)).toList(),
          );
        },
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final codeController = TextEditingController(text: _generateCode());
    final noteController = TextEditingController();
    final maxUsesController = TextEditingController(text: '1');
    AppRole role = AppRole.obreiro;
    DateTime? expiry;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l.admin_invite_create_title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: codeController,
                  decoration: InputDecoration(
                    labelText: l.admin_invite_code,
                    border: const OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AppRole>(
                  initialValue: role,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: AppRole.obreiro,
                      child: Text(l.admin_role_obreiro),
                    ),
                    DropdownMenuItem(
                      value: AppRole.admin,
                      child: Text(l.admin_role_admin),
                    ),
                  ],
                  onChanged: (v) => setState(() => role = v ?? AppRole.obreiro),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: maxUsesController,
                  decoration: InputDecoration(
                    labelText: l.admin_invite_max_uses,
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  decoration: InputDecoration(
                    labelText: l.admin_invite_note,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  title: Text(l.admin_invite_expiry_date),
                  subtitle: expiry != null
                      ? Text(DateFormat('dd/MM/yyyy').format(expiry!))
                      : Text(l.admin_invite_no_expiry),
                  trailing: const Icon(Icons.calendar_today_outlined),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now().add(const Duration(days: 30)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) setState(() => expiry = picked);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.action_cancel),
            ),
            FilledButton(
              onPressed: () async {
                final adminService = ref.read(adminServiceProvider);
                try {
                  await adminService.createInvite(
                    role: role,
                    maxUses: int.tryParse(maxUsesController.text) ?? 1,
                    expiresAt: expiry,
                    note: noteController.text.trim().isEmpty
                        ? null
                        : noteController.text.trim(),
                    code: codeController.text.trim().isEmpty
                        ? null
                        : codeController.text.trim().toUpperCase(),
                  );
                  if (context.mounted) Navigator.of(context).pop();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString())),
                    );
                  }
                }
              },
              child: Text(l.action_save),
            ),
          ],
        ),
      ),
    );
  }

  /// Gera um código de 6 caracteres alfanuméricos maiúsculos, sem 0/O/1/I
  /// para evitar confusão ao ditar por telefone.
  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final now = DateTime.now().microsecondsSinceEpoch;
    final rng = Random(now);
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }
}

class _InviteTile extends ConsumerWidget {
  const _InviteTile({required this.invite});

  final InviteRow invite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final status = _status(invite, l);
    final isRevoked = invite.revokedAt != null;
    final isExhausted = invite.uses >= invite.maxUses;
    final isExpired =
        invite.expiresAt != null && invite.expiresAt!.isBefore(DateTime.now());

    return ListTile(
      leading: Icon(
        isRevoked
            ? Icons.block
            : isExhausted
                ? Icons.check_circle_outline
                : isExpired
                    ? Icons.schedule_outlined
                    : Icons.mail_outline,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(
        invite.code,
        style: theme.textTheme.titleMedium?.copyWith(
          fontFamily: 'monospace',
          letterSpacing: 2,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${invite.role == AppRole.admin ? l.admin_role_admin : l.admin_role_obreiro} · '
            '${l.admin_invite_uses_format(invite.uses, invite.maxUses)}',
          ),
          if (invite.expiresAt != null)
            Text(
              '${l.admin_invite_expires}: ${DateFormat('dd/MM/yyyy').format(invite.expiresAt!)}',
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Chip(
            label: Text(
              status,
              style: TextStyle(
                fontSize: 11,
                color: isRevoked || isExhausted || isExpired
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.onPrimary,
              ),
            ),
            backgroundColor: isRevoked || isExhausted || isExpired
                ? theme.colorScheme.surfaceContainerHighest
                : theme.colorScheme.primary,
            visualDensity: VisualDensity.compact,
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'copy') {
                await Clipboard.setData(ClipboardData(text: invite.code));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l.admin_invite_copied)),
                );
              } else if (value == 'revoke') {
                try {
                  await ref.read(adminServiceProvider).revokeInvite(
                        inviteId: invite.id,
                      );
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString())),
                    );
                  }
                }
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'copy',
                child: Text(l.admin_invite_copy),
              ),
              if (!isRevoked)
                PopupMenuItem(
                  value: 'revoke',
                  child: Text(l.admin_invite_revoke),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _status(InviteRow invite, AppLocalizations l) {
    if (invite.revokedAt != null) return l.admin_invite_status_revoked;
    if (invite.uses >= invite.maxUses) return l.admin_invite_status_exhausted;
    if (invite.expiresAt != null &&
        invite.expiresAt!.isBefore(DateTime.now())) {
      return l.admin_invite_status_expired;
    }
    return l.admin_invite_status_active;
  }
}

/// Random simples para gerar o código — não precisa de crypto.
class Random {
  int _state;
  Random(this._state);

  int nextInt(int max) {
    // LCG simples, suficiente para gerar um código de 6 chars.
    _state = (1103515245 * _state + 12345) & 0x7FFFFFFF;
    return _state % max;
  }
}
