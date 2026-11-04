import 'package:flutter/cupertino.dart';

import 'package:veredas/data/models/report_reason.dart';
import 'package:veredas/l10n/app_localizations.dart';

/// Pergunta o motivo de uma denúncia. Devolve `null` se a pessoa cancelar.
///
/// Compartilhada entre a denúncia de pedido (cartão do mural) e a de
/// comentário (detalhe da oração): os motivos são o CHECK de
/// `content_reports.reason`, e precisam ser os mesmos nas duas.
Future<ReportReason?> showReportReasonSheet(
  BuildContext context, {
  required String title,
}) {
  final l = AppLocalizations.of(context);

  return showCupertinoModalPopup<ReportReason>(
    context: context,
    builder: (sheetContext) => CupertinoActionSheet(
      title: Text(title),
      message: Text(l.prayer_report_message),
      actions: [
        for (final r in ReportReason.values)
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop(r),
            child: Text(switch (r) {
              ReportReason.offensive => l.report_reason_offensive,
              ReportReason.spam => l.report_reason_spam,
              ReportReason.other => l.report_reason_other,
            }),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.of(sheetContext).pop(),
        isDefaultAction: true,
        child: Text(l.action_cancel),
      ),
    ),
  );
}
