import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/providers/laundry_providers.dart';
import 'package:veredas/ui/widgets/confirm_dialog.dart';

/// Administração da lavanderia — o cadastro que define a grade.
///
/// Só máquinas e faixas de horário moram aqui. Os **intervalos** são marcados
/// direto na grade da aba Lavanderia, tocando a célula: bloquear "máquina 2,
/// terça, 09:00" numa lista abstrata exigiria escolher três coisas de cabeça,
/// enquanto na grade é o lugar onde a informação já está na frente dos olhos.
class LavanderiaScreen extends ConsumerWidget {
  const LavanderiaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final machines = ref.watch(laundryAllMachinesProvider).value ?? const [];
    final timeSlots = ref.watch(laundryAllTimeSlotsProvider).value ?? const [];

    return CupertinoPageScaffold(
      backgroundColor: colors.groupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(l.laundry_admin_title),
        backgroundColor: colors.elevatedSurface,
      ),
      child: SafeArea(
        child: ListView(
          children: [
            _SectionHeader(title: l.laundry_admin_machines),
            for (final m in machines)
              _Tile(
                title: m.name,
                subtitle: m.note,
                onDelete: () => _deleteMachine(context, ref, m),
              ),
            _AddButton(
              label: l.laundry_admin_new_machine,
              onPressed: () => _addMachine(context, ref),
            ),
            _SectionHeader(title: l.laundry_admin_times),
            for (final s in timeSlots)
              _Tile(
                title: _formatMinutes(s.startsAtMinutes),
                subtitle: s.endsAtMinutes != null
                    ? '→ ${_formatMinutes(s.endsAtMinutes!)}'
                    : null,
                onDelete: () => _deleteTimeSlot(context, ref, s),
              ),
            _AddButton(
              label: l.laundry_admin_new_time,
              onPressed: () => _addTimeSlot(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addMachine(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final nameController = TextEditingController();
    final noteController = TextEditingController();

    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      // Há texto digitado: fechar no toque fora perderia o que foi escrito.
      barrierDismissible: false,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(l.laundry_admin_new_machine),
        content: Column(
          children: [
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: nameController,
              placeholder: l.laundry_admin_machine_name,
              autofocus: true,
            ),
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: noteController,
              placeholder: l.laundry_admin_machine_note,
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l.action_cancel),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l.action_save),
          ),
        ],
      ),
    );

    final name = nameController.text.trim();
    final note = noteController.text.trim();
    nameController.dispose();
    noteController.dispose();
    if (confirmed != true || name.isEmpty || !context.mounted) return;

    await ref.read(laundryRepositoryProvider).createMachine(
          name: name,
          note: note.isEmpty ? null : note,
        );
  }

  Future<void> _deleteMachine(
    BuildContext context,
    WidgetRef ref,
    LaundryMachineRow machine,
  ) async {
    final l = AppLocalizations.of(context);
    final ok = await ConfirmDialog.show(
      context,
      title: machine.name,
      message: l.laundry_admin_delete_machine_confirm,
      isDestructive: true,
    );
    if (ok != true) return;
    await ref.read(laundryRepositoryProvider).deleteMachine(machine.id);
  }

  Future<void> _addTimeSlot(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    var minutes = 6 * 60;

    final confirmed = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (sheetContext) => Container(
        height: 260,
        color: context.colors.surface,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: CupertinoButton(
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  child: Text(l.action_done),
                ),
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  initialDateTime: DateTime(2026, 1, 1, 6),
                  use24hFormat: true,
                  minuteInterval: 5,
                  onDateTimeChanged: (d) => minutes = d.hour * 60 + d.minute,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await ref
        .read(laundryRepositoryProvider)
        .createTimeSlot(startsAtMinutes: minutes);
  }

  Future<void> _deleteTimeSlot(
    BuildContext context,
    WidgetRef ref,
    LaundryTimeSlotRow slot,
  ) async {
    final l = AppLocalizations.of(context);
    final ok = await ConfirmDialog.show(
      context,
      title: _formatMinutes(slot.startsAtMinutes),
      message: l.laundry_admin_delete_time_confirm,
      isDestructive: true,
    );
    if (ok != true) return;
    await ref.read(laundryRepositoryProvider).deleteTimeSlot(slot.id);
  }

  static String _formatMinutes(int minutes) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(minutes ~/ 60)}:${two(minutes % 60)}';
  }
}

// ---------------------------------------------------------------------------
// _SectionHeader
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        title.toUpperCase(),
        style: AppTypography.sectionHeader.copyWith(color: colors.secondaryLabel),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _Tile
// ---------------------------------------------------------------------------

class _Tile extends StatelessWidget {
  const _Tile({required this.title, this.subtitle, required this.onDelete});

  final String title;
  final String? subtitle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      color: colors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      margin: const EdgeInsets.only(bottom: 1),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppTypography.body.copyWith(color: colors.label)),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    style: AppTypography.footnote
                        .copyWith(color: colors.secondaryLabel),
                  ),
              ],
            ),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: onDelete,
            child: Icon(CupertinoIcons.trash,
                size: 20, color: colors.destructive),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _AddButton
// ---------------------------------------------------------------------------

class _AddButton extends StatelessWidget {
  const _AddButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      color: colors.surface,
      child: CupertinoButton(
        onPressed: onPressed,
        child: Row(
          children: [
            Icon(CupertinoIcons.add, size: 20, color: colors.tint),
            const SizedBox(width: 8),
            Text(label, style: AppTypography.body.copyWith(color: colors.tint)),
          ],
        ),
      ),
    );
  }
}
