import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veredas/data/daos/agenda_dao.dart';
import 'package:veredas/data/daos/home_dao.dart';
import 'package:veredas/data/daos/prayer_dao.dart';
import 'package:veredas/data/daos/profile_dao.dart';
import 'package:veredas/data/daos/laundry_dao.dart';
import 'package:veredas/data/daos/scales_dao.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/remote/admin_service.dart';
import 'package:veredas/data/remote/supabase_admin_service.dart';
import 'package:veredas/data/repositories/agenda_repository.dart';
import 'package:veredas/data/repositories/documents_repository.dart';
import 'package:veredas/data/repositories/home_repository.dart';
import 'package:veredas/data/repositories/prayer_repository.dart';
import 'package:veredas/data/remote/laundry_service.dart';
import 'package:veredas/data/remote/supabase_laundry_service.dart';
import 'package:veredas/data/repositories/laundry_repository.dart';
import 'package:veredas/data/repositories/scales_repository.dart';
import 'package:veredas/data/sync/connectivity_monitor.dart';
import 'package:veredas/data/sync/outbox_worker.dart';
import 'package:veredas/data/sync/remote_source.dart';
import 'package:veredas/data/sync/sync_service.dart';

/// Providers de infraestrutura — só DI (dependency injection).
///
/// São os pontos de `override` nos testes. Providers de feature (estado de
/// tela) ficam em `providers/<feature>_providers.dart`.
///
/// Padrão do CalorieMate, mantido aqui: um `Provider<T>` por dependência,
/// observando os de quem depende.

// --- Supabase -------------------------------------------------------------

/// Cliente Supabase singleton. Inicializado em `main()` via
/// `Supabase.initialize`; o `Supabase.instance.client` é estável após isso.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Provider do [AdminService]. Em testes, override com um fake.
final adminServiceProvider = Provider<AdminService>((ref) {
  return SupabaseAdminService(ref.watch(supabaseClientProvider));
});

// --- Database -------------------------------------------------------------

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

// --- DAOs ------------------------------------------------------------------

final homeDaoProvider = Provider<HomeDao>(
  (ref) => HomeDao(ref.watch(appDatabaseProvider)),
);

final agendaDaoProvider = Provider<AgendaDao>(
  (ref) => AgendaDao(ref.watch(appDatabaseProvider)),
);

final laundryDaoProvider = Provider<LaundryDao>(
  (ref) => LaundryDao(ref.watch(appDatabaseProvider)),
);

final laundryServiceProvider = Provider<LaundryService>(
  (ref) => SupabaseLaundryService(ref.watch(supabaseClientProvider)),
);

final laundryRepositoryProvider = Provider<LaundryRepository>(
  (ref) => LaundryRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(laundryServiceProvider),
  ),
);

final scalesDaoProvider = Provider<ScalesDao>(
  (ref) => ScalesDao(ref.watch(appDatabaseProvider)),
);

final prayerDaoProvider = Provider<PrayerDao>(
  (ref) => PrayerDao(ref.watch(appDatabaseProvider)),
);

final profileDaoProvider = Provider<ProfileDao>(
  (ref) => ProfileDao(ref.watch(appDatabaseProvider)),
);

// --- Repositories (escrita via outbox) --------------------------------------

final homeRepositoryProvider = Provider<HomeRepository>(
  (ref) => HomeRepository(ref.watch(appDatabaseProvider)),
);

final prayerRepositoryProvider = Provider<PrayerRepository>(
  (ref) => PrayerRepository(ref.watch(appDatabaseProvider)),
);

final agendaRepositoryProvider = Provider<AgendaRepository>(
  (ref) => AgendaRepository(ref.watch(appDatabaseProvider)),
);

final scalesRepositoryProvider = Provider<ScalesRepository>(
  (ref) => ScalesRepository(ref.watch(appDatabaseProvider)),
);

final documentsRepositoryProvider = Provider<DocumentsRepository>(
  (ref) => DocumentsRepository(ref.watch(appDatabaseProvider)),
);

// --- Remote source ---------------------------------------------------------

final remoteSourceProvider = Provider<RemoteSource>((ref) {
  return SupabaseRemoteSource(ref.watch(supabaseClientProvider));
});

// --- Sync ------------------------------------------------------------------

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(
    db: ref.watch(appDatabaseProvider),
    remote: ref.watch(remoteSourceProvider),
  );
});

// --- Connectivity ----------------------------------------------------------

/// Monitor de conectividade. Em testes, override com `FakeConnectivityMonitor`.
final connectivityMonitorProvider = Provider<ConnectivityMonitor>(
  (ref) => PluginConnectivityMonitor(),
);

/// Stream de conectividade. Emite `List<ConnectivityResult>` (pode ter
/// múltiplas interfaces ativas).
///
/// **O primeiro valor vem de `current()`, não do stream de mudanças.**
/// `onConnectivityChanged` expõe apenas *mudanças*. Sem semear o estado atual, o
/// provider fica sem valor até a rede oscilar, e `isOnlineProvider` trata "sem
/// valor" como offline. As consequências não eram só cosméticas:
///
/// - o banner "sem conexão — mostrando dados salvos" aparecia com a internet
///   funcionando normalmente;
/// - e, pior, `OutboxWorker.drain()` começa com `if (!await isConnected())
///   return`, então **nenhuma escrita saía do aparelho** enquanto isso durasse.
final connectivityStreamProvider = StreamProvider<List<ConnectivityResult>>(
  (ref) async* {
    final monitor = ref.watch(connectivityMonitorProvider);
    yield await monitor.current();
    yield* monitor.changes();
  },
);

/// `true` quando há qualquer conexão (não `none`).
final isOnlineProvider = Provider<bool>((ref) {
  final conn = ref.watch(connectivityStreamProvider).value;
  if (conn == null || conn.isEmpty) return false;
  return !conn.every((c) => c == ConnectivityResult.none);
});

/// Verificador de conectividade injetado no `OutboxWorker`. Em produção,
/// lê o `isOnlineProvider`; em testes, pode ser overridden.
final connectivityCheckProvider = Provider<Future<bool> Function()>((ref) {
  return () async => ref.read(isOnlineProvider);
});

// --- Outbox ----------------------------------------------------------------

final outboxWorkerProvider = Provider<OutboxWorker>((ref) {
  return OutboxWorker(
    db: ref.watch(appDatabaseProvider),
    remote: ref.watch(remoteSourceProvider),
    isConnected: ref.watch(connectivityCheckProvider),
  );
});

/// Stream que emite `true` quando há entradas pendentes na outbox.
final hasPendingOutboxProvider = StreamProvider<bool>((ref) {
  return ref.watch(outboxWorkerProvider).watchPending();
});

/// Stream que emite o número de entradas pendentes na outbox. Usado pelo
/// banner offline para mostrar "N alterações aguardando envio".
final pendingOutboxCountProvider = StreamProvider<int>((ref) {
  return ref.watch(outboxWorkerProvider).watchPendingCount();
});
