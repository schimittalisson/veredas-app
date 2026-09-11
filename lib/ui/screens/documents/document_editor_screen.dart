import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/core/error/app_exception.dart';
import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/documents_providers.dart';
import 'package:veredas/ui/widgets/app_toast.dart';

/// Editor de atalho de arquivo — cria ou edita.
///
/// Só admin chega aqui (a tela de lista esconde a ação, e a policy
/// `documents_admin_write` recusa no servidor de qualquer forma).
///
/// O botão de salvar mora no `trailing` da navigation bar, como nos outros
/// cinco editores do app — no iOS é onde o usuário procura, e não fica escondido
/// atrás do teclado.
class DocumentEditorScreen extends ConsumerStatefulWidget {
  const DocumentEditorScreen({super.key, this.documentId});

  final String? documentId;

  @override
  ConsumerState<DocumentEditorScreen> createState() =>
      _DocumentEditorScreenState();
}

class _DocumentEditorScreenState extends ConsumerState<DocumentEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _urlController = TextEditingController();
  bool _loaded = false;
  bool _saving = false;

  bool get _isEditing => widget.documentId != null;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;

    if (_isEditing && !_loaded) _loadExisting();

    return CupertinoPageScaffold(
      backgroundColor: colors.groupedBackground,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: colors.elevatedSurface,
        middle: Text(_isEditing ? l.docs_edit_title : l.docs_new_title),
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
                    placeholder: l.docs_title_hint,
                    prefix: Text(
                      l.docs_title_label,
                      style: AppTypography.body.copyWith(color: colors.label),
                    ),
                    textAlign: TextAlign.end,
                    style: AppTypography.body.copyWith(color: colors.label),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                            ? l.docs_title_required
                            : null,
                  ),
                  CupertinoTextFormFieldRow(
                    controller: _descriptionController,
                    placeholder: l.docs_description_hint,
                    prefix: Text(
                      l.docs_description_label,
                      style: AppTypography.body.copyWith(color: colors.label),
                    ),
                    textAlign: TextAlign.end,
                    style: AppTypography.body.copyWith(color: colors.label),
                  ),
                  CupertinoTextFormFieldRow(
                    controller: _urlController,
                    placeholder: l.docs_url_hint,
                    prefix: Text(
                      l.docs_url_label,
                      style: AppTypography.body.copyWith(color: colors.label),
                    ),
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    style: AppTypography.body.copyWith(color: colors.label),
                    validator: _validateUrl,
                  ),
                ],
              ),
              // A permissão do Drive é o erro mais provável de quem cadastra um
              // atalho: o link abre para quem criou e não abre para o resto.
              // Por isso o aviso fica na tela, não na documentação.
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 4, 32, 16),
                child: Text(
                  l.docs_url_help,
                  style: AppTypography.footnote
                      .copyWith(color: colors.secondaryLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _validateUrl(String? value) {
    final l = AppLocalizations.of(context);
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return l.docs_url_required;

    // Validação deliberadamente rasa: exige só um esquema http(s) e um host.
    // Tentar validar "é um link de Drive válido" daria falso negativo em
    // Dropbox, OneDrive e num PDF hospedado em qualquer servidor — e quem
    // cadastra é admin, não um usuário anônimo.
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return l.docs_url_invalid;
    }
    return null;
  }

  void _loadExisting() {
    final doc = ref.read(documentByIdProvider(widget.documentId!));
    if (doc == null) return;

    _titleController.text = doc.title;
    _descriptionController.text = doc.description ?? '';
    _urlController.text = doc.url ?? '';
    setState(() => _loaded = true);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final l = AppLocalizations.of(context);
    final actions = ref.read(documentActionsProvider.notifier);

    final title = _titleController.text.trim();
    final url = _urlController.text.trim();
    final description = _descriptionController.text.trim().isEmpty
        ? null
        : _descriptionController.text.trim();

    try {
      if (_isEditing) {
        await actions.updateLink(
          id: widget.documentId!,
          title: title,
          url: url,
          description: description,
        );
      } else {
        await actions.createLink(
          title: title,
          url: url,
          description: description,
        );
      }

      if (!mounted) return;
      showAppToast(context, l.docs_saved);
      context.pop();
    } on AppException catch (e) {
      // A exceção nunca chega crua à tela (AGENTS.md §6 regra 6): o código
      // enumerado escolhe a mensagem do l10n.
      if (!mounted) return;
      showAppToast(context, _errorMessage(e.code), isError: true);
      setState(() => _saving = false);
    }
  }

  String _errorMessage(AppErrorCode code) {
    final l = AppLocalizations.of(context);
    return switch (code) {
      AppErrorCode.permissionDenied ||
      AppErrorCode.permissionDeniedOrStale ||
      AppErrorCode.forbidden =>
        l.docs_error_permission,
      AppErrorCode.noConnection => l.error_no_connection,
      _ => l.error_generic,
    };
  }
}
