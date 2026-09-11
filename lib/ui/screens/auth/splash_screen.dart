import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/providers/auth_providers.dart';

/// Tela de splash. Mostra a logo enquanto o router decide o destino.
///
/// **Esta tela imita o splash nativo de propósito.** Ela aparece logo depois
/// dele na abertura do app, então qualquer diferença de fundo, de tamanho ou
/// de posição da logo é percebida como um segundo splash piscando. As medidas
/// abaixo existem para a emenda ser invisível — ver os comentários.
///
/// Ela é usada em dois momentos, e o segundo é o mais longo:
/// 1. Abertura, enquanto o `authStateProvider` resolve a sessão (rápido, local).
/// 2. Depois do login numa instalação nova, enquanto o
///    `profileBootstrapProvider` puxa o perfil do servidor (~1-2s de rede).
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  /// Lado da logo. 168 não é arbitrário: com a marca ocupando 54,3% x 85,2%
  /// do `logo.jpg`, este valor a renderiza em 91,2 x 143,1 — que é exatamente
  /// o tamanho do `LaunchImage` no splash nativo do iOS (168x185pt com
  /// `contentMode="center"`, medido em 91,3 x 143). No Android o ícone do
  /// sistema sai em ~78 x 122dp, então sobra uma diferença pequena ali.
  static const double _logoSize = 168;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // O auth cobre a abertura; o bootstrap cobre a espera pós-login. Sem o
    // segundo, aqueles 1-2s de pull do perfil ficavam com a logo parada e
    // nenhum indicador — o app parecia travado.
    final isLoading = ref.watch(authStateProvider).isLoading ||
        ref.watch(profileBootstrapProvider).isLoading;

    // Branco fixo, e não `colors.groupedBackground`: os dois splashes nativos
    // são brancos em qualquer tema (`launch_background.xml` no Android,
    // `LaunchScreen.storyboard` no iOS). Com o creme do tema aparecia uma troca
    // de fundo na abertura, e a logo — que é JPEG, sem canal alpha — virava um
    // quadrado branco sobre o creme.
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.white,
      child: Center(
        // A logo fica no centro exato da tela, como nos dois nativos, e o
        // spinner é posicionado fora do fluxo. Numa Column ele empurraria a
        // logo para cima ao aparecer, e ela desceria de novo ao sumir —
        // deslocamento visível justamente na emenda com o splash nativo.
        child: SizedBox(
          width: _logoSize,
          height: _logoSize,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Image.asset(
                'assets/images/logo.jpg',
                width: _logoSize,
                height: _logoSize,
                fit: BoxFit.contain,
              ),
              if (isLoading)
                const Positioned(
                  bottom: -52,
                  child: CupertinoActivityIndicator(radius: 14),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
