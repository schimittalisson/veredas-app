import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/infra_providers.dart';

/// Editor de evento — cria ou edita.
class EventEditorScreen extends ConsumerStatefulWidget {
  const EventEditorScreen({super.key, this.eventId});

  final String? eventId;

  @override
  ConsumerState<EventEditorScreen> createState() =>
      _EventEditorScreenState();
}

class _EventEditorScreenState extends ConsumerState<EventEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _categoryController = TextEditingController();
  DateTime _startsAt = DateTime.now().add(const Duration(hours: 1));
  DateTime? _endsAt;
  bool _allDay = false;
  bool _loaded = false;
  bool _saving = false;

  bool get _isEditing => widget.eventId != null;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _categoryController.dispose();
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
        title: Text(_isEditing ? l.action_edit : l.agenda_new_event),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: l.agenda_event_title_label,
                border: const OutlineInputBorder(),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? l.agenda_event_title_label : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: l.agenda_event_description_label,
                border: const OutlineInputBorder(),
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: Text(l.agenda_event_all_day),
              value: _allDay,
              onChanged: (v) => setState(() => _allDay = v),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.event),
              title: Text(l.agenda_event_starts_at),
              subtitle: Text(_formatDateTime(_startsAt)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickDateTime(context, isStart: true),
            ),
            if (!_allDay)
              ListTile(
                leading: const Icon(Icons.event_available),
                title: Text(l.agenda_event_ends_at),
                subtitle: Text(
                  _endsAt != null ? _formatDateTime(_endsAt!) : '—',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _pickDateTime(context, isStart: false),
              ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _locationController,
              decoration: InputDecoration(
                labelText: l.agenda_event_location,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _categoryController,
              decoration: InputDecoration(
                labelText: l.agenda_event_category,
                border: const OutlineInputBorder(),
              ),
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
    final row = await dao.getEvent(widget.eventId!);
    if (row != null && mounted) {
      _titleController.text = row.title;
      _descriptionController.text = row.description ?? '';
      _locationController.text = row.location ?? '';
      _categoryController.text = row.category ?? '';
      setState(() {
        _startsAt = row.startsAt;
        _endsAt = row.endsAt;
        _allDay = row.allDay;
        _loaded = true;
      });
    }
  }

  Future<void> _pickDateTime(BuildContext context, {required bool isStart}) async {
    final now = DateTime.now();
    final initial = isStart ? _startsAt : (_endsAt ?? _startsAt);

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;

    if (_allDay) {
      setState(() {
        if (isStart) {
          _startsAt = date;
        } else {
          _endsAt = date;
        }
      });
      return;
    }

    if (!mounted) return;
    final time = await showTimePicker(
      context: this.context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;

    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _startsAt = dt;
      } else {
        _endsAt = dt;
      }
    });
  }

  String _formatDateTime(DateTime dt) {
    final d = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    if (_allDay) {
      return '${d.day}/${d.month}/${d.year}';
    }
    return '${d.day}/${d.month}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final l = AppLocalizations.of(context);
    final repo = ref.read(agendaRepositoryProvider);

    try {
      if (_isEditing) {
        await repo.updateEvent(
          id: widget.eventId!,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          startsAt: _startsAt,
          endsAt: _endsAt,
          allDay: _allDay,
          location: _locationController.text.trim().isEmpty
              ? null
              : _locationController.text.trim(),
          category: _categoryController.text.trim().isEmpty
              ? null
              : _categoryController.text.trim(),
        );
      } else {
        await repo.createEvent(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          startsAt: _startsAt,
          endsAt: _endsAt,
          allDay: _allDay,
          location: _locationController.text.trim().isEmpty
              ? null
              : _locationController.text.trim(),
          category: _categoryController.text.trim().isEmpty
              ? null
              : _categoryController.text.trim(),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.agenda_event_saved)),
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
