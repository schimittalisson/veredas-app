import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/core/theme/app_colors.dart';
import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/ui/navigation/app_router.dart';

class VeredasApp extends ConsumerWidget {
  const VeredasApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return CupertinoApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).app_title,
      routerConfig: router,
      // O tema real é aplicado no `builder`, onde já existe um MediaQuery para
      // ler o brilho do sistema. `CupertinoApp` não tem `darkTheme` como o
      // `MaterialApp` — a alternância claro/escuro é responsabilidade nossa.
      localizationsDelegates: const [
        AppLocalizations.delegate,
        // GlobalMaterialLocalizations continua na lista por causa do
        // table_calendar, único widget Material que sobrou (ver
        // material_compat.dart). Os outros dois são exigidos pelo Cupertino.
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final brightness = MediaQuery.platformBrightnessOf(context);
        final colors =
            brightness == Brightness.dark ? AppColors.dark : AppColors.light;

        return CupertinoTheme(
          data: cupertinoThemeFor(colors, brightness),
          child: AppTheme(
            colors: colors,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
