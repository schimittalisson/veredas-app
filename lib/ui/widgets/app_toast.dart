import 'package:flutter/cupertino.dart';

import 'package:veredas/core/theme/app_colors.dart';
import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';

/// Substituto do `SnackBar` para feedback transitório.
///
/// O Cupertino **não tem** equivalente ao `SnackBar` — a Apple não usa esse
/// padrão. O que mais se aproxima no iOS é a cápsula flutuante que aparece ao
/// silenciar o telefone ou conectar o AirPods: um HUD discreto, sem botão de
/// ação, que some sozinho.
///
/// É por isso que esta API não aceita ação nem callback: se a mensagem exige
/// uma decisão do usuário, o certo é um `CupertinoAlertDialog`, não um toast
/// que desaparece em 3 segundos.
///
/// Entra pelo `Overlay`, então flutua acima de qualquer tela — inclusive de
/// rotas empilhadas e do teclado.
void showAppToast(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;

  final entry = OverlayEntry(
    builder: (_) => _AppToast(
      message: message,
      isError: isError,
      colors: context.colors,
    ),
  );

  overlay.insert(entry);
  // 3s é o tempo do SnackBar padrão: suficiente para ler uma linha sem
  // atrapalhar quem já seguiu para a próxima ação.
  Future<void>.delayed(const Duration(seconds: 3), () {
    if (entry.mounted) entry.remove();
  });
}

class _AppToast extends StatefulWidget {
  const _AppToast({
    required this.message,
    required this.isError,
    required this.colors,
  });

  final String message;
  final bool isError;
  final AppColors colors;

  @override
  State<_AppToast> createState() => _AppToastState();
}

class _AppToastState extends State<_AppToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: const Duration(milliseconds: 250),
    vsync: this,
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    return Positioned(
      left: 16,
      right: 16,
      // Acima da tab bar (49) mais a área segura, com folga.
      bottom: MediaQuery.paddingOf(context).bottom + 68,
      child: FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.4),
            end: Offset.zero,
          ).animate(curve),
          child: _Capsule(
            message: widget.message,
            background:
                widget.isError ? colors.destructive : colors.label,
            foreground: widget.isError
                ? colors.onDestructive
                : colors.groupedBackground,
          ),
        ),
      ),
    );
  }
}

class _Capsule extends StatelessWidget {
  const _Capsule({
    required this.message,
    required this.background,
    required this.foreground,
  });

  final String message;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Align(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: const Color(0x33000000),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.subheadline.copyWith(color: foreground),
          ),
        ),
      ),
    );
  }
}
