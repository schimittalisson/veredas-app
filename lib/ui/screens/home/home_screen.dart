import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/home_providers.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/ui/navigation/app_router.dart';
import 'package:veredas/ui/widgets/app_toast.dart';
import 'package:veredas/ui/widgets/confirm_dialog.dart';
import 'package:veredas/ui/widgets/empty_state.dart';
import 'package:veredas/ui/widgets/loading_state.dart';
import 'package:veredas/ui/widgets/section_header.dart';

/// Tela Início — a primeira tab.
///
/// `ListView` com as seções na ordem do mockup (`TELAS.md` §1):
/// 1. Aviso fixado (cartão em destaque)
/// 2. Redes sociais (Row de botões circulares)
/// 3. Dados da Base (linhas expansíveis)
/// 4. Avisos anteriores (lista + "Ver tudo")
///
/// A ação "Novo aviso" só aparece para admin. No iOS ela mora no `trailing` da
/// barra de navegação: o FAB é um padrão do Material Design e não tem
/// equivalente na plataforma — a Apple põe a ação primária de uma lista no
/// canto superior direito.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final isAdmin = ref.watch(isAdminProvider);

    return CupertinoPageScaffold(
      backgroundColor: colors.groupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(l.tab_inicio),
        backgroundColor: colors.elevatedSurface,
        // Sem `heroTag`: aquilo existia só para desambiguar os 4 FABs que
        // coexistiam na árvore do StatefulShellRoute. Um botão de barra não
        // participa de transição hero, então o problema deixa de existir.
        trailing: isAdmin
            ? Semantics(
                // CupertinoButton não tem `tooltip`; a dica de acessibilidade
                // vira label semântico, que é o que o VoiceOver lê.
                label: l.home_announcement_new,
                button: true,
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: () => context.push(Routes.avisoNovo),
                  child: const Icon(CupertinoIcons.add),
                ),
              )
            : null,
      ),
      child: SafeArea(
        bottom: false,
        child: ListView(
          children: const [
            // 1. Aviso fixado
            _PinnedAnnouncement(),
            // 2. Redes sociais
            _SocialLinks(),
            // 3. Dados da Base
            _BaseInfoSection(),
            // 4. Avisos anteriores
            _RecentAnnouncements(),
            // Espaço para a tab bar não cobrir o último item.
            SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. Aviso fixado
// ---------------------------------------------------------------------------

class _PinnedAnnouncement extends ConsumerWidget {
  const _PinnedAnnouncement();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final announcement = ref.watch(pinnedAnnouncementProvider);

    if (announcement == null) {
      // Sem aviso fixado: não mostra a seção. O espaço fica limpo.
      return const SizedBox.shrink();
    }

    final isAdmin = ref.watch(isAdminProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      // O `Card` do Material trazia elevação (sombra). No iOS o destaque de um
      // cartão vem do contraste entre a superfície e o fundo agrupado, não de
      // sombra — por isso só cor + canto arredondado.
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Substitui o CircleAvatar (Material) por um círculo simples.
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.tintContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      // CupertinoIcons não tem "megafone"; o sino é o símbolo
                      // de aviso/notificação na iconografia da Apple.
                      CupertinoIcons.bell_fill,
                      size: 20,
                      color: colors.onTintContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          announcement.authorName ?? l.home_pinned_section,
                          style: AppTypography.footnoteEmphasis
                              .copyWith(color: colors.label),
                        ),
                        Text(
                          timeago.format(
                            announcement.createdAt,
                            locale: 'pt_BR',
                          ),
                          style: AppTypography.footnote
                              .copyWith(color: colors.secondaryLabel),
                        ),
                      ],
                    ),
                  ),
                  if (isAdmin)
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      onPressed: () => _showActions(context, ref, announcement),
                      child: Icon(
                        CupertinoIcons.ellipsis,
                        size: 20,
                        color: colors.secondaryLabel,
                      ),
                    ),
                ],
              ),
              if (announcement.title != null &&
                  announcement.title!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  announcement.title!,
                  style: AppTypography.headline.copyWith(color: colors.label),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                announcement.body,
                style: AppTypography.body.copyWith(color: colors.label),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Menu de ações do aviso (era um `PopupMenuButton`).
  ///
  /// O menu suspenso ancorado no botão é padrão Material. No iOS a forma
  /// equivalente para 2–3 ações é a *action sheet* que sobe da base, com o
  /// "Cancelar" destacado embaixo. As opções e os callbacks são os mesmos.
  Future<void> _showActions(
    BuildContext context,
    WidgetRef ref,
    AnnouncementRow announcement,
  ) async {
    final l = AppLocalizations.of(context);

    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(sheetContext).pop();
              context.push('${Routes.avisoEditar}?id=${announcement.id}');
            },
            child: Text(l.home_announcement_edit),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.of(sheetContext).pop();
              _confirmDelete(context, ref, announcement.id);
            },
            child: Text(l.home_announcement_delete),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: Text(l.action_cancel),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    final l = AppLocalizations.of(context);
    final confirmed = await ConfirmDialog.show(
      context,
      title: l.home_announcement_delete,
      message: l.home_announcement_delete_confirm,
      confirmLabel: l.home_announcement_delete,
    );

    if (!confirmed) return;

    try {
      await ref.read(homeRepositoryProvider).deleteAnnouncement(id);
    } catch (e) {
      if (context.mounted) {
        showAppToast(context, e.toString(), isError: true);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// 2. Redes sociais
// ---------------------------------------------------------------------------

class _SocialLinks extends ConsumerWidget {
  const _SocialLinks();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final links = ref.watch(socialLinksProvider);

    return links.when(
      loading: () => const SizedBox.shrink(),
      error: (_,_) => const SizedBox.shrink(),
      data: (data) {
        if (data.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              SectionHeader(title: l.home_social_section),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  children: data.map((link) => _SocialButton(link: link)).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({required this.link});

  final SocialLinkRow link;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // O `Tooltip` sai: é um padrão de desktop/Material e no iOS não existe
    // dica ao toque longo. O rótulo vira label semântico para o leitor de tela.
    return Semantics(
      label: link.label ?? link.platform,
      button: true,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: () => _launch(context),
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.tintContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            _iconForPlatform(link.platform),
            color: colors.onTintContainer,
          ),
        ),
      ),
    );
  }

  Future<void> _launch(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final uri = Uri.tryParse(link.url);
    if (uri == null) {
      showAppToast(context, l.home_link_open_error, isError: true);
      return;
    }

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      showAppToast(context, l.home_link_open_error, isError: true);
    }
  }

  /// Ícone Cupertino para a plataforma. O conjunto da Apple não tem logos de
  /// marca (nem Facebook, nem Instagram), então usamos o símbolo genérico mais
  /// próximo da função de cada rede — câmera para Instagram, balão para
  /// WhatsApp. O `flutter_svg` com os logos reais seria mais fiel, mas adiciona
  /// uma dependência só para isto — deixamos para quando o solicitante pedir.
  IconData _iconForPlatform(String platform) {
    final p = platform.toLowerCase();
    if (p.contains('instagram')) return CupertinoIcons.camera;
    if (p.contains('facebook')) return CupertinoIcons.person_2_fill;
    if (p.contains('whatsapp')) return CupertinoIcons.chat_bubble_2;
    if (p.contains('youtube')) return CupertinoIcons.play_circle;
    if (p.contains('twitter') || p.contains('x')) return CupertinoIcons.at;
    if (p.contains('tiktok')) return CupertinoIcons.music_note;
    if (p.contains('spotify')) return CupertinoIcons.waveform;
    if (p.contains('email') || p.contains('gmail')) return CupertinoIcons.mail;
    if (p.contains('phone')) return CupertinoIcons.phone;
    return CupertinoIcons.link;
  }
}

// ---------------------------------------------------------------------------
// 3. Dados da Base
// ---------------------------------------------------------------------------

class _BaseInfoSection extends ConsumerWidget {
  const _BaseInfoSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final baseInfo = ref.watch(baseInfoProvider);
    final isAdmin = ref.watch(isAdminProvider);

    return Column(
      children: [
        SectionHeader(title: l.home_base_info_section),
        baseInfo.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: LoadingState(),
          ),
          error: (_,_) => EmptyState(
            title: l.home_no_base_info,
            icon: CupertinoIcons.info_circle,
            compact: true,
          ),
          data: (data) {
            if (data.isEmpty) {
              return EmptyState(
                title: l.home_no_base_info,
                icon: CupertinoIcons.info_circle,
                compact: true,
              );
            }
            return Column(
              children: data
                  .map((item) => _BaseInfoTile(item: item, isAdmin: isAdmin))
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}

/// Linha expansível dos dados da base.
///
/// O `ExpansionTile` é exclusivo do Material. Aqui a expansão é feita à mão: a
/// linha inteira é tocável e a seta (`chevron_forward` → `chevron_down`) indica
/// o estado, como nas listas de Ajustes do iOS. O corpo entra num
/// `AnimatedCrossFade` para a transição não ser um salto seco.
///
/// Virou `StatefulWidget` só por causa disso — o "aberto/fechado" é estado de
/// apresentação e não pertence a nenhum provider.
class _BaseInfoTile extends ConsumerStatefulWidget {
  const _BaseInfoTile({required this.item, required this.isAdmin});

  final BaseInfoRow item;
  final bool isAdmin;

  @override
  ConsumerState<_BaseInfoTile> createState() => _BaseInfoTileState();
}

class _BaseInfoTileState extends ConsumerState<_BaseInfoTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          CupertinoListTile(
            backgroundColor: const Color(0x00000000),
            title: Text(
              widget.item.label,
              style: AppTypography.body.copyWith(color: colors.label),
            ),
            onTap: () => setState(() => _expanded = !_expanded),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.isAdmin)
                  Semantics(
                    label: l.home_base_info_edit,
                    button: true,
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      onPressed: _showEditDialog,
                      child: Icon(
                        CupertinoIcons.pencil,
                        size: 20,
                        color: colors.tint,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                Icon(
                  _expanded
                      ? CupertinoIcons.chevron_down
                      : CupertinoIcons.chevron_forward,
                  size: 16,
                  color: colors.tertiaryLabel,
                ),
              ],
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Divider é Material; a régua fina do iOS é um traço de 0.5px.
                Container(height: 0.5, color: colors.separator),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    // Seleção de texto para copiar CNPJ/CEP/etc. O
                    // `SelectableText` mora no Material, então usamos o
                    // `SelectableRegion` cru com as alças e o menu do iOS.
                    child: SelectableRegion(
                      selectionControls: cupertinoTextSelectionHandleControls,
                      contextMenuBuilder: (context, state) =>
                          CupertinoAdaptiveTextSelectionToolbar.buttonItems(
                        buttonItems: state.contextMenuButtonItems,
                        anchors: state.contextMenuAnchors,
                      ),
                      child: Text(
                        widget.item.value,
                        style: AppTypography.subheadline
                            .copyWith(color: colors.secondaryLabel),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditDialog() async {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final controller = TextEditingController(text: widget.item.value);

    // O iOS aceita campo de texto dentro de um alerta (é como o sistema pede
    // senha de Wi-Fi), então o formato do diálogo se mantém.
    final result = await showCupertinoDialog<String>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(l.home_base_info_edit_title),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            placeholder: l.home_base_info_value_label,
            maxLines: null,
            autofocus: true,
            style: AppTypography.body.copyWith(color: colors.label),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l.action_cancel),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(l.action_save),
          ),
        ],
      ),
    );

    controller.dispose();

    if (result == null || result == widget.item.value) return;

    try {
      await ref.read(homeRepositoryProvider).updateBaseInfo(
            id: widget.item.id,
            value: result,
          );
    } catch (e) {
      if (mounted) {
        showAppToast(context, e.toString(), isError: true);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// 4. Avisos anteriores
// ---------------------------------------------------------------------------

class _RecentAnnouncements extends ConsumerWidget {
  const _RecentAnnouncements();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final announcements = ref.watch(recentAnnouncementsProvider);

    return Column(
      children: [
        SectionHeader(
          title: l.home_announcements_section,
          actionLabel: l.action_see_all,
          onAction: () {
            // TODO: navegar para lista completa de avisos (rota /avisos)
            // Por ora, não há tela de lista — o editor de cada aviso é
            // acessível pela action sheet no aviso fixado.
          },
        ),
        if (announcements.isEmpty)
          EmptyState(
            title: l.home_no_announcements,
            icon: CupertinoIcons.bell,
            compact: true,
          )
        else
          // Os avisos ficam num único cartão, com as células separadas por um
          // traço fino: é a lista agrupada (`insetGrouped`) do iOS.
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                for (var i = 0; i < announcements.length; i++) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Container(height: 0.5, color: colors.separator),
                    ),
                  _AnnouncementTile(announcement: announcements[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _AnnouncementTile extends StatelessWidget {
  const _AnnouncementTile({required this.announcement});

  final AnnouncementRow announcement;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return CupertinoListTile(
      // O cartão em volta já dá a cor; a célula fica transparente para o canto
      // arredondado do container não ser tapado por um retângulo opaco.
      backgroundColor: const Color(0x00000000),
      title: Text(
        announcement.title?.isNotEmpty == true
            ? announcement.title!
            : announcement.body,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.body.copyWith(color: colors.label),
      ),
      subtitle: Text(
        timeago.format(announcement.createdAt, locale: 'pt_BR'),
        style: AppTypography.footnote.copyWith(color: colors.secondaryLabel),
      ),
      trailing: Icon(
        CupertinoIcons.chevron_forward,
        size: 16,
        color: colors.tertiaryLabel,
      ),
      onTap: () {
        // Detalhe do aviso: por ora, abre o editor em modo visualização.
        // TODO: tela de detalhe dedicada (/aviso/:id) quando houver
        // comentários ou anexos.
      },
    );
  }
}
