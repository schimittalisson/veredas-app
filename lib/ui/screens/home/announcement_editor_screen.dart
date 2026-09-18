import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/home_providers.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/ui/widgets/app_toast.dart';

/// Editor de aviso — cria ou edita.
///
/// Se [announcementId] for null, é criação. Se for fornecido, carrega o aviso
/// existente do cache para preencher os campos.
///
/// **Onde fica o botão de salvar.** No Material o padrão era um `FilledButton`
/// largo no fim do formulário. No iOS a ação de confirmação de um editor mora
/// no canto direito da barra de navegação — é onde o usuário procura, e evita
/// que o botão principal fique escondido abaixo do teclado num formulário
/// longo. Por isso o botão do fim foi **removido** em todos os cinco editores;
/// existe só o `trailing` da `CupertinoNavigationBar`.
class AnnouncementEditorScreen extends ConsumerStatefulWidget {
  const AnnouncementEditorScreen({super.key, this.announcementId});

  final String? announcementId;

  @override
  ConsumerState<AnnouncementEditorScreen> createState() =>
      _AnnouncementEditorScreenState();
}

// ---------------------------------------------------------------------------
// _AnnouncementEditorScreenState
// ---------------------------------------------------------------------------

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
    final colors = context.colors;

    // Carrega o aviso existente se for edição.
    if (_isEditing && !_loaded) {
      _loadExisting();
    }

    return CupertinoPageScaffold(
      backgroundColor: colors.groupedBackground,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: colors.elevatedSurface,
        middle: Text(
          _isEditing ? l.home_announcement_edit : l.home_announcement_new,
        ),
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
              // Uma única seção agrupada: título, corpo e o interruptor de
              // fixar são o mesmo assunto, não merecem cartões separados.
              CupertinoFormSection.insetGrouped(
                backgroundColor: colors.groupedBackground,
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                children: [
                  CupertinoTextFormFieldRow(
                    controller: _titleController,
                    textAlign: TextAlign.end,
                    prefix: Text(
                      l.home_announcement_title_label,
                      style: AppTypography.body.copyWith(color: colors.label),
                    ),
                    style: AppTypography.body.copyWith(color: colors.label),
                  ),
                  CupertinoTextFormFieldRow(
                    controller: _bodyController,
                    placeholder: l.home_announcement_body_label,
                    maxLines: 8,
                    style: AppTypography.body.copyWith(color: colors.label),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return l.home_announcement_body_label;
                      }
                      return null;
                    },
                  ),
                  CupertinoFormRow(
                    prefix: Text(
                      l.home_announcement_pinned,
                      style: AppTypography.body.copyWith(color: colors.label),
                    ),
                    child: CupertinoSwitch(
                      value: _pinned,
                      onChanged: (v) => setState(() => _pinned = v),
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
        showAppToast(context, l.home_announcement_saved);
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
