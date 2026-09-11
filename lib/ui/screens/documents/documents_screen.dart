import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/data/daos/documents_dao.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/documents_providers.dart';
import 'package:veredas/ui/navigation/app_router.dart';
import 'package:veredas/ui/widgets/app_toast.dart';
import 'package:veredas/ui/widgets/confirm_dialog.dart';
import 'package:veredas/ui/widgets/empty_state.dart';
import 'package:veredas/ui/widgets/pull_to_refresh.dart';

/// Tela Arquivos — quinta aba.
///
/// Catálogo de documentos da base. Cada item é um **atalho** para um arquivo
/// hospedado fora do app (Google Drive e afins), aberto no navegador ou no app
/// do serviço. O app não guarda o arquivo — ver a migration
/// `20260828000100_documents.sql` para o porquê e para o caminho de evolução.
///
/// Ordenação é escolha do usuário (nome ou data), num controle no topo.
/// Cadastro e edição são só de admin.
class DocumentsScreen extends ConsumerWidget {
  const DocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final docs = ref.watch(documentsProvider).value ?? const [];
    final isAdmin = ref.watch(isAdminProvider);

    return CupertinoPageScaffold(
      backgroundColor: colors.groupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(l.tab_arquivos),
        backgroundColor: colors.elevatedSurface,
        // O iOS põe a ação primária no canto da barra, não num FAB.
        trailing: isAdmin
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: () => context.push(Routes.arquivoNovo),
                child: Semantics(
                  label: l.docs_new,
                  button: true,
                  child: const Icon(CupertinoIcons.add),
                ),
              )
            : null,
      ),
      child: SafeArea(
        // `bottom` ligado: o RootScaffold soma o espaço da pílula ao
        // MediaQuery, e é isso que impede o último item de ficar escondido.
        child: Column(
          children: [
            const _SortBar(),
            Container(height: 0.5, color: colors.separator),
            Expanded(
              child: docs.isEmpty
                  // O estado vazio também arrasta para atualizar: é quando o
                  // usuário mais quer buscar novidade.
                  ? RefreshableBox(
                      child: EmptyState(
                        title: l.docs_no_documents,
                        icon: CupertinoIcons.folder,
                      ),
                    )
                  : CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        const SyncRefreshControl(),
                        SliverList.builder(
                          itemCount: docs.length,
                          itemBuilder: (context, i) => _DocumentTile(
                            document: docs[i],
                            canEdit: isAdmin,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Seletor de ordenação.
///
/// Um `CupertinoSlidingSegmentedControl` não serve aqui: são quatro opções com
/// rótulos longos ("Adicionados recentemente"). O padrão do iOS para isso é um
/// botão que abre uma action sheet mostrando a opção ativa.
class _SortBar extends ConsumerWidget {
  const _SortBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final sort = ref.watch(documentSortProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          minimumSize: Size.zero,
          onPressed: () => _pickSort(context, ref, sort),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.arrow_up_arrow_down,
                size: 16,
                color: colors.tint,
              ),
              const SizedBox(width: 6),
              Text(
                _sortLabel(l, sort),
                style: AppTypography.subheadline.copyWith(color: colors.tint),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickSort(
    BuildContext context,
    WidgetRef ref,
    DocumentSort current,
  ) async {
    final l = AppLocalizations.of(context);

    final chosen = await showCupertinoModalPopup<DocumentSort>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(l.docs_sort_label),
        actions: [
          for (final option in DocumentSort.values)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop(option),
              // A opção ativa vem marcada: sem isso a sheet não diz qual
              // ordenação está valendo, e o rótulo do botão fica sendo a única
              // pista.
              child: Text(
                _sortLabel(l, option),
                style: option == current
                    ? AppTypography.headline
                    : AppTypography.body,
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: Text(l.action_cancel),
        ),
      ),
    );

    if (chosen != null) {
      ref.read(documentSortProvider.notifier).set(chosen);
    }
  }
}

String _sortLabel(AppLocalizations l, DocumentSort sort) => switch (sort) {
      DocumentSort.recentlyUpdated => l.docs_sort_recently_updated,
      DocumentSort.recentlyAdded => l.docs_sort_recently_added,
      DocumentSort.titleAsc => l.docs_sort_title_asc,
      DocumentSort.titleDesc => l.docs_sort_title_desc,
    };

class _DocumentTile extends ConsumerStatefulWidget {
  const _DocumentTile({required this.document, required this.canEdit});

  final DocumentRow document;
  final bool canEdit;

  @override
  ConsumerState<_DocumentTile> createState() => _DocumentTileState();
}

class _DocumentTileState extends ConsumerState<_DocumentTile> {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final doc = widget.document;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _open,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.tintContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _iconFor(doc),
                  color: colors.onTintContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.title,
                      style: AppTypography.headline
                          .copyWith(color: colors.label),
                    ),
                    if (doc.description != null &&
                        doc.description!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        doc.description!,
                        style: AppTypography.footnote
                            .copyWith(color: colors.secondaryLabel),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.canEdit)
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: _showActions,
                  child: Icon(
                    CupertinoIcons.ellipsis,
                    size: 20,
                    color: colors.secondaryLabel,
                  ),
                )
              else
                // Sinaliza que o item leva para fora do app.
                Icon(
                  CupertinoIcons.arrow_up_right_square,
                  size: 18,
                  color: colors.tertiaryLabel,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open() async {
    final l = AppLocalizations.of(context);
    final doc = widget.document;

    // Nesta versão todo documento é um atalho. Quando `source_type == 'file'`
    // existir, é aqui que entra a URL assinada do Storage.
    final raw = doc.url;
    if (raw == null || raw.trim().isEmpty) {
      showAppToast(context, l.home_link_open_error, isError: true);
      return;
    }

    final uri = Uri.tryParse(raw);
    if (uri == null) {
      showAppToast(context, l.home_link_open_error, isError: true);
      return;
    }

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      showAppToast(context, l.home_link_open_error, isError: true);
    }
  }

  Future<void> _showActions() async {
    final l = AppLocalizations.of(context);

    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop('edit'),
            child: Text(l.action_edit),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(sheetContext).pop('delete'),
            child: Text(l.action_delete),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: Text(l.action_cancel),
        ),
      ),
    );

    if (!mounted || action == null) return;

    switch (action) {
      case 'edit':
        await context.push('${Routes.arquivoEditar}?id=${widget.document.id}');

      case 'delete':
        final confirmed = await ConfirmDialog.show(
          context,
          title: l.docs_delete_confirm,
          // Deixa explícito que o arquivo no Drive continua lá — quem apaga um
          // atalho não espera perder o original, e o contrário assustaria.
          message: l.docs_delete_message,
        );
        if (!confirmed || !mounted) return;
        await ref
            .read(documentActionsProvider.notifier)
            .delete(widget.document.id);
    }
  }

  /// Ícone pela extensão no fim da URL.
  ///
  /// É um palpite: link do Drive normalmente não termina em `.pdf`, e nesse
  /// caso cai no ícone genérico de documento. Serve para dar uma pista visual
  /// quando o link é direto para o arquivo, sem prometer detecção real de tipo.
  IconData _iconFor(DocumentRow doc) {
    final target = (doc.url ?? doc.storagePath ?? '').toLowerCase();
    if (target.contains('.pdf')) return CupertinoIcons.doc_richtext;
    if (target.contains('.doc')) return CupertinoIcons.doc_text;
    if (target.contains('.xls') || target.contains('spreadsheet')) {
      return CupertinoIcons.table;
    }
    if (target.contains('.ppt') || target.contains('presentation')) {
      return CupertinoIcons.chart_bar_square;
    }
    if (target.contains('.zip')) return CupertinoIcons.archivebox;
    if (target.contains('youtube') || target.contains('.mp4')) {
      return CupertinoIcons.play_rectangle;
    }
    if (target.contains('drive.google') || target.contains('folder')) {
      return CupertinoIcons.folder;
    }
    return CupertinoIcons.doc;
  }
}
