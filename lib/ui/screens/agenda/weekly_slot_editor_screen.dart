import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/infra_providers.dart';

/// Editor de slot do cronograma semanal — cria ou edita.
class WeeklySlotEditorScreen extends ConsumerStatefulWidget {
  const WeeklySlotEditorScreen({super.key, this.slotId});

  final String? slotId;

  @override
  ConsumerState<WeeklySlotEditorScreen> createState() =>
      _WeeklySlotEditorScreenState();
}

class _WeeklySlotEditorScreenState
    extends ConsumerState<WeeklySlotEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _locationController = TextEditingController();
  final _categoryController = TextEditingController();
  final _notesController = TextEditingController();
  int _weekday = 1; // 1=segunda ... 7=domingo
  TimeOfDay _startsAt = const TimeOfDay(hour: 19, minute: 0);
  TimeOfDay? _endsAt;
  bool _loaded = false;
  bool _saving = false;

  bool get _isEditing => widget.slotId != null;

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _categoryController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    if (_isEditing && !_loaded) {
      _loadExisting();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? l.action_edit : l.agenda_new_slot),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<int>(
              initialValue: _weekday,
              decoration: InputDecoration(
                labelText: l.agenda_slot_weekday,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(value: 1, child: Text(l.agenda_weekday_mon)),
                DropdownMenuItem(value: 2, child: Text(l.agenda_weekday_tue)),
                DropdownMenuItem(value: 3, child: Text(l.agenda_weekday_wed)),
                DropdownMenuItem(value: 4, child: Text(l.agenda_weekday_thu)),
                DropdownMenuItem(value: 5, child: Text(l.agenda_weekday_fri)),
                DropdownMenuItem(value: 6, child: Text(l.agenda_weekday_sat)),
                DropdownMenuItem(value: 7, child: Text(l.agenda_weekday_sun)),
              ],
              onChanged: (v) => setState(() => _weekday = v ?? 1),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: l.agenda_slot_title_label,
                border: const OutlineInputBorder(),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? l.agenda_slot_title_label : null,
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.access_time),
              title: Text(l.agenda_slot_starts_at),
              subtitle: Text(_formatTime(_startsAt)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickTime(context, isStart: true),
            ),
            ListTile(
              leading: const Icon(Icons.access_time_filled),
              title: Text(l.agenda_slot_ends_at),
              subtitle: Text(
                _endsAt != null ? _formatTime(_endsAt!) : '—',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickTime(context, isStart: false),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _locationController,
              decoration: InputDecoration(
                labelText: l.agenda_slot_location,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _categoryController,
              decoration: InputDecoration(
                labelText: l.agenda_slot_category,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              decoration: InputDecoration(
                labelText: l.agenda_slot_notes,
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
    final dao = ref.read(agendaDaoProvider);
    final row = await dao.getWeeklySlot(widget.slotId!);
    if (row != null && mounted) {
      _titleController.text = row.title;
      _locationController.text = row.location ?? '';
      _categoryController.text = row.category ?? '';
      _notesController.text = row.notes ?? '';
      setState(() {
        _weekday = row.weekday;
        _startsAt = TimeOfDay(
          hour: row.startsAtMinutes ~/ 60,
          minute: row.startsAtMinutes % 60,
        );
        if (row.endsAtMinutes != null) {
          _endsAt = TimeOfDay(
            hour: row.endsAtMinutes! ~/ 60,
            minute: row.endsAtMinutes! % 60,
          );
        }
        _loaded = true;
      });
    }
  }

  Future<void> _pickTime(BuildContext context, {required bool isStart}) async {
    final initial = isStart ? _startsAt : (_endsAt ?? _startsAt);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startsAt = picked;
      } else {
        _endsAt = picked;
      }
    });
  }

  String _formatTime(TimeOfDay t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final l = AppLocalizations.of(context);
    final repo = ref.read(agendaRepositoryProvider);

    final startsAtMinutes = _startsAt.hour * 60 + _startsAt.minute;
    final endsAtMinutes = _endsAt != null ? _endsAt!.hour * 60 + _endsAt!.minute : null;

    try {
      if (_isEditing) {
        await repo.updateWeeklySlot(
          id: widget.slotId!,
          weekday: _weekday,
          startsAtMinutes: startsAtMinutes,
          endsAtMinutes: endsAtMinutes,
          title: _titleController.text.trim(),
          location: _locationController.text.trim().isEmpty
              ? null
              : _locationController.text.trim(),
          category: _categoryController.text.trim().isEmpty
              ? null
              : _categoryController.text.trim(),
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        );
      } else {
        await repo.createWeeklySlot(
          weekday: _weekday,
          startsAtMinutes: startsAtMinutes,
          endsAtMinutes: endsAtMinutes,
          title: _titleController.text.trim(),
          location: _locationController.text.trim().isEmpty
              ? null
              : _locationController.text.trim(),
          category: _categoryController.text.trim().isEmpty
              ? null
              : _categoryController.text.trim(),
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.agenda_slot_saved)),
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
