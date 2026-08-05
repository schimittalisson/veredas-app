import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/home_providers.dart';
import 'package:veredas/providers/infra_providers.dart';

/// Editor de aviso — cria ou edita.
///
/// Se [announcementId] for null, é criação. Se for fornecido, carrega o aviso
/// existente do cache para preencher os campos.
class AnnouncementEditorScreen extends ConsumerStatefulWidget {
  const AnnouncementEditorScreen({super.key, this.announcementId});

  final String? announcementId;

  @override
  ConsumerState<AnnouncementEditorScreen> createState() =>
      _AnnouncementEditorScreenState();
}

class _AnnouncementEditorScreenState
    extends ConsumerState<AnnouncementEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  bool _pinned = false;
  bool _loaded = false;
  bool _saving = false;

  bool get _isEditing => widget.announcementId != null;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    // Carrega o aviso existente se for edição.
    if (_isEditing && !_loaded) {
      _loadExisting();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? l.home_announcement_edit : l.home_announcement_new),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: l.home_announcement_title_label,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _bodyController,
              decoration: InputDecoration(
                labelText: l.home_announcement_body_label,
                border: const OutlineInputBorder(),
              ),
              maxLines: 8,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return l.home_announcement_body_label;
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: Text(l.home_announcement_pinned),
              value: _pinned,
              onChanged: (v) => setState(() => _pinned = v),
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
    final announcements = ref.read(announcementsProvider).value ?? const [];
    final item = announcements.where((a) => a.id == widget.announcementId).firstOrNull;
    if (item != null) {
      _titleController.text = item.title ?? '';
      _bodyController.text = item.body;
      setState(() {
        _pinned = item.pinned;
        _loaded = true;
      });
    } else {
      // Tenta buscar do DAO.
      final dao = ref.read(homeDaoProvider);
      final row = await dao.getAnnouncement(widget.announcementId!);
      if (row != null && mounted) {
        _titleController.text = row.title ?? '';
        _bodyController.text = row.body;
        setState(() {
          _pinned = row.pinned;
          _loaded = true;
        });
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final l = AppLocalizations.of(context);
    final repo = ref.read(homeRepositoryProvider);

    try {
      if (_isEditing) {
        await repo.updateAnnouncement(
          id: widget.announcementId!,
          title: _titleController.text.trim().isEmpty
              ? null
              : _titleController.text.trim(),
          body: _bodyController.text.trim(),
          pinned: _pinned,
        );
      } else {
        final profile = ref.read(currentProfileProvider).value;
        await repo.createAnnouncement(
          title: _titleController.text.trim().isEmpty
              ? null
              : _titleController.text.trim(),
          body: _bodyController.text.trim(),
          pinned: _pinned,
          authorId: profile?.id,
          authorName: profile?.fullName,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.home_announcement_saved)),
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
