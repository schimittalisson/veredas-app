import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/core/error/app_exception.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/ui/navigation/app_router.dart';

/// Avisa quando um link de autenticação abriu o app e não funcionou.
///
/// **O bug que isto corrige.** O link de recuperação de senha é amarrado ao
/// aparelho que pediu (PKCE) e ao e-mail mais recente. Aberto de outro jeito,
/// o `supabase_flutter` falhava ao trocá-lo por uma sessão e punha o erro num
/// stream que ninguém lia: o app abria e nada acontecia — a tela de nova senha
/// simplesmente não vinha, sem mensagem nenhuma.
///
/// Fica no `builder` do `CupertinoApp`, ao lado do `SyncCoordinator`, pelo
/// mesmo motivo: o link pode chegar com qualquer tela aberta. Como está acima
/// do Navigator, o alerta usa o contexto do navigator raiz.
///
/// Assina o stream do serviço direto, e não por um `StreamProvider`: o
/// Riverpod 3 filtra valores iguais com `==`, e o segundo link com problema
/// (mesmo código de erro) não geraria um segundo aviso.
class AuthLinkErrorListener extends ConsumerStatefulWidget {
  const AuthLinkErrorListener({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AuthLinkErrorListener> createState() =>
      _AuthLinkErrorListenerState();
}

class _AuthLinkErrorListenerState extends ConsumerState<AuthLinkErrorListener> {
  StreamSubscription<AppErrorCode>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription =
        ref.read(authServiceProvider).authLinkErrors.listen(_showAlert);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _showAlert(AppErrorCode code) {
    if (code != AppErrorCode.authLinkInvalid) return;
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null) return;
    final l = AppLocalizations.of(navContext);
    showCupertinoDialog<void>(
      context: navContext,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(l.auth_link_invalid_title),
        content: Text(l.auth_link_invalid_message),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l.action_ok),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
