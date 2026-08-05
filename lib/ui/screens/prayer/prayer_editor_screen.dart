import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/infra_providers.dart';

/// Editor de pedido de oração — cria ou edita.
class PrayerEditorScreen extends ConsumerStatefulWidget {
  const PrayerEditorScreen({super.key, this.postId});

  final String? postId;

  @override
  ConsumerState<PrayerEditorScreen> createState() =>
      _PrayerEditorScreenState();
}

class _PrayerEditorScreenState extends ConsumerState<PrayerEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  bool _isAnonymous = false;
  bool _loaded = false;
  bool _saving = false;

  bool get _isEditing => widget.postId != null;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
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
        title: Text(_isEditing ? l.prayer_edit : l.prayer_new),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: l.prayer_title_label,
                border: const OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return l.prayer_title_label;
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _bodyController,
              decoration: InputDecoration(
                labelText: l.prayer_body_label,
                border: const OutlineInputBorder(),
              ),
              maxLines: 8,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return l.prayer_body_label;
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: Text(l.prayer_anonymous),
              subtitle: Text(
                _isAnonymous
                    ? 'Seu nome não será exibido'
                    : 'Seu nome será exibido',
              ),
              value: _isAnonymous,
              onChanged: (v) => setState(() => _isAnonymous = v),
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
    final dao = ref.read(prayerDaoProvider);
    final row = await dao.getPost(widget.postId!);
    if (row != null && mounted) {
      _titleController.text = row.title;
      _bodyController.text = row.body;
      setState(() {
        _isAnonymous = row.isAnonymous;
        _loaded = true;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final l = AppLocalizations.of(context);
    final repo = ref.read(prayerRepositoryProvider);

    try {
      if (_isEditing) {
        await repo.updatePost(
          id: widget.postId!,
          title: _titleController.text.trim(),
          body: _bodyController.text.trim(),
          isAnonymous: _isAnonymous,
        );
      } else {
        final profile = ref.read(currentProfileProvider).value;
        if (profile == null) return;

        await repo.createPost(
          title: _titleController.text.trim(),
          body: _bodyController.text.trim(),
          isAnonymous: _isAnonymous,
          authorId: profile.id,
          authorName: profile.fullName,
          authorAvatarUrl: profile.avatarUrl,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.prayer_saved)),
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
