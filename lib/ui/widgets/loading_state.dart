import 'package:flutter/cupertino.dart';

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';

/// Indicador de carregamento compartilhado.
///
/// Usado no ramo `loading` de `AsyncValue.when`. Como as telas leem do cache
/// local (drift), este estado é raro em uso normal — aparece no primeiro
/// carregamento e depois praticamente nunca.
class LoadingState extends StatelessWidget {
  const LoadingState({this.message, super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CupertinoActivityIndicator(radius: 14),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: AppTypography.subheadline
                  .copyWith(color: colors.secondaryLabel),
            ),
          ],
        ],
      ),
    );
  }
}
