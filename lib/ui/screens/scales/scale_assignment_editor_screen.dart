import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/admin_providers.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/ui/widgets/app_toast.dart';
import 'package:veredas/ui/widgets/confirm_dialog.dart';

/// Editor de atribuição de escala — cria ou edita.
///
/// [scaleTypeId] é sempre necessário (define em qual escala a atribuição
/// será criada). [assignmentId] é null para criação.
class ScaleAssignmentEditorScreen extends ConsumerStatefulWidget {
  const ScaleAssignmentEditorScreen({
    super.key,
    required this.scaleTypeId,
    this.assignmentId,
  });

  final String scaleTypeId;
  final String? assignmentId;

  @override
  ConsumerState<ScaleAssignmentEditorScreen> createState() =>
      _ScaleAssignmentEditorScreenState();
}

// ---------------------------------------------------------------------------
// _ScaleAssignmentEditorScreenState
// ---------------------------------------------------------------------------

class _ScaleAssignmentEditorScreenState
    extends ConsumerState<ScaleAssignmentEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _taskController = TextEditingController();
  final _memberNamesController = TextEditingController();
  final _leadNameController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime _date = DateTime.now();
  String? _slot;

  /// Equipe escalada, entre os obreiros com conta no app. Uma atribuição pode
  /// ter várias pessoas — é o caso do almoço, feito por um grupo.
  List<String> _memberIds = const [];

  /// Responsável geral sobre a equipe. Opcional: nem toda escala tem um.
  String? _leadId;

  bool _loaded = false;
  bool _saving = false;

  bool get _isEditing => widget.assignmentId != null;

  @override
  void dispose() {
    _taskController.dispose();
    _memberNamesController.dispose();
    _leadNameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;

    if (_isEditing && !_loaded) {
      _loadExisting();
    }

    // Slots disponíveis do scale_type.
    final scaleTypes = ref.watch(allScaleTypesProvider).value ?? const [];
    final scaleType =
        scaleTypes.where((t) => t.id == widget.scaleTypeId).firstOrNull;
    final slots = scaleType?.slots ?? const <String>[];

    // Obreiros aprovados: a fonte tanto da equipe quanto do responsável geral.
    final profiles = ref.watch(approvedProfilesProvider);
    final names = {for (final p in profiles) p.id: p.fullName};

    // O "—" na frente é a opção "sem responsável geral" — que é o normal, não
    // a exceção: a maioria das escalas não tem alguém acima da equipe.
    final leadIds = <String?>[null, ...profiles.map((p) => p.id)];
    final leadLabels = <String?, String>{null: '—', ...names};

    final teamLabel = _memberIds.isEmpty
        ? '—'
        : _memberIds
            .map((id) => names[id] ?? l.scales_assignee_unknown)
            .join(', ');

    // Salvar mora no `trailing` da barra — ver a nota em
    // `announcement_editor_screen.dart` sobre por que o botão do fim saiu.
    return CupertinoPageScaffold(
      backgroundColor: colors.groupedBackground,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: colors.elevatedSurface,
        middle: Text(_isEditing ? l.action_edit : l.scales_new_assignment),
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
                  _ValueRow(
                    label: l.scales_assignment_date,
                    value: _formatDate(_date),
                    onTap: _pickDate,
                  ),
                  if (slots.isNotEmpty)
                    _ValueRow(
                      label: l.scales_assignment_slot,
                      value: _slot ?? '—',
                      onTap: () => _pickSlot(slots),
                    ),
                  CupertinoTextFormFieldRow(
                    controller: _taskController,
                    textAlign: TextAlign.end,
                    prefix: Text(
                      l.scales_assignment_task,
                      style: AppTypography.body.copyWith(color: colors.label),
                    ),
                    style: AppTypography.body.copyWith(color: colors.label),
                  ),
                ],
              ),

              // Equipe: quem faz a tarefa. Seleção múltipla, porque uma
              // escala pode ser de um grupo inteiro.
              CupertinoFormSection.insetGrouped(
                backgroundColor: colors.groupedBackground,
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                // O `helperText` do campo Material vira o rodapé da seção: é
                // onde o iOS coloca a explicação de um grupo de células.
                footer: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    l.scales_assignment_team_names_helper,
                    style: AppTypography.footnote
                        .copyWith(color: colors.secondaryLabel),
                  ),
                ),
                children: [
                  _ValueRow(
                    label: l.scales_assignment_team,
                    value: teamLabel,
                    onTap: () => _pickTeam(profiles),
                  ),
                  CupertinoTextFormFieldRow(
                    controller: _memberNamesController,
                    textAlign: TextAlign.end,
                    prefix: Text(
                      l.scales_assignment_team_names,
                      style: AppTypography.body.copyWith(color: colors.label),
                    ),
                    style: AppTypography.body.copyWith(color: colors.label),
                  ),
                ],
              ),

              // Responsável geral: fica sobre a equipe e pode não existir.
              CupertinoFormSection.insetGrouped(
                backgroundColor: colors.groupedBackground,
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                footer: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    l.scales_assignment_lead_helper,
                    style: AppTypography.footnote
                        .copyWith(color: colors.secondaryLabel),
                  ),
                ),
                children: [
                  _ValueRow(
                    label: l.scales_assignment_lead,
                    value: leadLabels[_leadId] ?? '—',
                    onTap: () => _pickLead(leadIds, leadLabels),
                  ),
                  CupertinoTextFormFieldRow(
                    controller: _leadNameController,
                    textAlign: TextAlign.end,
                    prefix: Text(
                      l.scales_assignment_lead_name,
                      style: AppTypography.body.copyWith(color: colors.label),
                    ),
                    style: AppTypography.body.copyWith(color: colors.label),
                  ),
                ],
              ),

              CupertinoFormSection.insetGrouped(
                backgroundColor: colors.groupedBackground,
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                children: [
                  CupertinoTextFormFieldRow(
                    controller: _notesController,
                    placeholder: l.scales_assignment_notes,
                    maxLines: 3,
                    style: AppTypography.body.copyWith(color: colors.label),
                  ),
                ],
              ),

              // Excluir mora aqui, e não num menu na tela Escalas: a grade de
              // slots é densa e um gesto destrutivo sobre uma célula de poucos
              // milímetros erra fácil. Mesma posição do editor de escala em
              // `admin/scale_type_editor_screen.dart` — última seção, em
              // vermelho, atrás de uma confirmação.
              if (_isEditing)
                CupertinoListSection.insetGrouped(
                  backgroundColor: colors.groupedBackground,
                  separatorColor: colors.separator,
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  children: [
                    CupertinoListTile(
                      title: Text(
                        l.scales_assignment_delete,
                        style: AppTypography.body
                            .copyWith(color: colors.destructive),
                      ),
                      onTap: _saving ? null : _delete,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _delete() async {
    final l = AppLocalizations.of(context);

    final confirmed = await ConfirmDialog.show(
      context,
      title: l.scales_assignment_delete_confirm,
      // Aponta a alternativa: quem só quer trocar a pessoa escalada deve
      // editar, senão perde a tarefa, as notas e o slot junto.
      message: l.scales_assignment_delete_message,
    );
    if (!confirmed || !mounted) return;

    setState(() => _saving = true);
    try {
      await ref
          .read(scalesRepositoryProvider)
          .deleteAssignment(widget.assignmentId!);
      if (mounted) {
        showAppToast(context, l.scales_assignment_deleted);
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, e.toString(), isError: true);
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _loadExisting() async {
    final dao = ref.read(scalesDaoProvider);
    final row = await dao.getAssignment(widget.assignmentId!);
    if (row != null && mounted) {
      _taskController.text = row.task ?? '';
      _memberNamesController.text = row.memberNames.join(', ');
      _leadNameController.text = row.assigneeName ?? '';
      _notesController.text = row.notes ?? '';
      setState(() {
        _date = row.startsOn;
        _slot = row.slot;
        _memberIds = row.memberIds;
        _leadId = row.assigneeId;
        _loaded = true;
      });
    }
  }

  /// Roda de data no lugar do `showDatePicker` — o calendário em grade é um
  /// padrão do Material; o iOS resolve datas com rolagem.
  ///
  /// A janela (1 ano atrás, 2 anos à frente) é a mesma de antes, e o valor só
  /// é aplicado se o usuário confirmar.
  Future<void> _pickDate() async {
    var picked = DateTime(_date.year, _date.month, _date.day);
    final confirmed = await _showPickerSheet(
      child: CupertinoDatePicker(
        mode: CupertinoDatePickerMode.date,
        initialDateTime: _date,
        minimumDate: DateTime.now().subtract(const Duration(days: 365)),
        maximumDate: DateTime.now().add(const Duration(days: 365 * 2)),
        onDateTimeChanged: (v) => picked = v,
      ),
      height: 260,
    );
    if (confirmed && mounted) {
      setState(() => _date = picked);
    }
  }

  /// Slot do tipo de escala. Lista de itens preservada do dropdown original.
  Future<void> _pickSlot(List<String> slots) async {
    var selected = _slot ?? slots.first;
    final confirmed = await _showPickerSheet(
      child: CupertinoPicker(
        magnification: 1.1,
        squeeze: 1.2,
        itemExtent: 32,
        scrollController: FixedExtentScrollController(
          initialItem: _slot == null
              ? 0
              : slots.indexOf(_slot!).clamp(0, slots.length - 1),
        ),
        onSelectedItemChanged: (i) => selected = slots[i],
        children: [for (final s in slots) Center(child: Text(s))],
      ),
    );
    if (!confirmed || !mounted) return;
    setState(() => _slot = selected);
  }

  /// Responsável geral. O primeiro item é "nenhum" (`null`), que é um valor
  /// legítimo e não uma pendência: escala sem responsável geral é o caso comum.
  Future<void> _pickLead(
    List<String?> ids,
    Map<String?, String> labels,
  ) async {
    var selected = _leadId;
    final confirmed = await _showPickerSheet(
      child: CupertinoPicker(
        magnification: 1.1,
        squeeze: 1.2,
        itemExtent: 32,
        scrollController: FixedExtentScrollController(
          initialItem: ids.indexOf(_leadId).clamp(0, ids.length - 1),
        ),
        onSelectedItemChanged: (i) => selected = ids[i],
        children: [
          for (final id in ids) Center(child: Text(labels[id] ?? '—')),
        ],
      ),
    );
    if (!confirmed || !mounted) return;
    setState(() => _leadId = selected);
  }

  /// Equipe — seleção múltipla.
  ///
  /// Não é um `CupertinoPicker` como os outros campos: a roda escolhe **um**
  /// valor, e aqui a resposta é um conjunto. O formato é a lista de marcar do
  /// iOS (toque alterna o check), com a seleção mantida num estado local da
  /// folha para que "voltar" desfaça tudo, e não pela metade.
  Future<void> _pickTeam(List<ProfileRow> profiles) async {
    final colors = context.colors;
    final l = AppLocalizations.of(context);
    final selected = _memberIds.toSet();

    final confirmed = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (sheetContext) => Container(
        height: MediaQuery.of(sheetContext).size.height * 0.6,
        color: colors.surface,
        child: SafeArea(
          top: false,
          child: StatefulBuilder(
            builder: (context, setSheetState) => Column(
              children: [
                Row(
                  children: [
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l.scales_assignment_team_count(selected.length),
                        style: AppTypography.subheadline
                            .copyWith(color: colors.secondaryLabel),
                      ),
                    ),
                    CupertinoButton(
                      onPressed: () => Navigator.of(sheetContext).pop(true),
                      child: Text(l.action_done),
                    ),
                  ],
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: profiles.length,
                    itemBuilder: (context, i) {
                      final p = profiles[i];
                      final isSelected = selected.contains(p.id);
                      return CupertinoListTile(
                        title: Text(
                          p.fullName,
                          style: AppTypography.body
                              .copyWith(color: colors.label),
                        ),
                        trailing: isSelected
                            ? Icon(CupertinoIcons.check_mark,
                                color: colors.tint)
                            : null,
                        onTap: () => setSheetState(() {
                          if (isSelected) {
                            selected.remove(p.id);
                          } else {
                            selected.add(p.id);
                          }
                        }),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    // Preserva a ordem da lista de obreiros, e não a ordem dos toques: a
    // escala precisa sair igual toda vez que for aberta.
    setState(() {
      _memberIds = [
        for (final p in profiles)
          if (selected.contains(p.id)) p.id,
      ];
    });
  }

  /// Folha modal padrão dos seletores: altura fixa, fundo de cartão e um botão
  /// de confirmar. Sem o confirmar, girar a roda já aplicaria o valor — o que
  /// torna impossível desistir da alteração.
  Future<bool> _showPickerSheet({
    required Widget child,
    double height = 260,
  }) async {
    final colors = context.colors;
    final l = AppLocalizations.of(context);

    final result = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (sheetContext) => Container(
        height: height,
        color: colors.surface,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: CupertinoButton(
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  child: Text(l.action_done),
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }

  /// "Ana, Bia ,, Caio" -> ["Ana", "Bia", "Caio"].
  ///
  /// Campo livre separado por vírgula em vez de uma lista editável: quem não
  /// tem conta no app é a minoria dos escalados, e digitar corrido é mais
  /// rápido do que abrir um formulário por nome.
  static List<String> _parseNames(String raw) {
    return [
      for (final part in raw.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    ];
  }

  String _formatDate(DateTime dt) {
    final d = dt.toLocal();
    return '${d.day}/${d.month}/${d.year}';
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);

    final memberNames = _parseNames(_memberNamesController.text);
    final leadName = _leadNameController.text.trim();

    // A atribuição precisa apontar para alguém — equipe ou responsável geral.
    // Mesma regra do CHECK `assignment_has_someone` no servidor; aqui ela
    // existe só para o erro aparecer antes da viagem até o Supabase.
    if (_memberIds.isEmpty &&
        memberNames.isEmpty &&
        _leadId == null &&
        leadName.isEmpty) {
      showAppToast(
        context,
        l.scales_assignment_people_required,
        isError: true,
      );
      return;
    }

    setState(() => _saving = true);
    final repo = ref.read(scalesRepositoryProvider);

    final task = _taskController.text.trim();
    final notes = _notesController.text.trim();

    try {
      if (_isEditing) {
        await repo.updateAssignment(
          id: widget.assignmentId!,
          scaleTypeId: widget.scaleTypeId,
          startsOn: _date,
          slot: _slot,
          task: task.isEmpty ? null : task,
          assigneeId: _leadId,
          assigneeName: leadName.isEmpty ? null : leadName,
          memberIds: _memberIds,
          memberNames: memberNames,
          notes: notes.isEmpty ? null : notes,
        );
      } else {
        await repo.createAssignment(
          scaleTypeId: widget.scaleTypeId,
          startsOn: _date,
          slot: _slot,
          task: task.isEmpty ? null : task,
          assigneeId: _leadId,
          assigneeName: leadName.isEmpty ? null : leadName,
          memberIds: _memberIds,
          memberNames: memberNames,
          notes: notes.isEmpty ? null : notes,
        );
      }

      if (mounted) {
        showAppToast(context, l.scales_assignment_saved);
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

// ---------------------------------------------------------------------------
// _ValueRow
// ---------------------------------------------------------------------------

/// Linha de formulário que mostra um valor e abre um seletor ao ser tocada.
///
/// Substitui o `ListTile` com `trailing: Icon(chevron_right)`: dentro de uma
/// `CupertinoFormSection` a célula precisa ser um `CupertinoFormRow`, senão os
/// separadores e o recuo do grupo não se aplicam.
class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return CupertinoFormRow(
      prefix: Text(
        label,
        style: AppTypography.body.copyWith(color: colors.label),
      ),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                style:
                    AppTypography.body.copyWith(color: colors.secondaryLabel),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              CupertinoIcons.chevron_right,
              size: 16,
              color: colors.tertiaryLabel,
            ),
          ],
        ),
      ),
    );
  }
}
