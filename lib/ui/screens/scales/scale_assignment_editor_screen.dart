import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/admin_providers.dart';
import 'package:veredas/providers/infra_providers.dart';

/// Editor de atribuição de escala — cria ou edita.
///
/// [scaleTypeId] é sempre necessário (define em qual escala a atribuição
/// será criada). [assignmentId] é null para criação.
class ScaleAssignmentEditorScreen extends ConsumerStatefulWidget {
  const ScaleAssignmentEditorScreen({
    super.key,
    required this.scaleTypeId,
    this.assignmentId,
  });

  final String scaleTypeId;
  final String? assignmentId;

  @override
  ConsumerState<ScaleAssignmentEditorScreen> createState() =>
      _ScaleAssignmentEditorScreenState();
}

class _ScaleAssignmentEditorScreenState
    extends ConsumerState<ScaleAssignmentEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _taskController = TextEditingController();
  final _assigneeNameController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime _date = DateTime.now();
  String? _slot;
  String? _assigneeId;
  bool _loaded = false;
  bool _saving = false;

  bool get _isEditing => widget.assignmentId != null;

  @override
  void dispose() {
    _taskController.dispose();
    _assigneeNameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    if (_isEditing && !_loaded) {
      _loadExisting();
    }

    // Slots disponíveis do scale_type.
    final scaleTypes = ref.watch(allScaleTypesProvider).value ?? const [];
    final scaleType =
        scaleTypes.where((t) => t.id == widget.scaleTypeId).firstOrNull;
    final slots = scaleType?.slots ?? const <String>[];

    // Obreiros aprovados para selecionar o atribuído.
    final profiles = ref.watch(approvedProfilesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? l.action_edit : l.scales_new_assignment),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: Text(l.scales_assignment_date),
              subtitle: Text(_formatDate(_date)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickDate(context),
            ),
            const SizedBox(height: 8),
            if (slots.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: _slot,
                decoration: InputDecoration(
                  labelText: l.scales_assignment_slot,
                  border: const OutlineInputBorder(),
                ),
                items: slots
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() => _slot = v),
              ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _taskController,
              decoration: InputDecoration(
                labelText: l.scales_assignment_task,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            // Seleção de obreiro: dropdown dos aprovados.
            DropdownButtonFormField<String>(
              initialValue: _assigneeId,
              decoration: InputDecoration(
                labelText: l.scales_assignment_assignee,
                border: const OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('—')),
                ...profiles.map(
                  (p) => DropdownMenuItem(value: p.id, child: Text(p.fullName)),
                ),
              ],
              onChanged: (v) => setState(() => _assigneeId = v),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _assigneeNameController,
              decoration: InputDecoration(
                labelText: l.scales_assignment_assignee_name,
                border: const OutlineInputBorder(),
                helperText: 'Use se a pessoa não tem conta no app',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              decoration: InputDecoration(
                labelText: l.scales_assignment_notes,
                border: const OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l.action_save),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadExisting() async {
    final dao = ref.read(scalesDaoProvider);
    final row = await dao.getAssignment(widget.assignmentId!);
    if (row != null && mounted) {
      _taskController.text = row.task ?? '';
      _assigneeNameController.text = row.assigneeName ?? '';
      _notesController.text = row.notes ?? '';
      setState(() {
        _date = row.startsOn;
        _slot = row.slot;
        _assigneeId = row.assigneeId;
        _loaded = true;
      });
    }
  }

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null && mounted) {
      setState(() => _date = picked);
    }
  }

  String _formatDate(DateTime dt) {
    final d = dt.toLocal();
    return '${d.day}/${d.month}/${d.year}';
  }

  Future<void> _save() async {
    // Valida: precisa de assigneeId OU assigneeName.
    if (_assigneeId == null &&
        _assigneeNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione um obreiro ou digite um nome.')),
      );
      return;
    }

    setState(() => _saving = true);
    final l = AppLocalizations.of(context);
    final repo = ref.read(scalesRepositoryProvider);

    try {
      if (_isEditing) {
        await repo.updateAssignment(
          id: widget.assignmentId!,
          scaleTypeId: widget.scaleTypeId,
          startsOn: _date,
          slot: _slot,
          task: _taskController.text.trim().isEmpty
              ? null
              : _taskController.text.trim(),
          assigneeId: _assigneeId,
          assigneeName: _assigneeNameController.text.trim().isEmpty
              ? null
              : _assigneeNameController.text.trim(),
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        );
      } else {
        await repo.createAssignment(
          scaleTypeId: widget.scaleTypeId,
          startsOn: _date,
          slot: _slot,
          task: _taskController.text.trim().isEmpty
              ? null
              : _taskController.text.trim(),
          assigneeId: _assigneeId,
          assigneeName: _assigneeNameController.text.trim().isEmpty
              ? null
              : _assigneeNameController.text.trim(),
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.scales_assignment_saved)),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
        setState(() => _saving = false);
      }
    }
  }
}
