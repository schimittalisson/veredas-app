import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/core/error/app_exception.dart';
import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/providers/laundry_providers.dart';
import 'package:veredas/providers/sync_providers.dart';
import 'package:veredas/ui/widgets/app_toast.dart';
import 'package:veredas/ui/widgets/confirm_dialog.dart';
import 'package:veredas/ui/widgets/empty_state.dart';
import 'package:veredas/ui/widgets/pull_to_refresh.dart';

/// Aba Lavanderia — a planilha de uso das máquinas, agora reservável no app.
///
/// Substitui a planilha semanal que a base mantinha à mão: linhas são faixas de
/// horário, colunas são as máquinas, e cada célula é livre, intervalo (máquina
/// indisponível) ou reservada por alguém.
///
/// **Semana + dia, e não a planilha inteira.** A planilha original tem 7 dias ×
/// 3 máquinas = 21 colunas, o que no celular só existiria atrás de scroll
/// horizontal. Aqui a semana é escolhida no topo, o dia numa faixa logo abaixo,
/// e a grade mostra as 3 máquinas por inteiro — sem rolagem lateral e sem
/// esconder coluna.
///
/// **Por que o pull-to-refresh importa aqui mais que nas outras abas.** A vaga
/// é disputada: a grade desenhada pode estar velha. Arrastar para atualizar é o
/// gesto que evita tocar num horário que outra pessoa já levou — e, quando
/// ainda assim acontecer, quem recusa é o índice único do banco, não esta tela.
class LaundryTab extends ConsumerWidget {
  const LaundryTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final machines = ref.watch(laundryMachinesProvider).value ?? const [];
    final timeSlots = ref.watch(laundryTimeSlotsProvider).value ?? const [];

    // Sem cadastro não há grade que desenhar. O estado vazio continua
    // arrastável: é onde o obreiro mais quer puxar para buscar novidade.
    //
    // `RefreshableBox` já é um `CustomScrollView` completo, com o próprio
    // `SyncRefreshControl` dentro — não é um sliver. Aninhá-lo numa lista de
    // slivers compila, mas estoura no layout e a aba fica em branco.
    if (machines.isEmpty || timeSlots.isEmpty) {
      return RefreshableBox(
        child: EmptyState(
          title: l.laundry_empty_setup,
          icon: CupertinoIcons.drop,
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        const SyncRefreshControl(),
        const SliverToBoxAdapter(child: _WeekNavigator()),
        const SliverToBoxAdapter(child: _DayStrip()),
        SliverToBoxAdapter(
          child: _Grid(machines: machines, timeSlots: timeSlots),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _selectedDayProvider
// ---------------------------------------------------------------------------

/// Dia escolhido na faixa, como deslocamento (0 = segunda) dentro da semana.
///
/// Guardado como deslocamento e não como data para sobreviver à troca de
/// semana: mudar de semana mantém o mesmo dia da semana selecionado, que é o
/// que se espera ao comparar "a terça que vem" com "esta terça".
class _SelectedDayNotifier extends Notifier<int> {
  @override
  int build() => DateTime.now().weekday - 1;

  void set(int dayOffset) => state = dayOffset;
}

final _selectedDayProvider =
    NotifierProvider<_SelectedDayNotifier, int>(_SelectedDayNotifier.new);

// ---------------------------------------------------------------------------
// _WeekNavigator
// ---------------------------------------------------------------------------

class _WeekNavigator extends ConsumerWidget {
  const _WeekNavigator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final monday = ref.watch(laundryWeekProvider);
    final sunday = monday.add(const Duration(days: 6));

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () =>
                ref.read(laundryWeekProvider.notifier).previous(),
            child: Icon(CupertinoIcons.chevron_left, color: colors.tint),
          ),
          Expanded(
            child: GestureDetector(
              // Toque no meio volta para a semana atual — o caminho de volta
              // sem ter de contar quantas semanas se avançou.
              onTap: () => ref.read(laundryWeekProvider.notifier).reset(),
              child: Text(
                l.laundry_week_of(_short(monday), _short(sunday)),
                textAlign: TextAlign.center,
                style: AppTypography.subheadline.copyWith(color: colors.label),
              ),
            ),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => ref.read(laundryWeekProvider.notifier).next(),
            child: Icon(CupertinoIcons.chevron_right, color: colors.tint),
          ),
        ],
      ),
    );
  }

  static String _short(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// _DayStrip
// ---------------------------------------------------------------------------

class _DayStrip extends ConsumerWidget {
  const _DayStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final monday = ref.watch(laundryWeekProvider);
    final selected = ref.watch(_selectedDayProvider);

    final labels = [
      l.agenda_weekday_mon,
      l.agenda_weekday_tue,
      l.agenda_weekday_wed,
      l.agenda_weekday_thu,
      l.agenda_weekday_fri,
      l.agenda_weekday_sat,
      l.agenda_weekday_sun,
    ];

    return SizedBox(
      height: 64,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: 7,
        itemBuilder: (context, i) {
          final date = monday.add(Duration(days: i));
          final isSelected = i == selected;
          return CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: Size.zero,
            onPressed: () =>
                ref.read(_selectedDayProvider.notifier).set(i),
            child: Container(
              width: 52,
              decoration: BoxDecoration(
                color: isSelected ? colors.tint : colors.fill,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    labels[i],
                    style: AppTypography.footnote.copyWith(
                      color: isSelected ? colors.surface : colors.label,
                    ),
                  ),
                  Text(
                    date.day.toString().padLeft(2, '0'),
                    style: AppTypography.subheadline.copyWith(
                      color: isSelected
                          ? colors.surface
                          : colors.secondaryLabel,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _Grid
// ---------------------------------------------------------------------------

class _Grid extends ConsumerWidget {
  const _Grid({required this.machines, required this.timeSlots});

  final List<LaundryMachineRow> machines;
  final List<LaundryTimeSlotRow> timeSlots;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final monday = ref.watch(laundryWeekProvider);
    final dayOffset = ref.watch(_selectedDayProvider);
    final date = monday.add(Duration(days: dayOffset));
    final weekday = date.weekday;

    final blocks = ref.watch(laundryBlocksProvider).value ?? const {};
    final reservations =
        ref.watch(laundryReservationsProvider).value ?? const {};

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          // Cabeçalho: os nomes das máquinas.
          Row(
            children: [
              const SizedBox(width: 56),
              for (final m in machines)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        Text(
                          m.name,
                          textAlign: TextAlign.center,
                          style: AppTypography.footnote
                              .copyWith(color: colors.label),
                        ),
                        if (m.note != null && m.note!.isNotEmpty)
                          Text(
                            m.note!,
                            textAlign: TextAlign.center,
                            style: AppTypography.caption
                                .copyWith(color: colors.secondaryLabel),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          for (final slot in timeSlots)
            // `IntrinsicHeight` é o que permite o `stretch`: dentro de uma
            // Column sem altura definida, esticar no eixo cruzado pediria
            // altura infinita e a grade estouraria no layout. Com ele, a
            // linha mede a célula mais alta e as demais acompanham — que é o
            // que mantém as colunas alinhadas quando um nome quebra em duas
            // linhas.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 56,
                    child: Center(
                      child: Text(
                        _formatMinutes(slot.startsAtMinutes),
                        style: AppTypography.caption
                            .copyWith(color: colors.secondaryLabel),
                      ),
                    ),
                  ),
                  for (final machine in machines)
                    Expanded(
                      child: _Cell(
                        machine: machine,
                        slot: slot,
                        date: date,
                        blockId: blocks[blockKey(machine.id, slot.id, weekday)],
                        reservation: reservations[
                            reservationKey(machine.id, slot.id, date)],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _formatMinutes(int minutes) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(minutes ~/ 60)}:${two(minutes % 60)}';
  }
}

// ---------------------------------------------------------------------------
// _Cell
// ---------------------------------------------------------------------------

/// Uma célula da grade: livre, intervalo ou reservada.
///
/// Concentra as três ações possíveis porque o estado da célula é exatamente o
/// que decide qual delas faz sentido — espalhar isso pela tela faria a regra
/// aparecer em três lugares e divergir no primeiro ajuste.
class _Cell extends ConsumerStatefulWidget {
  const _Cell({
    required this.machine,
    required this.slot,
    required this.date,
    required this.blockId,
    required this.reservation,
  });

  final LaundryMachineRow machine;
  final LaundryTimeSlotRow slot;
  final DateTime date;
  final String? blockId;
  final LaundryReservationRow? reservation;

  @override
  ConsumerState<_Cell> createState() => _CellState();
}

class _CellState extends ConsumerState<_Cell> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final userId = ref.watch(currentUserIdProvider);

    final isBlocked = widget.blockId != null;
    final reservation = widget.reservation;
    final isMine = reservation != null && reservation.userId == userId;

    final (Color bg, Color fg, String label) = switch (
        (isBlocked, reservation, isMine)) {
      (true, _, _) => (colors.destructive, colors.surface, l.laundry_blocked),
      (_, final r?, true) => (colors.tint, colors.surface, l.laundry_mine),
      (_, final r?, false) => (
          colors.fill,
          colors.secondaryLabel,
          l.laundry_reserved_by(r.userName),
        ),
      _ => (colors.surface, colors.tint, l.laundry_free),
    };

    return Padding(
      padding: const EdgeInsets.all(2),
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        minimumSize: Size.zero,
        borderRadius: BorderRadius.circular(8),
        color: bg,
        onPressed: _busy ? null : _onTap,
        child: _busy
            ? const CupertinoActivityIndicator(radius: 8)
            : Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(color: fg),
              ),
      ),
    );
  }

  Future<void> _onTap() async {
    final l = AppLocalizations.of(context);
    final isAdmin = ref.read(isAdminProvider);
    final userId = ref.read(currentUserIdProvider);
    final reservation = widget.reservation;

    // Intervalo: só o admin tem o que fazer aqui — liberar a célula.
    if (widget.blockId != null) {
      if (!isAdmin) return;
      final ok = await ConfirmDialog.show(
        context,
        title: l.laundry_admin_unblock,
        message: l.laundry_admin_block_hint,
      );
      if (ok != true) return;
      await _run(() async {
        await ref
            .read(laundryRepositoryProvider)
            .unblockSlot(widget.blockId!);
      }, l.laundry_admin_unblocked_done);
      return;
    }

    if (reservation != null) {
      // Reserva de outra pessoa. A mensagem é a mesma do conflito no servidor:
      // do ponto de vista de quem tocou, a planilha estava velha.
      if (reservation.userId != userId && !isAdmin) {
        showAppToast(context, l.laundry_error_taken, isError: true);
        return;
      }
      final ok = await ConfirmDialog.show(
        context,
        title: l.laundry_cancel,
        message: l.laundry_cancel_confirm(
          widget.machine.name,
          _Grid._formatMinutes(widget.slot.startsAtMinutes),
        ),
      );
      if (ok != true) return;
      await _run(() async {
        await ref
            .read(laundryRepositoryProvider)
            .cancelReservation(reservation.id);
      }, l.laundry_cancel_done);
      return;
    }

    // Célula livre. Para o admin há duas ações possíveis, então ele escolhe.
    if (isAdmin) {
      final action = await showCupertinoModalPopup<String>(
        context: context,
        builder: (sheetContext) => CupertinoActionSheet(
          actions: [
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop('reserve'),
              child: Text(l.laundry_reserve),
            ),
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop('block'),
              child: Text(l.laundry_admin_block),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop(),
            child: Text(l.action_cancel),
          ),
        ),
      );
      if (action == null || !mounted) return;
      if (action == 'block') {
        await _run(() async {
          await ref.read(laundryRepositoryProvider).blockSlot(
                machineId: widget.machine.id,
                timeSlotId: widget.slot.id,
                weekday: widget.date.weekday,
              );
        }, l.laundry_admin_blocked_done);
        return;
      }
    }

    await _reserve();
  }

  Future<void> _reserve() async {
    final l = AppLocalizations.of(context);
    final ok = await ConfirmDialog.show(
      context,
      title: l.laundry_reserve,
      message: l.laundry_reserve_confirm(
        widget.machine.name,
        '${widget.date.day.toString().padLeft(2, '0')}/'
            '${widget.date.month.toString().padLeft(2, '0')}',
        _Grid._formatMinutes(widget.slot.startsAtMinutes),
      ),
    );
    if (ok != true) return;

    await _run(() async {
      await ref.read(laundryRepositoryProvider).reserve(
            machineId: widget.machine.id,
            timeSlotId: widget.slot.id,
            onDate: widget.date,
          );
    }, l.laundry_reserved_done);
  }

  /// Executa a ação, traduz o erro e **sempre** sincroniza depois.
  ///
  /// O pull no fim não é detalhe: nem a reserva nem o cancelamento escrevem no
  /// cache, então é ele que traz a célula de volta no estado real. E no caso do
  /// conflito ele é ainda mais importante — a grade está comprovadamente velha,
  /// e atualizar evita o segundo toque no mesmo horário já tomado.
  Future<void> _run(Future<void> Function() action, String successMessage) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) showAppToast(context, successMessage);
    } on AppException catch (e) {
      if (mounted) {
        showAppToast(context, _errorMessage(e.code), isError: true);
      }
    } catch (_) {
      if (mounted) {
        showAppToast(context, AppLocalizations.of(context).auth_error_unknown,
            isError: true);
      }
    } finally {
      // `pullAll` fora do try: mesmo com falha a grade precisa ser refeita.
      await ref.read(syncStatusProvider.notifier).pullAll();
      if (mounted) setState(() => _busy = false);
    }
  }

  String _errorMessage(AppErrorCode code) {
    final l = AppLocalizations.of(context);
    return switch (code) {
      AppErrorCode.conflict => l.laundry_error_taken,
      AppErrorCode.laundrySlotBlocked => l.laundry_error_blocked,
      AppErrorCode.laundryPastDate => l.laundry_error_past,
      AppErrorCode.noConnection => l.error_no_connection,
      AppErrorCode.permissionDenied => l.auth_error_unknown,
      _ => l.auth_error_unknown,
    };
  }
}
