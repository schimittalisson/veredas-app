import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/home_providers.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/ui/widgets/empty_state.dart';
import 'package:veredas/ui/widgets/loading_state.dart';
import 'package:veredas/ui/widgets/section_header.dart';

/// Tela Início — a primeira tab.
///
/// `ListView` com as seções na ordem do mockup (`TELAS.md` §1):
/// 1. Aviso fixado (cartão em destaque)
/// 2. Redes sociais (Row de IconButtons circulares)
/// 3. Dados da Base (ExpansionTile)
/// 4. Avisos anteriores (lista + "Ver tudo")
///
/// FAB "Novo aviso" só aparece para admin.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final isAdmin = ref.watch(isAdminProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.tab_inicio)),
      floatingActionButton: isAdmin
          ? FloatingActionButton(
              onPressed: () {
                // TODO: navegar para /aviso/novo (Fase 9 ou editor de aviso)
              },
              tooltip: l.home_announcement_new,
              child: const Icon(Icons.add),
            )
          : null,
      body: ListView(
        children: [
          // 1. Aviso fixado
          const _PinnedAnnouncement(),
          // 2. Redes sociais
          const _SocialLinks(),
          // 3. Dados da Base
          const _BaseInfoSection(),
          // 4. Avisos anteriores
          const _RecentAnnouncements(),
          const SizedBox(height: 80), // espaço para o FAB
        ],
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
    final announcement = ref.watch(pinnedAnnouncementProvider);

    if (announcement == null) {
      // Sem aviso fixado: não mostra a seção. O espaço fica limpo.
      return const SizedBox.shrink();
    }

    final isAdmin = ref.watch(isAdminProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(
                      Icons.campaign,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // TODO: nome do autor (precisa de join com profiles
                        // no cache, ou denormalizar author_name no sync).
                        // Por ora, mostra "Aviso" como placeholder.
                        Text(
                          l.home_pinned_section,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        Text(
                          timeago.format(
                            announcement.createdAt,
                            locale: 'pt_BR',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (isAdmin)
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') {
                          // TODO: navegar para editor de aviso
                        } else if (value == 'delete') {
                          _confirmDelete(context, ref, announcement.id);
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text(l.home_announcement_edit),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(l.home_announcement_delete),
                        ),
                      ],
                    ),
                ],
              ),
              if (announcement.title != null &&
                  announcement.title!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  announcement.title!,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
              const SizedBox(height: 8),
              Text(announcement.body),
            ],
          ),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.home_announcement_delete),
        content: Text(l.home_announcement_delete_confirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.action_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.home_announcement_delete),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(homeRepositoryProvider).deleteAnnouncement(id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
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
    return InkWell(
      onTap: () => _launch(context),
      borderRadius: BorderRadius.circular(28),
      child: Tooltip(
        message: link.label ?? link.platform,
        child: CircleAvatar(
          radius: 24,
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          child: Icon(
            _iconForPlatform(link.platform),
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
        ),
      ),
    );
  }

  Future<void> _launch(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final uri = Uri.tryParse(link.url);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.home_link_open_error)),
      );
      return;
    }

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.home_link_open_error)),
      );
    }
  }

  /// Ícone Material para a plataforma. Para marcas sem ícone nativo, usa
  /// `Icons.link`. O `flutter_svg` com logos de marca seria mais fiel, mas
  /// adiciona uma dependência só para isto — deixamos para quando o
  /// solicitante pedir.
  IconData _iconForPlatform(String platform) {
    final p = platform.toLowerCase();
    if (p.contains('instagram')) return Icons.camera_alt_outlined;
    if (p.contains('facebook')) return Icons.facebook_outlined;
    if (p.contains('whatsapp')) return Icons.chat_outlined;
    if (p.contains('youtube')) return Icons.play_circle_outline;
    if (p.contains('twitter') || p.contains('x')) return Icons.alternate_email;
    if (p.contains('tiktok')) return Icons.music_note_outlined;
    if (p.contains('spotify')) return Icons.graphic_eq_outlined;
    if (p.contains('email') || p.contains('gmail')) return Icons.email_outlined;
    if (p.contains('phone')) return Icons.phone_outlined;
    return Icons.link;
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
            icon: Icons.info_outline,
            compact: true,
          ),
          data: (data) {
            if (data.isEmpty) {
              return EmptyState(
                title: l.home_no_base_info,
                icon: Icons.info_outline,
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

class _BaseInfoTile extends ConsumerWidget {
  const _BaseInfoTile({required this.item, required this.isAdmin});

  final BaseInfoRow item;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);

    return ExpansionTile(
      title: Text(item.label),
      trailing: isAdmin
          ? IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: l.home_base_info_edit,
              onPressed: () => _showEditDialog(context, ref),
            )
          : null,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Align(
            alignment: Alignment.centerLeft,
            // SelectableText permite copiar CNPJ/CEP/etc.
            child: SelectableText(item.value),
          ),
        ),
      ],
    );
  }

  Future<void> _showEditDialog(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController(text: item.value);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.home_base_info_edit_title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: l.home_base_info_value_label,
            border: const OutlineInputBorder(),
          ),
          maxLines: null,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.action_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(l.action_save),
          ),
        ],
      ),
    );

    controller.dispose();

    if (result == null || result == item.value) return;

    try {
      await ref.read(homeRepositoryProvider).updateBaseInfo(
            id: item.id,
            value: result,
          );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
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
    final announcements = ref.watch(recentAnnouncementsProvider);

    return Column(
      children: [
        SectionHeader(
          title: l.home_announcements_section,
          actionLabel: l.action_see_all,
          onAction: () {
            // TODO: navegar para lista completa de avisos
          },
        ),
        if (announcements.isEmpty)
          EmptyState(
            title: l.home_no_announcements,
            icon: Icons.campaign_outlined,
            compact: true,
          )
        else
          ...announcements.map((a) => _AnnouncementTile(announcement: a)),
      ],
    );
  }
}

class _AnnouncementTile extends StatelessWidget {
  const _AnnouncementTile({required this.announcement});

  final AnnouncementRow announcement;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(
        announcement.title?.isNotEmpty == true
            ? announcement.title!
            : announcement.body,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        timeago.format(announcement.createdAt, locale: 'pt_BR'),
      ),
      onTap: () {
        // TODO: navegar para detalhe do aviso
      },
    );
  }
}
