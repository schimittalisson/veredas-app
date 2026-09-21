import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/scales_providers.dart';
import 'package:veredas/ui/navigation/app_router.dart';
import 'package:veredas/ui/widgets/empty_state.dart';
import 'package:veredas/ui/widgets/pull_to_refresh.dart';

/// Conteúdo de uma aba de escala.
///
/// Conforme o `cadence` do tipo:
/// - `weekly`: navegador de semana (segunda a domingo, ISO).
/// - `monthly`: navegador de mês.
/// - `adhoc`: sem navegador; lista próximas + "Anteriores".
///
/// Conforme o tipo ter `slots` ou não:
/// - Com slots: tabela compacta (linhas = slots, células = a equipe escalada).
/// - Sem slots: lista por dia da semana.
///
/// Uma atribuição pode ter várias pessoas (a equipe) e, opcionalmente, um
/// responsável geral sobre elas.
class ScaleTabView extends ConsumerStatefulWidget {
  const ScaleTabView({
    required this.scaleType,
    required this.canEdit,
    super.key,
  });

  final ScaleTypeRow scaleType;
  final bool canEdit;

  @override
  ConsumerState<ScaleTabView> createState() => _ScaleTabViewState();
}

class _ScaleTabViewState extends ConsumerState<ScaleTabView> {
  late DateTime _periodStart;

  @override
  void initState() {
    super.initState();
    _periodStart = _startOfCurrentPeriod();
  }

  DateTime _startOfCurrentPeriod() {
    final now = DateTime.now();
    switch (widget.scaleType.cadence) {
      case 'weekly':
        // Segunda-feira da semana atual (ISO: DateTime.weekday = 1 = segunda).
        return DateTime(now.year, now.month, now.day - (now.weekday - 1));
      case 'monthly':
        return DateTime(now.year, now.month, 1);
      default:
        return now; // adhoc não usa período
    }
  }

  void _previousPeriod() {
    setState(() {
      switch (widget.scaleType.cadence) {
        case 'weekly':
          _periodStart = _periodStart.subtract(const Duration(days: 7));
        case 'monthly':
          _periodStart = DateTime(_periodStart.year, _periodStart.month - 1, 1);
      }
    });
  }

  void _nextPeriod() {
    setState(() {
      switch (widget.scaleType.cadence) {
        case 'weekly':
          _periodStart = _periodStart.add(const Duration(days: 7));
        case 'monthly':
          _periodStart = DateTime(_periodStart.year, _periodStart.month + 1, 1);
      }
    });
  }

  void _goToToday() {
    setState(() => _periodStart = _startOfCurrentPeriod());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cadence = widget.scaleType.cadence;

    if (cadence == 'adhoc') {
      return _AdhocView(
        scaleType: widget.scaleType,
        canEdit: widget.canEdit,
      );
    }

    return Column(
      children: [
        _PeriodNavigator(
          cadence: cadence,
          periodStart: _periodStart,
          onPrevious: _previousPeriod,
          onNext: _nextPeriod,
          onToday: _goToToday,
        ),
        // Meio pixel é a espessura do separador do iOS — o Divider do Material
        // não existe aqui.
        Container(height: 0.5, color: colors.separator),
        Expanded(
          child: _PeriodBody(
            scaleType: widget.scaleType,
            periodStart: _periodStart,
            canEdit: widget.canEdit,
          ),
        ),
      ],
    );
  }
}

/// Abre o editor de uma atribuição já montada.
///
/// O `scaleTypeId` sai da própria linha, e não da aba aberta: na visão adhoc
/// e na seção "Anteriores" a lista não é recortada por período, e amarrar a
/// rota à aba mandaria o editor para a escala errada se algum dia essas listas
/// passarem a misturar tipos.
void _editAssignment(BuildContext context, ScaleAssignmentRow a) {
  context.push(
    '${Routes.escalaAtribuicaoEditar}?scaleTypeId=${a.scaleTypeId}&id=${a.id}',
  );
}

// ---------------------------------------------------------------------------
// Navegador de período
// ---------------------------------------------------------------------------

class _PeriodNavigator extends StatelessWidget {
  const _PeriodNavigator({
    required this.cadence,
    required this.periodStart,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });

  final String cadence;
  final DateTime periodStart;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;

    String label;
    if (cadence == 'weekly') {
      final end = periodStart.add(const Duration(days: 6));
      final fmt = DateFormat('d MMM', 'pt_BR');
      label = l.scales_week_of(fmt.format(periodStart), fmt.format(end));
    } else {
      label = DateFormat('MMMM y', 'pt_BR').format(periodStart);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          CupertinoButton(
            padding: const EdgeInsets.all(8),
            minimumSize: Size.zero,
            onPressed: onPrevious,
            child: Icon(CupertinoIcons.chevron_left, color: colors.tint),
          ),
          Expanded(
            child: Center(
              child: Text(
                label,
                style: AppTypography.subheadlineEmphasis
                    .copyWith(color: colors.label),
              ),
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.all(8),
            minimumSize: Size.zero,
            onPressed: onNext,
            child: Icon(CupertinoIcons.chevron_right, color: colors.tint),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
            onPressed: onToday,
            child: Text(
              l.scales_today,
              style: AppTypography.subheadline.copyWith(color: colors.tint),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Corpo do período (semana ou mês)
// ---------------------------------------------------------------------------

class _PeriodBody extends ConsumerWidget {
  const _PeriodBody({
    required this.scaleType,
    required this.periodStart,
    required this.canEdit,
  });

  final ScaleTypeRow scaleType;
  final DateTime periodStart;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final cadence = scaleType.cadence;

    // Calcula o intervalo de datas.
    final from = periodStart;
    final to = cadence == 'weekly'
        ? periodStart.add(const Duration(days: 7))
        : DateTime(periodStart.year, periodStart.month + 1, 0);

    final query = (scaleTypeId: scaleType.id, from: from, to: to);
    final assignments = ref.watch(assignmentsProvider(query));
    final myCount = ref.watch(myAssignmentCountProvider(query)).value ?? 0;
    final currentUserId = ref.watch(currentUserIdProvider);
    // A equipe é guardada como ids; o nome vem do cache de perfis.
    final profileNames = ref.watch(profileNamesProvider);

    return assignments.when(
      loading: () => const RefreshableBox(
        child: Center(child: CupertinoActivityIndicator()),
      ),
      error: (_,_) => RefreshableBox(
        child: EmptyState(
          title: l.scales_no_assignments,
          icon: CupertinoIcons.doc_text,
        ),
      ),
      data: (data) {
        if (data.isEmpty) {
          return RefreshableBox(
            child: EmptyState(
              title: l.scales_no_assignments,
              icon: CupertinoIcons.doc_text,
              action: canEdit
                  ? CupertinoButton.filled(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      onPressed: () => context.push(
                        '${Routes.escalaAtribuicaoNovo}?scaleTypeId=${scaleType.id}',
                      ),
                      // CupertinoButton não tem slot de ícone: o par
                      // ícone+texto do FilledButton.icon vira uma Row.
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(CupertinoIcons.add, size: 18),
                          const SizedBox(width: 6),
                          Text(l.scales_mount),
                        ],
                      ),
                    )
                  : null,
            ),
          );
        }

        return Column(
          children: [
            // Resumo "Você está escalado N×".
            if (currentUserId != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  l.scales_you_count(myCount),
                  style: AppTypography.subheadline
                      .copyWith(color: colors.secondaryLabel),
                  textAlign: TextAlign.center,
                ),
              ),
            // Corpo: tabela com slots ou lista sem slots.
            Expanded(
              child: scaleType.slots.isNotEmpty
                  ? _SlotsTable(
                      scaleType: scaleType,
                      assignments: data,
                      periodStart: periodStart,
                      currentUserId: currentUserId,
                      profileNames: profileNames,
                      canEdit: canEdit,
                    )
                  : _SimpleList(
                      assignments: data,
                      periodStart: periodStart,
                      cadence: cadence,
                      currentUserId: currentUserId,
                      profileNames: profileNames,
                      canEdit: canEdit,
                    ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Tabela com slots (linhas = slots, células = responsável por dia)
// ---------------------------------------------------------------------------

class _SlotsTable extends StatelessWidget {
  const _SlotsTable({
    required this.scaleType,
    required this.assignments,
    required this.periodStart,
    required this.currentUserId,
    required this.profileNames,
    required this.canEdit,
  });

  final ScaleTypeRow scaleType;
  final List<ScaleAssignmentRow> assignments;
  final DateTime periodStart;
  final String? currentUserId;
  final Map<String, String> profileNames;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final days = scaleType.cadence == 'weekly' ? 7 : 1;
    final dayLabels = _dayLabels(periodStart, days);

    final headerStyle =
        AppTypography.footnoteEmphasis.copyWith(color: colors.label);

    // Agrupa atribuições por (slot, dia).
    final bySlotAndDay = <String, Map<int, ScaleAssignmentRow>>{};
    for (final a in assignments) {
      final slot = a.slot ?? l.scales_slot_label;
      final dayIndex = a.startsOn.difference(periodStart).inDays;
      if (dayIndex < 0 || dayIndex >= days) continue;
      (bySlotAndDay[slot] ??= {})[dayIndex] = a;
    }

    final slots = scaleType.slots;

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        const SyncRefreshControl(),
        SliverToBoxAdapter(
          child: Container(
        // O Card do Material vira um retângulo arredondado sobre o fundo
        // agrupado — é a forma de "cartão" do iOS.
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            children: [
              // Cabeçalho.
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(l.scales_slot_label, style: headerStyle),
                  ),
                  for (final label in dayLabels)
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(label, style: headerStyle),
                    ),
                ],
              ),
              // Linhas por slot.
              for (final slot in slots)
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(
                        slot,
                        style: AppTypography.footnote
                            .copyWith(color: colors.label),
                      ),
                    ),
                    for (int day = 0; day < days; day++)
                      _AssignmentCell(
                        assignment: bySlotAndDay[slot]?[day],
                        currentUserId: currentUserId,
                        profileNames: profileNames,
                        canEdit: canEdit,
                      ),
                  ],
                ),
            ],
          ),
        ),
          ),
        ),
      ],
    );
  }

  List<String> _dayLabels(DateTime start, int count) {
    final fmt = DateFormat.E('pt_BR');
    return [
      for (int i = 0; i < count; i++) fmt.format(start.add(Duration(days: i))),
    ];
  }
}

// ---------------------------------------------------------------------------
// _AssignmentCell
// ---------------------------------------------------------------------------

class _AssignmentCell extends StatelessWidget {
  const _AssignmentCell({
    required this.assignment,
    required this.currentUserId,
    required this.profileNames,
    required this.canEdit,
  });

  final ScaleAssignmentRow? assignment;
  final String? currentUserId;
  final Map<String, String> profileNames;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;

    if (assignment == null) {
      return Padding(
        padding: const EdgeInsets.all(4),
        child: Text(
          '—',
          style:
              AppTypography.footnote.copyWith(color: colors.secondaryLabel),
        ),
      );
    }

    final isMe =
        currentUserId != null && isAssignedTo(assignment!, currentUserId!);
    final people = _peopleOf(assignment!, profileNames, l);
    final labelColor = isMe ? colors.onTintContainer : colors.label;

    final cell = Container(
      padding: const EdgeInsets.all(4),
      decoration: isMe
          ? BoxDecoration(
              color: colors.tintContainer,
              borderRadius: BorderRadius.circular(4),
            )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Uma linha por pessoa: a equipe cabe na célula estreita da grade,
          // que uma lista separada por vírgula truncaria já na segunda.
          for (final name in people.team)
            Text(
              name,
              style: AppTypography.footnote.copyWith(color: labelColor),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          if (people.lead != null)
            Text(
              '${l.scales_lead_badge}: ${people.lead}',
              style: AppTypography.caption.copyWith(
                color: isMe ? colors.onTintContainer : colors.secondaryLabel,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          if (isMe)
            Text(
              l.scales_you,
              style: AppTypography.caption
                  .copyWith(color: colors.onTintContainer),
            ),
        ],
      ),
    );

    if (!canEdit) return cell;

    // A célula não ganha chevron: na grade de sete dias ela tem poucos
    // milímetros de largura, e um ícone ali empurraria os nomes para fora.
    // Quem pode editar descobre pelo toque; para quem não pode, não há o que
    // descobrir. `opaque` faz o toque valer na célula inteira, inclusive no
    // vão entre as linhas de nome.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _editAssignment(context, assignment!),
      child: Semantics(
        button: true,
        label: '${l.action_edit}: ${people.team.join(', ')}',
        child: cell,
      ),
    );
  }
}

/// Como uma atribuição é lida na tela: a equipe e, se houver, o responsável
/// geral sobre ela.
typedef _People = ({List<String> team, String? lead});

/// Resolve os nomes de uma atribuição.
///
/// Dois detalhes que não são óbvios:
///
/// 1. Quando não há equipe, o responsável geral **vira** a equipe. É o caso
///    das atribuições criadas antes das escalas em grupo, em que
///    `assignee_id`/`assignee_name` eram a pessoa escalada — mostrá-las como
///    "responsável: Fulano" sobre uma célula vazia seria só confuso.
/// 2. Um id que não está no cache de perfis (pessoa removida, ou perfil ainda
///    não sincronizado) cai em "A definir", nunca no UUID cru.
_People _peopleOf(
  ScaleAssignmentRow a,
  Map<String, String> profileNames,
  AppLocalizations l,
) {
  final team = <String>[
    for (final id in a.memberIds) profileNames[id] ?? l.scales_assignee_unknown,
    ...a.memberNames,
  ];

  final leadId = a.assigneeId;
  final lead = leadId != null
      ? (profileNames[leadId] ?? l.scales_assignee_unknown)
      : (a.assigneeName?.trim().isNotEmpty ?? false
          ? a.assigneeName!.trim()
          : null);

  if (team.isEmpty) {
    return (team: [lead ?? l.scales_assignee_unknown], lead: null);
  }
  return (team: team, lead: lead);
}

// ---------------------------------------------------------------------------
// Lista simples (sem slots) — por dia da semana
// ---------------------------------------------------------------------------

class _SimpleList extends StatelessWidget {
  const _SimpleList({
    required this.assignments,
    required this.periodStart,
    required this.cadence,
    required this.currentUserId,
    required this.profileNames,
    required this.canEdit,
  });

  final List<ScaleAssignmentRow> assignments;
  final DateTime periodStart;
  final String cadence;
  final String? currentUserId;
  final Map<String, String> profileNames;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final days = cadence == 'weekly' ? 7 : 1;

    // Agrupa por dia.
    final byDay = <int, List<ScaleAssignmentRow>>{};
    for (final a in assignments) {
      final dayIndex = a.startsOn.difference(periodStart).inDays;
      if (dayIndex < 0 || dayIndex >= days) continue;
      (byDay[dayIndex] ??= []).add(a);
    }

    final fmt = DateFormat.EEEE('pt_BR');

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        const SyncRefreshControl(),
        SliverList.list(
          children: [
            for (int day = 0; day < days; day++)
              if (byDay[day] != null) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    fmt.format(periodStart.add(Duration(days: day))),
                    style: AppTypography.subheadlineEmphasis
                        .copyWith(color: colors.label),
                  ),
                ),
                for (final a in byDay[day]!)
                  _AssignmentListTile(
                    assignment: a,
                    isMe: currentUserId != null &&
                        isAssignedTo(a, currentUserId!),
                    profileNames: profileNames,
                    canEdit: canEdit,
                  ),
              ],
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _AssignmentListTile
// ---------------------------------------------------------------------------

class _AssignmentListTile extends StatelessWidget {
  const _AssignmentListTile({
    required this.assignment,
    required this.isMe,
    required this.profileNames,
    required this.canEdit,
  });

  final ScaleAssignmentRow assignment;
  final bool isMe;
  final Map<String, String> profileNames;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final people = _peopleOf(assignment, profileNames, l);

    // Tarefa e responsável geral dividem o subtítulo — as duas são contexto
    // sobre a mesma escala, e duas linhas empurrariam a célula para fora do
    // ritmo da lista.
    final subtitle = [
      if (assignment.task != null) assignment.task!,
      if (people.lead != null) '${l.scales_lead_badge}: ${people.lead}',
    ].join(' · ');

    return CupertinoListTile(
      backgroundColor: isMe ? colors.tintContainer : colors.surface,
      leading: Icon(
        // Um ícone de grupo quando a escala é de mais de uma pessoa: dá para
        // ver que é equipe antes de ler os nomes.
        people.team.length > 1
            ? CupertinoIcons.person_2
            : CupertinoIcons.person,
        color: isMe ? colors.onTintContainer : colors.secondaryLabel,
      ),
      title: Text(
        people.team.join(', '),
        style: AppTypography.body.copyWith(
          color: isMe ? colors.onTintContainer : colors.label,
        ),
      ),
      subtitle: subtitle.isNotEmpty
          ? Text(
              subtitle,
              style: AppTypography.footnote.copyWith(
                color: isMe ? colors.onTintContainer : colors.secondaryLabel,
              ),
            )
          : null,
      // O Chip do Material vira uma cápsula desenhada à mão: o iOS não tem
      // chips, e o destaque "Você" só precisa de um fundo arredondado.
      //
      // O chevron entra ao lado da cápsula, e não no lugar dela: é o que diz
      // que a célula abre algo. Só para quem pode editar — chevron em célula
      // que não faz nada é pior que célula sem chevron.
      trailing: (isMe || canEdit)
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isMe)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colors.fill,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      l.scales_you,
                      style:
                          AppTypography.caption.copyWith(color: colors.label),
                    ),
                  ),
                if (canEdit) ...[
                  const SizedBox(width: 6),
                  Icon(
                    CupertinoIcons.chevron_right,
                    size: 16,
                    color: colors.secondaryLabel,
                  ),
                ],
              ],
            )
          : null,
      onTap: canEdit ? () => _editAssignment(context, assignment) : null,
    );
  }
}

// ---------------------------------------------------------------------------
// View adhoc (sem período — próximas + anteriores)
// ---------------------------------------------------------------------------

class _AdhocView extends ConsumerWidget {
  const _AdhocView({required this.scaleType, required this.canEdit});

  final ScaleTypeRow scaleType;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final assignments = ref.watch(allAssignmentsProvider(scaleType.id));
    final currentUserId = ref.watch(currentUserIdProvider);
    final profileNames = ref.watch(profileNamesProvider);

    return assignments.when(
      loading: () => const RefreshableBox(
        child: Center(child: CupertinoActivityIndicator()),
      ),
      error: (_,_) => RefreshableBox(
        child: EmptyState(
          title: l.scales_no_assignments,
          icon: CupertinoIcons.doc_text,
        ),
      ),
      data: (data) {
        if (data.isEmpty) {
          return RefreshableBox(
            child: EmptyState(
              title: l.scales_no_assignments,
              icon: CupertinoIcons.doc_text,
            ),
          );
        }

        final now = DateTime.now();
        final upcoming = data.where((a) => a.startsOn.isAfter(now)).toList()
          ..sort((a, b) => a.startsOn.compareTo(b.startsOn));
        final past = data.where((a) => a.startsOn.isBefore(now)).toList()
          ..sort((a, b) => b.startsOn.compareTo(a.startsOn));

        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const SyncRefreshControl(),
            SliverList.list(
              children: [
                for (final a in upcoming.take(10))
                  _AssignmentListTile(
                    assignment: a,
                    isMe: currentUserId != null &&
                        isAssignedTo(a, currentUserId),
                    profileNames: profileNames,
                    canEdit: canEdit,
                  ),
                if (past.isNotEmpty)
                  _PreviousSection(
                    assignments: past.take(20).toList(),
                    currentUserId: currentUserId,
                    profileNames: profileNames,
                    canEdit: canEdit,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// _PreviousSection
// ---------------------------------------------------------------------------

/// Seção recolhível "Anteriores".
///
/// Substitui o `ExpansionTile` do Material, que não tem equivalente no
/// Cupertino: uma linha clicável com chevron, no estilo das listas de Ajustes
/// do iOS, guardando o estado de aberto/fechado localmente.
class _PreviousSection extends StatefulWidget {
  const _PreviousSection({
    required this.assignments,
    required this.currentUserId,
    required this.profileNames,
    required this.canEdit,
  });

  final List<ScaleAssignmentRow> assignments;
  final String? currentUserId;
  final Map<String, String> profileNames;
  final bool canEdit;

  @override
  State<_PreviousSection> createState() => _PreviousSectionState();
}

class _PreviousSectionState extends State<_PreviousSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          minimumSize: Size.zero,
          onPressed: () => setState(() => _expanded = !_expanded),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l.scales_previous,
                  style: AppTypography.subheadlineEmphasis
                      .copyWith(color: colors.label),
                ),
              ),
              Icon(
                _expanded
                    ? CupertinoIcons.chevron_down
                    : CupertinoIcons.chevron_right,
                size: 18,
                color: colors.secondaryLabel,
              ),
            ],
          ),
        ),
        if (_expanded)
          for (final a in widget.assignments)
            _AssignmentListTile(
              assignment: a,
              isMe: widget.currentUserId != null &&
                  isAssignedTo(a, widget.currentUserId!),
              profileNames: widget.profileNames,
              canEdit: widget.canEdit,
            ),
      ],
    );
  }
}
