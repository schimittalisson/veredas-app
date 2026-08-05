import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'package:veredas/app.dart';
import 'package:veredas/core/config/env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // pt-BR para formatação de data (o TableCalendar e o DateFormat dependem
  // disto estar carregado antes do primeiro build).
  await initializeDateFormatting('pt_BR');
  timeago.setLocaleMessages('pt_BR', timeago.PtBrMessages());

  // Enquanto o projeto Supabase não existir (Fase 1), o app roda sem backend
  // para permitir validar navegação e tema. A partir da Fase 3 a ausência de
  // credenciais passa a ser um erro fatal — o login não funciona sem elas.
  if (Env.isConfigured) {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      // `anonKey` foi depreciado no supabase_flutter 2.16 (o PLANO.md e o
      // AGENTS.md ainda citam o nome antigo). O parâmetro aceita tanto a
      // "anon key" legada quanto a "publishable key" nova do painel, então a
      // variável de ambiente continua sendo SUPABASE_ANON_KEY.
      publishableKey: Env.supabaseAnonKey,
    );
  } else {
    debugPrint(
      'AVISO: SUPABASE_URL/SUPABASE_ANON_KEY ausentes — rodando sem backend. '
      'Use --dart-define-from-file=env/dev.json (ver supabase/README.md).',
    );
  }

  runApp(const ProviderScope(child: VeredasApp()));
}
