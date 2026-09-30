import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:veredas/core/config/links.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/ui/widgets/app_toast.dart';

/// Abre os Termos de uso no navegador. Usado pelo cadastro e pelo menu da
/// conta na tela Início.
Future<void> openTermsOfUse(BuildContext context) async {
  final l = AppLocalizations.of(context);
  final ok = await launchUrl(
    AppLinks.termsOfUse,
    mode: LaunchMode.externalApplication,
  );
  if (!ok && context.mounted) {
    showAppToast(context, l.terms_open_error, isError: true);
  }
}
