import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/ui/widgets/app_toast.dart';

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
    final colors = context.colors;

    if (_isEditing && !_loaded) {
      _loadExisting();
    }

    // Salvar mora no `trailing` da barra — ver a nota em
    // `announcement_editor_screen.dart` sobre por que o botão do fim saiu.
    return CupertinoPageScaffold(
      backgroundColor: colors.groupedBackground,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: colors.elevatedSurface,
        middle: Text(_isEditing ? l.prayer_edit : l.prayer_new),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _saving ? null : _save,
          child: _saving
              ? const CupertinoActivityIndicator()
              : Text(l.action_save),
        ),
      ),
      child: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              CupertinoFormSection.insetGrouped(
                backgroundColor: colors.groupedBackground,
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                children: [
                  CupertinoTextFormFieldRow(
                    controller: _titleController,
                    placeholder: l.prayer_title_label,
                    style: AppTypography.body.copyWith(color: colors.label),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return l.prayer_title_label;
                      }
                      return null;
                    },
                  ),
                  CupertinoTextFormFieldRow(
                    controller: _bodyController,
                    placeholder: l.prayer_body_label,
                    maxLines: 8,
                    style: AppTypography.body.copyWith(color: colors.label),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return l.prayer_body_label;
                      }
                      return null;
                    },
                  ),
                  // O subtítulo do antigo `SwitchListTile` vira o `helper` da
                  // linha: é o slot que o iOS reserva para texto explicativo
                  // abaixo do controle, sem virar uma segunda célula.
                  CupertinoFormRow(
                    prefix: Text(
                      l.prayer_anonymous,
                      style: AppTypography.body.copyWith(color: colors.label),
                    ),
                    helper: Text(
                      // TODO l10n: prayer_anonymous_on / prayer_anonymous_off
                      _isAnonymous
                          ? 'Seu nome não será exibido'
                          : 'Seu nome será exibido',
                      style: AppTypography.footnote
                          .copyWith(color: colors.secondaryLabel),
                    ),
                    child: CupertinoSwitch(
                      value: _isAnonymous,
                      onChanged: (v) => setState(() => _isAnonymous = v),
                    ),
                  ),
                ],
              ),
            ],
          ),
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
        showAppToast(context, l.prayer_saved);
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, e.toString(), isError: true);
        setState(() => _saving = false);
      }
    }
  }
}
