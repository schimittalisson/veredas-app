import 'package:flutter/material.dart';

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
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}
