# Veredas App — Regras do Projeto

**Leia este arquivo antes de escrever qualquer código.** Ele contém as
convenções, os comandos e — o mais importante — as armadilhas de versão que vão
te custar tempo se você ignorá-las.

Ordem de leitura: `docs/PLANO.md` → este arquivo → `docs/SCHEMA.md` / `docs/TELAS.md`.

---

## 1. Contexto

App de gerenciamento da Base Missionária JOCUM Veredas (Joinville/SC), ~30 obreiros.
Flutter + Supabase, com cache offline em drift.

- **Este projeto**: `/home/alisson.silva/Documentos/veredas-app`
- **Projeto de referência** (arquitetura a reaproveitar):
  `/home/alisson.silva/Documentos/CalorieMateFlutter`

O CalorieMate é um app **single-user, 100% local**. O Veredas é **multi-usuário
com backend e permissões**. Os padrões de UI, navegação e organização de camadas
são reaproveitáveis; a camada de dados é fundamentalmente diferente.

---

## 2. Ambiente

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
```

- **Flutter ≥ 3.44.8 / Dart ≥ 3.12.2** obrigatório.
  O SDK instalado originalmente era 3.24.5 (nov/2024) e **não resolve as
  dependências deste projeto**. Rode `flutter upgrade` na Fase 0 e confirme com
  `flutter --version`.
- JDK 17 para o build Android:
  `flutter config --jdk-dir=/usr/lib/jvm/java-17-openjdk-amd64`
- `libsqlite3-dev` instalado para rodar testes de drift no desktop:
  `sudo apt install libsqlite3-dev`
- iOS **não compila no Linux**. Configure os arquivos (`Info.plist`, `Podfile`,
  deep links) e documente; o build só roda em macOS com Xcode 15+ (Flutter 3.44
  exige Xcode 15, que exige macOS Ventura 13.5+, que exige Mac 2017+).
  **Alternativa sem Mac**: Codemagic CI/CD (ver `codemagic.yaml` na raiz).
  Plano gratuito: 500 min/mês de macOS M2 na nuvem. Comece pelo workflow
  `ios-unsigned` para validar, depois configure certificados Apple para o
  `ios-release` gerar o `.ipa` assinado para TestFlight/App Store.

---

## 3. Comandos

```bash
# Análise e testes
flutter analyze
flutter test
flutter test test/sync/                     # suíte específica

# Rodar (segredos via dart-define, NUNCA .env como asset)
flutter run --dart-define-from-file=env/dev.json

# Codegen (drift, freezed, json_serializable)
# NÃO passe --delete-conflicting-outputs: a flag foi REMOVIDA no build_runner
# 2.15 e o comando avisa "These options have been removed and were ignored".
dart run build_runner build
dart run build_runner watch          # durante o desenvolvimento

# Localizações
flutter gen-l10n

# Builds
flutter build apk --debug
flutter build appbundle --release --dart-define-from-file=env/prod.json
```

### Assinatura do Android

A chave de upload **vive fora do repositório**, em
`~/.android-keys/veredas-upload.jks` (PKCS12, RSA 2048, validade 10.000 dias).
Fora e não dentro porque `.gitignore` protege contra o acidente comum, não
contra um `git add -f`; o que não está na árvore não tem como ser commitado.

`android/key.properties` (gitignored, modo 600) aponta para ela. **Sem esse
arquivo o `flutter build appbundle --release` não falha** — ele cai nas debug
keys e produz um AAB que a Play recusa, sem avisar. Depois de qualquer build
de release destinado à loja, confirme quem assinou:

```bash
/usr/lib/jvm/java-17-openjdk-amd64/bin/jarsigner -verify -certs \
  build/app/outputs/bundle/release/app-release.aab | grep "Signed by"
# esperado: CN=Base Missionaria JOCUM Veredas, ...
# se aparecer "Android Debug", o key.properties não foi lido
```

Use o `keytool` do **JDK 17**. O que está no PATH é do GraalVM Java 8 e gera
keystore no formato JKS antigo.

**A permissão `INTERNET` mora no manifesto `main`.** O template do Flutter só
a declara em `debug` e `profile`, onde existe para o hot reload. Se sair do
`main`, o release instala, abre e não alcança o Supabase — e o teste no
emulador não pega, porque ali roda debug. Confira no artefato, não no fonte:

```bash
unzip -p build/app/outputs/bundle/release/app-release.aab \
  base/manifest/AndroidManifest.xml | strings | grep permission.INTERNET
```

**Isto é uma chave de _upload_, não a de assinatura do app.** Com o Play App
Signing (obrigatório para apps novos desde ago/2021), quem guarda a chave de
assinatura é o Google; esta aqui só autentica o envio. Perdê-la é chato — exige
pedir reset ao suporte da Play — mas **não** impede atualizar o app, ao
contrário do que valia no modelo antigo. Ainda assim: faça backup do `.jks` e
da senha (que está no `key.properties`) num gerenciador de senhas.

### Emulador Android

`flutter` está no PATH; **`adb` e `emulator` não**. Eles vivem no SDK do Android:

```bash
export PATH="$HOME/Android/Sdk/platform-tools:$HOME/Android/Sdk/emulator:$PATH"
```

```bash
flutter emulators                        # lista os AVDs (há um: Medium_Phone)
flutter emulators --launch Medium_Phone
flutter devices                          # fica "offline" por ~20s enquanto sobe
flutter run -d emulator-5554 --dart-define-from-file=env/dev.json
```

Sem passar pelo Flutter, direto pelo SDK: `emulator -avd Medium_Phone &`.

**`R` (hot restart) não é confiável para mudança estrutural** — troca do widget
raiz, do tema ou do tipo de um widget. O `flutter run` reporta "Restarted
application" e a tela continua com o código antigo; já custou duas rodadas de
teste em cima de código que já estava corrigido. O sintoma é o app na tela não
bater com o fonte. Nesse caso, reinstale:

```bash
adb shell am force-stop br.com.veredas.app
adb uninstall br.com.veredas.app     # apaga a sessão salva — exige login de novo
flutter run -d emulator-5554 --dart-define-from-file=env/dev.json
```

Hot reload (`r`) continua confiável para mudança de layout e estilo. Dá para
distinguir pelo log: um reload de verdade imprime `compile`/`reload`/`reassemble`
com tempos; um restart que não fez nada só imprime "Restarted application".

**Acentuação não funciona digitando pelo teclado do computador.** O AVD vem
com `hw.keyboard=yes`, e nesse modo o emulador recebe os códigos de tecla
brutos do host e não mostra o teclado do Android. A composição por tecla morta
(`´` + `a` → `á`) é feita pelo IME do host, que o emulador não usa — chega só a
vogal. O sintoma é digitar "Conversão" e salvar "Conversao", o que parece bug
do app e não é: texto acentuado vindo do banco aparece certo, e não há
normalização de string em lugar nenhum do código.

Usuário real não passa por isso — no celular o teclado é o do Android. Para
testar acentuação no emulador, uma das duas:

```bash
# 1) Desligar o teclado de hardware e usar o teclado na tela (long-press na
#    vogal abre as variantes). Exige reiniciar o emulador.
sed -i 's/^hw.keyboard=yes/hw.keyboard=no/' ~/.android/avd/Medium_Phone.avd/config.ini

# 2) Ou copiar o texto acentuado no host e colar no emulador (o clipboard é
#    compartilhado), sem mexer na configuração.
```

`adb shell input text` **também não serve**: descarta não-ASCII.

**Conferir a UI sem depender de descrição** (útil também para o agente):

```bash
adb exec-out screencap -p > /tmp/tela.png   # screenshot
adb shell input tap <x> <y>                 # tela do Medium_Phone: 1080x2400
adb shell input swipe <x1> <y1> <x2> <y2> <ms>
```

`env/dev.json` (gitignored; commitar `env/dev.example.json`):

```json
{
  "SUPABASE_URL": "https://xxxx.supabase.co",
  "SUPABASE_ANON_KEY": "eyJ..."
}
```

> A `anon key` do Supabase é **pública por design** — a proteção dos dados é o
> RLS, não o sigilo da chave. Ainda assim, não a commite: rotacioná-la depois de
> vazar no histórico do git é trabalhoso. A chave `service_role` **nunca** entra
> no app, em nenhuma circunstância.

---

## 4. Riverpod 3 — diferenças em relação ao CalorieMate

O CalorieMate usa **Riverpod 2.5**. Este projeto usa **3.4.x**. Copiar os
providers de lá literalmente **não compila** ou muda de comportamento de forma
silenciosa. Tabela de tradução:

| CalorieMate (Riverpod 2) | Veredas (Riverpod 3) |
|---|---|
| `class X extends FamilyNotifier<S, int>` com `build(int arg)` | `class X extends Notifier<S>` com construtor `X(this.arg)` e `build()` sem parâmetro |
| `FamilyAsyncNotifier` / `FamilyStreamNotifier` | `AsyncNotifier` / `StreamNotifier` (mesma mudança de construtor) |
| `AutoDisposeProvider`, `AutoDisposeNotifier` | `Provider`, `Notifier` — os prefixos `AutoDispose` foram removidos, comportamento idêntico |
| `Ref<T>` genérico, `ProviderRef.state`, `Ref.listenSelf`, `FutureProviderRef.future` | `Ref` sem genérico; use `Notifier.state`, `listenSelf()`, `AsyncNotifier.future` |
| `class X extends Notifier` (sem genérico) | **sempre** `Notifier<void>` / `Notifier<S>` explícito |
| `StateProvider`, `StateNotifierProvider` | legado — `import 'package:flutter_riverpod/legacy.dart'`. **Não use neste projeto.** |
| `ProviderObserver.didAddProvider(provider, value, container)` | `didAddProvider(ProviderObserverContext context, value)` |

**Três mudanças de comportamento que causam bugs difíceis:**

1. **Retry automático.** Providers que falham são reexecutados com backoff
   exponencial. Para chamadas que não devem ser repetidas (ex.: um `POST` de
   escrita), desabilite explicitamente:
   ```dart
   final xProvider = FutureProvider<T>(..., retry: (count, error) => null);
   ```
   Ou globalmente no `ProviderScope(retry: (c, e) => null, ...)`. **Decida
   conscientemente por provider** — retry silencioso em escrita duplica dados.

2. **Providers fora de tela são pausados.** Como o app usa
   `indexedStack` (as 4 tabs ficam vivas), isso normalmente ajuda. Mas um
   `StreamProvider` pausado **não recebe eventos**. Se precisar de um listener
   sempre ativo (ex.: `OutboxWorker`), não o pendure em um widget — inicialize-o
   com `ref.listen` no nível do `app.dart` ou use um `Provider` mantido vivo
   explicitamente.

3. **Todos os providers filtram updates com `==`.** Isso afeta `StreamProvider`.
   Nossos streams do drift emitem `List` nova a cada evento (identidade
   diferente), então notificam normalmente. Mas se você criar modelos com
   `freezed` (que gera `==` por valor) e emitir um objeto igual, a UI **não**
   rebuilda. Isso geralmente é desejável; só saiba que é o comportamento.

4. **Erros vêm embrulhados em `ProviderException`.** Se você usa `try/catch`
   esperando um tipo específico:
   ```dart
   } on ProviderException catch (e) {
     if (e.exception is AppException) { ... }
   }
   ```
   Com `AsyncValue.error` na UI, nada muda: `value.error is AppException`
   continua funcionando.

**Organização dos providers** (padrão do CalorieMate, mantido):

- `providers/infra_providers.dart` — só DI: `supabaseClientProvider`,
  `appDatabaseProvider`, DAOs, repositórios, services. Todos `Provider<T>`.
  São os pontos de `override` nos testes.
- `providers/<feature>_providers.dart` — estado de feature: `StreamProvider`
  sobre o drift, `Notifier` para ações.

---

## 5. Outras armadilhas de versão

### drift + sqlite3

**Não adicione `sqlite3_flutter_libs`.** Está descontinuado (última versão:
`0.6.0+eol`, descrição: *"Not used anymore, update to version 3.x of
package:sqlite3 instead"*). O `sqlite3` 3.x carrega a biblioteca nativa via
*build hooks*.

Setup correto (oficial atual):

```yaml
dependencies:
  drift: ^2.34.3
  drift_flutter: ^0.3.1
  path_provider: ^2.1.6
dev_dependencies:
  drift_dev: ^2.34.5
  build_runner: ^2.16.0
```

```dart
@DriftDatabase(tables: [...], daos: [...])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // Steps reais por versão. NÃO use m.createAll() aqui.
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  static QueryExecutor _open() => driftDatabase(name: 'veredas');
}
```

O CalorieMate usa `onUpgrade: (m, from, to) => m.createAll()`. **Isso está
errado** — `createAll` só cria tabelas inexistentes, então uma mudança de coluna
falha em silêncio e o app quebra em produção. Escreva steps de migration de
verdade desde a v1.

### freezed 3.x

Sintaxe mudou. O padrão do CalorieMate (freezed 2.x) não compila:

```dart
// freezed 3.x — correto
@freezed
abstract class Profile with _$Profile {
  const factory Profile({
    required String id,
    required String fullName,
    @Default(false) bool isApproved,
  }) = _Profile;

  factory Profile.fromJson(Map<String, dynamic> json) => _$ProfileFromJson(json);
}
```

Note `abstract class` (era `class` no 2.x).

### flutter_lints 6.0

Mais rígido que o 4.0 do CalorieMate. Espere avisos novos. **Corrija, não
silencie** — a exceção é `invalid_annotation_target` (ruído do
`freezed`/`json_serializable`), já ignorado no `analysis_options.yaml`.

### go_router 17.x

O router precisa ser um **provider**, não uma variável global como no
CalorieMate, porque o `redirect` depende do estado de autenticação:

```dart
final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authStateProvider);   // observa mudanças de sessão
  return GoRouter(
    initialLocation: '/inicio',
    refreshListenable: ref.watch(routerRefreshProvider),
    redirect: (context, state) { /* guard, ver docs/PLANO.md Fase 3 */ },
    routes: [...],
  );
});
```

Cuidado: recriar o `GoRouter` a cada mudança de auth **descarta o histórico de
navegação**. Prefira um router estável + `refreshListenable` ligado ao stream de
auth, e faça a decisão dentro do `redirect` lendo o container do Riverpod.

---

## 6. Convenções de código

Herdadas do CalorieMate, com correções:

1. **Imports absolutos**: `package:veredas/...` no `lib/`. Em testes, relativo
   para os helpers (`import 'helpers/test_helpers.dart';`).
2. **Um widget de tela por arquivo.** Sub-widgets privados `_Xxx` no fim do
   mesmo arquivo.
3. `ConsumerWidget` quando não há estado local; `ConsumerStatefulWidget` para
   controllers, seleção múltipla e timers. `dispose()` de todo controller e
   `Timer`.
4. `ref.watch(...)` para ler estado; `ref.read(xProvider.notifier)` para ações.
   Nunca `ref.watch` dentro de callback.
5. **Zero strings hardcoded na UI.** Chaves do `.arb` em `snake_case`
   (consistente com o CalorieMate). Use plural ICU:
   `"{n, plural, =1{1 alteração} other{{n} alterações}}"`.
6. **Erros nunca vazam crus para a UI.** Toda exceção de Supabase/drift é
   convertida em `AppException` com um `code` enumerado; a UI escolhe a mensagem
   do l10n a partir do `code`. Este é um erro explícito do CalorieMate
   (`'Error: $e'` hardcoded em inglês dentro do notifier) — não repita.
7. **Repositórios expõem `Stream` do drift para leitura** e `Future` para
   escrita. A UI nunca vê `SupabaseClient` nem DAO.
8. **Toda escrita passa pelo outbox.** Não existe caminho "chama o Supabase
   direto" numa tela — exceções conscientes (login, upload de imagem) devem ser
   comentadas no código explicando por quê.
9. `if (!mounted) return;` após todo `await` que precede `setState`/navegação.
10. Comentários explicam **por quê**, não o quê. Comentário obrigatório em:
    política de conflito, janela de segurança do sync, qualquer `// ignore:`.

---

## 7. Testes

Prioridade (do mais para o menos importante):

1. **Sync e outbox** (`test/sync/`) — a lógica mais complexa e a que mais quebra.
   drift in-memory + `FakeRemoteSource` (implementa `RemoteSource` com dados
   pré-configurados — não mocka a cadeia fluent do supabase_flutter).
   Casos cobertos: pull insere/atualiza/remove; pull idempotente; escrita offline
   entra na fila; fila drena; 403 reverte o cache; 0-linhas reverte o cache;
   backoff exponencial; ordem de drenagem; janela de 2min.
2. **Mapeamento de erros** — `PostgrestException`/`AuthException` → `AppException`.
3. **Helpers puros** — `date_utils` (semana ISO, virada de mês, DST),
   `permissions`.
4. **Widget tests** das telas principais.

**A armadilha que travou o CalorieMate:** 4 suítes de widget test lá estão
desabilitadas com `@Skip` porque `pumpAndSettle` nunca termina com
`StreamProvider` + drift (a stream nunca "assenta"). Solução:

```dart
// NUNCA: await tester.pumpAndSettle();
await tester.pump();
await tester.pump(const Duration(milliseconds: 50));
```

E envolva a tela num `GoRouter` de teste — as telas usam `context.push`, que
lança exceção dentro de um `MaterialApp` simples.

**A segunda armadilha, para tela que lê stream do drift:** termine o teste
desmontando a árvore e pumpando **com duração**:

```dart
await tester.pumpWidget(const SizedBox.shrink());
await tester.pump(const Duration(milliseconds: 10));
```

Cancelar um stream do drift agenda um timer de duração zero
(`StreamQueryStore.markAsClosed`). Sem o desmonte explícito, o `ProviderScope`
só é descartado quando o teste **seguinte** monta a sua árvore, e o timer nasce
depois do último frame: o flutter_test falha com *"A Timer is still pending even
after the widget tree was disposed"* com todas as asserções verdes. E um
`pump()` sem duração não avança o relógio falso, então não consome o timer.
Exemplo em `test/ui/scale_tab_view_test.dart`.

Helpers em `test/helpers/test_helpers.dart`: `createTestDatabase()`,
`FakeRemoteSource`, `makeProfileJson()`, `makeEventJson()`,
`makeAnnouncementJson()`, `makeScaleManagerJson()`, `enqueueOutboxEntry()`,
`makeRlsException()`, `makeSocketException()`.

---

## 8. Segurança — regras não negociáveis

1. **RLS habilitado em toda tabela.** No Supabase, tabela sem RLS é pública para
   a `anon key`.
2. **Nunca** embarcar a chave `service_role` no app.
3. Ocultar um botão na UI **não é** controle de acesso. Toda permissão tem
   policy correspondente no banco (`docs/SCHEMA.md` §6).
4. Funções que consultam `profiles` dentro de policies de `profiles` precisam ser
   `security definer` com `search_path` fixo — senão: recursão infinita de RLS.
5. Usuário comum **não pode** alterar o próprio `role`/`is_approved`. Garantido
   por policy **e** por trigger (`docs/SCHEMA.md` §8).
6. Não logar tokens, sessões ou dados pessoais. Cuidado com `print` de
   `PostgrestException`, que às vezes carrega o payload.
7. Não commitar `env/*.json` (exceto `.example`), keystores (`*.jks`) ou
   `pubspec.lock` com URLs internas.

---

## 9. Git

Um commit por fase concluída, mensagem em português explicando o **porquê**.
Não fazer push sem pedido explícito.

```
Fase 4: cache offline com drift e fila de escrita

O app precisa funcionar na base, onde o sinal é instável. As telas leem do
cache local e o SyncService faz pull incremental por updated_at; escritas vão
para uma outbox drenada quando há conexão.
```

---

## 10. Estado do projeto

Atualize esta seção ao concluir cada fase.

- [x] Fase 0 — Ambiente e esqueleto
- [x] Fase 1 — Backend Supabase (schema + RLS + seeds) — **aplicado** no projeto
      `vwstkxemtkdlsagricsh`. 13 tabelas + view `prayer_feed` + RPCs, RLS ativo
      (leitura anônima devolve vazio; `redeem_invite` nega `anon` com 42501).
      Validado antes com 47 asserções em Postgres local
      (`supabase/local_test/run.sh`). SMTP via Brevo configurado — ver
      `supabase/README.md` §6.7 para o estado de entregabilidade e o plano B.
- [x] Fase 2 — Fundação Flutter (tema, router, 4 tabs)
- [x] Fase 3 — Autenticação, convite e papéis — `AuthService` (interface) +
      `SupabaseAuthService` (signUp com convite, signIn, signOut,
      resetPassword, resendEmailConfirmation, updateProfile), providers de
      auth (`authStateProvider`, `currentProfileProvider`, `authActionsProvider`,
      `isAdminProvider`), guard no router (redirect: sem sessão → /login,
      não aprovado → /aguardando, aprovado em rota de auth → /inicio),
      telas (splash, login, cadastro, aguardando, esqueci senha),
      `flutter_secure_storage` para convite pendente, deep link Android
      (`br.com.veredas.app://login-callback/`). 13 testes de auth.
- [x] Fase 4 — Camada de dados e sincronização ⚠ crítica — schema do cache,
      codegen, `AppException`/`error_mapper`, `SyncEntity`/`SyncService`/
      `OutboxWorker`/`RemoteSource`, DAOs por área, `OutboxHelper`,
      providers de infra, `syncStatusProvider`, `OfflineBanner`,
      `connectivity_plus`. 56 testes (sync, outbox, error_mapper, schema).
      Os 5 aceites do plano + o caso 0-linhas cobertos.
- [x] Fase 5 — Tela Início — aviso fixado, redes sociais, dados da base,
      avisos anteriores. FAB só admin. Editor de avisos implementado
      (`announcement_editor_screen.dart`). Nome do autor denormalizado
      (`authorName` em `AnnouncementRow`, exibido na UI). TODO: lista
      completa de avisos (rota `/avisos`), editor de base_info
      (`BaseDataScreen`).
- [x] Fase 6 — Tela Agenda — abas Eventos (TableCalendar + lista do dia +
      próximos, `cached_network_image` para capas) e Cronograma (grade
      semanal proporcional + lista por dia). FAB só admin. Editores de
      evento e slot implementados com seletor de cor (`color_index`).
      Evento de vários dias marca todos os dias no calendário; dia inteiro
      aceita intervalo; exclusão no editor (só admin).
      TODO: detalhe do evento.
- [x] Fase 7 — Tela Escalas — TabBar dinâmica de scale_types, seletor de
      período (weekly/monthly/adhoc), tabela com slots / lista sem slots,
      destaque "Você" (primaryContainer + Chip), resumo "N× no período".
      FAB só se canEditScale. Editor de atribuição implementado
      (`scale_assignment_editor_screen.dart`), alcançável tocando numa
      atribuição já montada, com exclusão dentro dele. Atribuição em equipe +
      responsável geral e escala de Almoço (ver decisões no fim deste
      arquivo). TODO: duplicar semana, seleção múltipla com exclusão em lote.
- [x] Fase 8 — Mural de Oração — feed com busca por título (debounce 400ms),
      composer inline, PrayerCard (avatar, timeago, "estou orando" toggle
      otimista, badge "Respondido", popup Editar/Excluir/Marcar respondido),
      texto expansível (3 linhas + ver mais). FAB novo pedido. Editor
      implementado (`prayer_editor_screen.dart`). TODO: tela de detalhe,
      paginação.
- [x] Fase 9 — Administração — AdminScreen (menu), MembrosScreen (lista com
      busca, pendentes no topo, popup Aprovar/Revogar/Promover/Rebaixar/
      Remover, proteção auto-rebaixamento), ConvitesScreen (lista + FAB criar
      diálogo com código gerado sem 0/O/1/I, copiar, revogar),
      ResponsaveisScreen (ExpansionTile por scale_type, adicionar/remover),
      EscalasScreen (`/admin/escalas`: criar, renomear, reordenar por arrasto,
      ocultar e excluir escalas + editor `scale_type_editor_screen.dart`).
      Rotas de admin + guard no router (não-admin → /inicio). Todas as 6
      RPCs implementadas (`supabase_admin_service.dart`). TODO: BaseDataScreen.
- [x] Fase 10 — Qualidade, iOS e lançamento — flutter_launcher_icons (logo
      900x900), ProGuard + minify/shrink + signing config via key.properties
      (gitignored), Info.plist (CFBundleLocalizations pt/pt-BR,
      CFBundleURLTypes deep link, NSCameraUsageDescription,
      NSPhotoLibraryUsageDescription), política de privacidade LGPD
      (PRIVACIDADE.md), `flutter analyze` limpo, 77 testes passando
      (71 unit/integração + 6 widget), APK release assinado (66MB).
      Migrado para Cupertino (CupertinoApp.router, CupertinoTabBar, widgets
      iOS). Seletor de cor para eventos/slots. Exclusão de conta
      (RPC `delete_own_account` + proteção último admin). iOS não compila
      no Linux — arquivos configurados, build requer macOS + Xcode.

### Decisões tomadas durante a execução

> Registre aqui toda decisão que divergir do plano, com a justificativa. Isso
> evita que a próxima sessão desfaça o trabalho sem entender o motivo.

#### Fases 0–2 (execução inicial)

**Ambiente**

1. **JDK 17 e Android SDK 36.** O `sdkmanager` não existia (`cmdline-tools`
   ausente) e falhava com o Java 8, que é o padrão do sistema. Instalado
   `cmdline-tools`, licenças aceitas e `platforms;android-36` (exigido pelo
   Flutter 3.44). Rodar sempre com:
   ```bash
   export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
   export ANDROID_HOME="$HOME/Android/Sdk"
   export PATH="$HOME/development/flutter/bin:$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"
   ```
2. **O emulador precisa de `setsid`.** Lançado como filho do shell da sessão,
   ele morre quando o comando é reaped, e o `flutter run` reporta o sintoma
   enganoso `Lost connection to device`. Use:
   ```bash
   setsid nohup $ANDROID_HOME/emulator/emulator -avd Medium_Phone \
     > /tmp/emu.log 2>&1 < /dev/null & disown
   ```
3. **`adb shell input tap` usa pixels físicos** (1080×2400 no AVD), não as
   coordenadas da imagem escalada exibida no visualizador.

**Correções no docs/PLANO.md §3 — as versões declaradas não resolvem**

O plano afirma que as versões foram "todas verificadas contra Flutter 3.44.8".
Duas não são resolvíveis; ambas foram corrigidas no `pubspec.yaml`, com o motivo
comentado no próprio arquivo:

| Plano | Aplicado | Por quê |
|---|---|---|
| `build_runner: ^2.16.0` | `^2.14.0` (resolve 2.15.1) | `build_runner >= 2.15.2` exige `meta ^1.18.3`; o `flutter_test` do SDK 3.44.8 fixa `meta 1.18.0` → *version solving failed* |
| `drift_dev: ^2.34.5` | `^2.34.0` | `drift_dev >= 2.34.1` exige `analyzer ^13`; o `freezed` estável (3.2.5) exige `analyzer <11`. **Não há sobreposição** — só as prereleases `freezed 4.0.0-dev.*` suportam analyzer 13. `drift_dev 2.34.0` aceita `analyzer >=10 <13`, que sobrepõe |

Consequência: o projeto roda com `analyzer 10.2.0`, `drift 2.34.3` (runtime) e
`drift_dev 2.34.0` (gerador). **Revalide o codegen na Fase 4** — é a primeira
vez que o gerador do drift roda de verdade. Se der conflito, a saída é abandonar
o `freezed` (escrever os modelos à mão) e subir o `drift_dev`, não usar
prerelease.

**Correção no docs/SCHEMA.md §3 — `manages_scale` na ordem errada**

O `docs/SCHEMA.md` diz que "o corpo de uma função `language sql` só é resolvido na
execução, então criar a função antes da tabela funciona". **Isso é falso** com
`check_function_bodies = on`, que é o padrão no Supabase: o corpo é validado já
no `CREATE FUNCTION`, e `manages_scale` referencia `public.scale_managers`
(criada no §4). Aplicar na ordem do documento falha com
`relation "public.scale_managers" does not exist`.

Extraída para `migrations/20260803000450_manages_scale.sql`, aplicada **depois**
das tabelas de domínio. As outras funções (`is_approved`, `is_admin`,
`norm_text`) não dependem de tabela de domínio e ficaram na `0300`.

**Correção no docs/PLANO.md — `minSdk`**

O plano manda fixar `minSdk = 23`. O default do Flutter 3.44 é **24**, então 23
seria um downgrade, e o `flutter build` reescreve o `build.gradle.kts` na
migração do Gradle, revertendo o valor fixado. Mantido
`minSdk = flutter.minSdkVersion`, que já satisfaz o `flutter_secure_storage`.

**Depreciação no supabase_flutter 2.16**

`Supabase.initialize(anonKey:)` foi depreciado em favor de `publishableKey:`.
O `docs/PLANO.md` e este arquivo citam o nome antigo. A variável de ambiente segue
`SUPABASE_ANON_KEY` (o parâmetro aceita as duas chaves do painel).

**Melhorias no schema (não pedidas, mas necessárias)**

1. **`social_links` ganhou índice único em `platform`.** Sem ele o
   `on conflict do nothing` do `seed.sql` nunca dispara e reaplicar o seed
   duplica os ícones da tela Início.
2. **`weekly_slots` usa guard `where not exists` no seed**, em vez de
   `on conflict` — a tabela não tem chave natural (a base pode ter dois eventos
   no mesmo horário), então nenhum `on conflict` funcionaria.
3. **Índice trigram adicional em `norm_text(body)`.** A `search_prayers` busca
   no título *e* no corpo; sem esse índice a segunda metade do `OR` faz scan
   sequencial.

**Desvio de convenção: l10n sem `!`**

`l10n.yaml` usa `nullable-getter: false`, então o correto é
`AppLocalizations.of(context)` — **sem** o `!` que o `docs/TELAS.md` §"Padrões
obrigatórios" prescreve. Com o getter não-nulo, o `!` seria erro de lint
(`unnecessary_non_null_assertion`). Escolhido o getter não-nulo por eliminar
uma classe inteira de null-assertions ruidosas.

**Tema: paleta da logo (decisão do solicitante)**

O mockup usava o roxo padrão do construtor no-code. A logo real da base (o
vitral) definiu a paleta, com a orientação do solicitante de "branco e preto com
detalhes nas cores":

- **Cor de marca (`tint`)**: marrom `#62503F` (traço e tipografia da logo).
- **Fundo no tema claro**: creme `#F5EEE6` (fundo do vitral), em vez de
  branco puro.
- **5 acentos do vitral** em `AppColors`: verde-água, azul, laranja, amarelo,
  roxo. São **semânticos**, não decorativos: identificam tipo de escala e
  categoria de evento.
- `AppColors.accentFor(key)` deriva a cor de uma **string** (o `slug` do tipo de
  escala), não do índice da lista — assim inserir um tipo novo no meio não muda
  a cor dos existentes, e não é preciso uma coluna de cor no banco. A soma de
  code units é usada em vez de `hashCode` porque o `hashCode` do Dart **não é
  estável entre execuções**.
- Cada acento tem par `accent` (vivo, para bordas/ícones) e `accentContainer`
  (dessaturado, para fundos). **Nunca escreva texto sobre `accent` puro**: o
  amarelo e o laranja da logo reprovam em WCAG AA como fundo.

**A UI é Cupertino, não Material (decisão do solicitante)**

O app foi construído em Material e depois migrado inteiro para Cupertino, a
pedido do solicitante, buscando estética Apple e aderência ao iOS. Fica
registrado o custo aceito: no Android, Cupertino **viola** as convenções da
plataforma (sem ripple, gesto de voltar diferente, tipografia fora do sistema),
e a maioria dos usuários da base está no Android.

Regras ao escrever UI nova:

1. **Importe `package:flutter/cupertino.dart`**, nunca `material.dart`.
2. **Cores vêm de `context.colors`** (`AppTheme` → `AppColors`), nunca de
   `Theme.of(context).colorScheme`. Os nomes seguem o iOS: `label`,
   `secondaryLabel`, `separator`, `groupedBackground`, `surface`, `fill`,
   `tint`, `destructive`.
3. **Texto vem de `AppTypography`** (escala do HIG: `body` 17, `footnote` 13,
   `caption2` 11), nunca de `textTheme`. Os estilos não trazem cor — aplique
   `.copyWith(color: ...)`.
4. **`fontFamily` é sempre nulo** nos estilos. O `Text` faz merge sobre o
   `DefaultTextStyle`, então a família vem do `CupertinoTheme` (SF Pro no iOS,
   fonte do sistema no Android). Fixar a família quebra esse fallback.
5. **Não existe `FloatingActionButton` no iOS.** Ações de criação vão no
   `trailing` da `CupertinoNavigationBar`.
6. **Não existe `SnackBar`.** Use `showAppToast(context, msg, isError: bool)`.
   Se a mensagem exige decisão do usuário, use `CupertinoAlertDialog` — um
   toast some em 3 segundos.
7. **Menus de contexto** são `showCupertinoModalPopup` + `CupertinoActionSheet`,
   com `isDestructiveAction` nas exclusões. Faça a folha **retornar** o valor e
   trate depois do `await`, senão o callback roda com o contexto já desmontado.
8. **Seleção de valor** é `CupertinoPicker` (roda) em modal popup, não menu
   suspenso. Aplique o valor só na confirmação: a roda dispara `onChanged` a
   cada giro, e sem botão um toque acidental muda o dado sem como desistir.
9. **Formulários** usam `CupertinoFormSection.insetGrouped` +
   `CupertinoTextFormFieldRow`. `Form`/`FormState` continuam valendo — vivem em
   `widgets.dart`, não no Material. Referência: `ui/screens/auth/login_screen.dart`.
10. **Botão de salvar** de editor fica no `trailing` da navigation bar, não no
    fim do formulário.

**O que ainda é Material, e por quê**

- `table_calendar` usa `InkWell` internamente e não tem equivalente Cupertino.
  Ele é o único motivo de `core/theme/material_compat.dart` existir: uma ilha
  de `Material` + `Theme` envolvendo **só** o calendário em `events_tab.dart`.
  Não reintroduza esse wrapper globalmente.
- `TabController`/`TabBarView` em `agenda_screen.dart` e `scales_screen.dart`,
  importados com `show` restrito. São mecânica de paginação e não exigem
  ancestral `Material`. Trocá-los por `PageController` é possível, mas mexe no
  estado das telas.
- `GlobalMaterialLocalizations` segue registrado por causa do `table_calendar`.

**Armadilhas encontradas na migração**

- `TimeOfDay` é do Material e `TimeOfDay.format(context)` exige
  `MaterialLocalizations`. Onde havia horário, o estado passou a `int` de
  minutos — que é o formato que o DAO já usava.
- Widgets sem equivalente que tiveram de ser reconstruídos à mão:
  `ExpansionTile`, `MaterialBanner`, `CircleAvatar`, `Chip`, `Divider`,
  `SelectableText`, `Tooltip` (virou `Semantics`), `FilledButton.icon`
  (o `CupertinoButton` não tem slot de ícone).
- Ao passar `BuildContext` como parâmetro para um método de `State`, ele
  **sombreia** o `State.context` e o `if (!mounted)` deixa de proteger o
  contexto realmente usado — o lint `use_build_context_synchronously` acusa.
  Em `State`, não receba `context` por parâmetro.

#### Fase 1 — validação local e bugs encontrados

Antes de aplicar no Supabase, todas as migrations, o seed e as policies foram
rodados num Postgres 17 local (Docker) com 47 asserções de RLS. Harness em
`supabase/local_test/`, reexecutável com `./supabase/local_test/run.sh`.
**Rode isso depois de qualquer alteração em `supabase/migrations/`.**

Três bugs reais foram encontrados e corrigidos:

1. **`manages_scale` na ordem errada** (já descrito acima) — confirmado
   empiricamente, não era teoria.
2. **Era impossível criar o primeiro admin.** O trigger
   `protect_profile_privileges` avalia `is_admin()`, que é `false` no SQL Editor
   porque ali `auth.uid()` é `NULL`. O `UPDATE` de promoção que o `docs/SCHEMA.md` §9
   e o `supabase/README.md` passo 7 mandam rodar morria com
   `FORBIDDEN_PRIVILEGE_CHANGE`, **sem nenhuma saída** — a base não poderia ser
   bootstrapada. Corrigido com uma exceção para `auth.uid() is null` na
   migration `0800`, documentada no próprio arquivo. Não abre brecha: as policies
   de `profiles` são `to authenticated` e exigem `id = auth.uid()`, então uma
   requisição anônima não alcança linha alguma.
3. **`authenticated` sem `USAGE` no schema `extensions`.** `norm_text()` não pode
   ser `security definer` (precisa ser `immutable` para servir de índice de
   expressão), então executa com os privilégios de quem chama. A busca do mural
   falhava com `permission denied for schema extensions`. Grant explícito
   adicionado na migration `0100`.

#### Fase 4 — codegen validado, e duas armadilhas

**O codegen funciona** com as versões rebaixadas (`freezed 3.2.5` +
`drift_dev 2.34.0` + `json_serializable` + `analyzer 10.2.0`). O risco levantado
acima está resolvido: não é preciso abandonar o `freezed` nem usar prerelease.

1. **`flutter analyze` NÃO detecta erros de codegen.** O `analysis_options.yaml`
   exclui `**/*.g.dart` e `**/*.freezed.dart`, então o analyzer nunca olha o
   código gerado. Um caso real: o `app_database.g.dart` não resolvia `AppRole` e
   `StringListConverter`, o `analyze` dizia "No issues found!", e só o
   `flutter test` acusou.
   **Depois de mexer em tabelas/modelos, rode `flutter test`, não só `analyze`.**

2. **O arquivo dono do `part` precisa importar tudo que o gerado usa.** Um part
   file herda os imports da biblioteca dona. O `app_database.dart` importa
   `converters.dart` e `app_role.dart` **apesar de não os usar diretamente** —
   são para o `.g.dart`. Não remova esses imports "não usados".

3. **Sufixo `Row` nos `@DataClassName`.** O drift geraria `Profile` para a tabela
   `ProfileRows`, colidindo com o modelo de domínio `Profile` do freezed. Todas
   as tabelas de cache usam `@DataClassName('XxxRow')`.

#### Fase 4 — sync, outbox e RemoteSource (implementação)

**`prayer_feed` usa `fullReplace`, não `incremental`.** A view não expõe
`deleted_at` — ela filtra `where p.deleted_at is null` internamente. Um post
apagado simplesmente desaparece dos resultados, e o incremental jamais
perceberia. Com ~dezenas de posts numa base de 30 obreiros, baixar a view
inteira a cada sync é trivial. `prayer_comments` (tabela, tem `deleted_at`)
continua incremental.

**`RemoteSource` como interface abstrata.** O `docs/PLANO.md §2.4` prevê que "cada
fonte remota fica atrás de uma interface abstrata". O `SyncService` e o
`OutboxWorker` dependem de `RemoteSource`, não de `SupabaseClient` diretamente.
Isto torna os testes viáveis sem mockar a cadeia fluent do supabase_flutter
(`PostgrestQueryBuilder` → `PostgrestFilterBuilder` → `PostgrestTransformBuilder`
...), que é frágil e acoplada a tipos internos do SDK. A implementação Supabase
(`SupabaseRemoteSource`) é uma camada fina; nos testes, `FakeRemoteSource`
retorna dados pré-configurados.

**O `previousRow` da outbox é drift JSON, não Supabase JSON.** O snapshot da
linha antes da mudança é gerado por `row.toJson()` (formato drift: camelCase,
DateTime como int ms). O `restore` usa `RowClass.fromJson(driftJson)`, que é o
inverso exato. O payload enviado ao servidor (`outbox.payload`) é Supabase JSON
(snake_case, ISO strings) — construído pelo repositório no momento da escrita.

**PK composta na outbox.** `scale_managers` tem PK `(scale_type_id, user_id)`.
O `rowId` na outbox é codificado como `"scaleTypeId|userId"` (funções
`encodeCompositeId`/`decodeCompositeId` em `sync_entity.dart`). O `remove` da
entidade decodifica o pipe. As outras entidades usam o UUID direto.

**Drift devolve `DateTime` em hora local.** O `DateTimeColumn` do drift armazena
como Unix timestamp e lê de volta com `isUtc: false`. Testes que comparam
`lastSyncedAt` precisam usar `.toUtc()` — senão falham em fuso != UTC.

**`count().watchSingle()`, não `count().watch()`.** `count().watch()` retorna
`Stream<List<int>>` (lista com um elemento); `watchSingle()` retorna
`Stream<int>`. Confundir os dois é erro de tipo silencioso.

**Ordem do drain: para no primeiro erro retentável.** Rede/timeout/5xx
provavelmente afeta todas as entradas seguintes — tentar todas é desperdício.
Erros permanentes (403/conflito/0-linhas) são independentes: o drain continua
para a próxima entrada.

**Backoff capado em 256s (~4min).** `2^attempts` segundos, limitado a
`attempts <= 8`. Crescimento: 1s, 2s, 4s, 8s, 16s, 32s, 64s, 128s, 256s.

#### Fase 4 — DAOs, providers e OfflineBanner (implementação)

**DAOs sem `@DriftAccessor`.** O CalorieMate usa `@DriftAccessor` (gera
`*.dao.g.dart` e exige registrar os DAOs no `@DriftDatabase`). O Veredas usa
classes simples que recebem `AppDatabase` no construtor — menos codegen, menos
arquivos gerados, e o `AppDatabase` já expõe todas as tabelas via getters.
O padrão é igual em funcionalidade: `Stream` para leitura, `Future` para
escrita local.

**`OutboxHelper` centraliza a transação otimista+outbox.** Toda escrita do
app passa por `OutboxHelper.write()` (ou os atalhos `insert`/`update`/`delete`),
que numa única transação drift: (1) captura o snapshot anterior, (2) aplica a
mudança no cache, (3) insere na outbox. Sem isto, um crash entre (2) e (3)
deixaria a UI mostrando um dado que nunca chegaria ao servidor.

**`Riverpod 3`: `.value` é nullable, não `.valueOrNull`.** O `AsyncValue<T>`
do Riverpod 3 tem `.value` que retorna `T?` (null se loading/error). O
`valueOrNull` não existe — é uma extensão do Riverpod 2 que foi incorporada
como getter nativo com nome diferente.

**`syncStatusProvider` é um `Notifier`, não um `StreamProvider`.** O estado de
sync é derivado de múltiplas fontes (conectividade, outbox pendente, erro do
último pull), e `pullAll()` é uma ação imperativa. Um `StreamProvider` não
permite expor métodos. O `Notifier` observa os providers de infra via
`ref.watch` no `build()` e expõe `pullAll()` e `clearError()`.

**O sync precisa de um gatilho, e ele mora no `app.dart`.** A Fase 4 entregou
`SyncService` e `OutboxWorker` testados, mas **nada chamava `pullAll()`** — o
app parecia funcionar e não sincronizava. Alterações feitas no servidor nunca
chegavam ao cache, e escritas ficavam presas na outbox para sempre, porque
`drain()` só roda dentro de `pullAll()`.

O `SyncCoordinator` (`ui/widgets/sync_coordinator.dart`) fecha esse buraco.
Fica acima do router, no `builder` do `CupertinoApp` — **não mova para dentro
de uma tela**: o Riverpod 3 pausa providers fora de tela, e o gatilho pararia
de disparar ao trocar de aba. Sincroniza na abertura, no login, ao voltar a
conexão e ao retornar do segundo plano. O portão é a **sessão**, não a
aprovação: gatear por `isApproved` daria impasse, já que o perfil só entra no
cache pelo próprio pull.

**`OfflineBanner` é uma faixa persistente, não um toast.** O banner precisa
ficar visível enquanto durar o estado e não ser descartável — um toast some
sozinho e o usuário perde a informação de que está offline. Era um
`MaterialBanner`; na migração para Cupertino virou uma faixa fina própria
(`MaterialBanner` não tem equivalente).

#### Fase 3 — Auth, convite e guard (implementação)

**`AuthState` colide com o gotrue.** O `supabase_flutter` exporta `AuthState`
do gotrue. O nosso `AuthState` (em `auth_service.dart`) tem o mesmo nome.
Solução: `import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState`
nos arquivos que usam o nosso tipo.

**`updateProfile` é escrita direta, não passa pela outbox.** O profile é do
próprio usuário, o conflito é impossível (só ele edita seus dados), e cachear
otimistamente o próprio profile adiciona complexidade sem benefício. A exceção
ao "toda escrita passa pelo outbox" (§6 regra 8) está comentada no código.

**Guard via `refreshListenable`, não `ref.watch`.** O `routerProvider` usa um
`_RouterRefreshNotifier` (ChangeNotifier) que é disparado por `ref.listen` no
`authStateProvider` e `currentProfileProvider`. Recriar o GoRouter a cada
mudança de auth descartaria o histórico de navegação. O `redirect` lê o estado
via `ref.read` — decisão pontual, não reativa.

**Perfil null mesmo com sessão.** O `currentProfileProvider` pode emitir null
mesmo com sessão ativa — o perfil ainda não foi sincronizado do Supabase. O
redirect trata null como "não aprovado" → manda para `/aguardando`, que tem
"verificar novamente" (força um pull). Isto é aceitável: a aprovação é feita
por um admin, e o usuário descobre no próximo sync.

**`FakeAuthService.authStateChanges` usa `onListen` para emitir o estado
inicial.** O `StreamProvider` precisa receber pelo menos um evento para
resolver. O `async*` generator faz o primeiro `yield` em microtask, e o
`StreamProvider.future` pode ficar pendurado. Solução: `StreamController.broadcast`
com `onListen: () => sc.add(_currentState)` — emite síncrono na inscrição.

**`StreamProvider.future` retorna o valor atual, não a próxima emissão.** Nos
testes, usar `.future` após uma ação não espera a próxima emissão — retorna o
valor atual. Solução: helper `waitForAuthState` que usa `container.listen` +
`Completer` para aguardar uma emissão que satisfaz um predicado.

#### ⚠ Semântica do RLS que afeta o OutboxWorker (ler antes da Fase 4)

Descoberta ao escrever as asserções, e **não** está no `docs/PLANO.md`:

| Operação | RLS reprova em | Resultado |
|---|---|---|
| `INSERT` | `WITH CHECK` | **erro** `42501 insufficient_privilege` |
| `UPDATE` que gera linha proibida | `WITH CHECK` | **erro** `42501` |
| `UPDATE` / `DELETE` de linha invisível | `USING` | **0 linhas, SEM erro** |

O `docs/PLANO.md` §2.5 diz que o `OutboxWorker` deve tratar "`PostgrestException`
401/403 (RLS negou) → remove da fila, reverte o cache". **Isso cobre só metade
dos casos.** Um `UPDATE` ou `DELETE` negado pelo `USING` volta **HTTP 200 com
lista vazia**, não 403. Se o worker tratar 200 como sucesso, ele marca o item
como enviado, o cache local mantém a escrita otimista e o dispositivo divergirá
do servidor **para sempre**, sem nenhum erro visível.

Concretamente, na Fase 4 o `OutboxWorker` precisa:

1. usar `.select()` nos `update`/`delete` do Supabase, para que a resposta traga
   as linhas afetadas;
2. tratar **0 linhas afetadas** em `update`/`delete` como **negação**, com o
   mesmo caminho de um 403: remover da fila, reverter o cache e forçar
   `pull(entity)` daquela entidade;
3. cobrir isso com teste — é o caso que não dá erro e por isso passa batido.

Cuidado com um falso positivo: 0 linhas também acontece legitimamente quando a
linha foi **removida por outra pessoa** (soft delete) desde a escrita local.
O tratamento é o mesmo (reverter e sincronizar), então não é preciso
distinguir — mas a mensagem ao usuário deve ser "este item foi alterado ou
removido", não "você não tem permissão".

**Pendências que dependem do solicitante**

- ~~Salvar a logo~~ — feito: `assets/images/logo.jpg`. As cores do tema foram
  amostradas dele. ~~Falta gerar o launcher icon~~ — feito:
  `flutter_launcher_icons` configurado e ícones gerados em
  `android/app/src/main/res/mipmap-*/ic_launcher.png`.
- ~~Aplicar as migrations no projeto Supabase~~ — feito. Todas as migrations
  aplicadas no projeto `vwstkxemtkdlsagricsh`. RLS ativo, seeds carregados.
- ~~Dados de `base_info` e `social_links`~~ — feito pelo solicitante no
  `seed.sql`.
- **Cronograma semanal**: o seed tem um MODELO de 40 slots baseado no ritmo
  típico de uma base JOCUM, por decisão do solicitante ("criar um cronograma
  padrão e depois os adms editam pelo app"). **Não é o cronograma real da base**
  — os admins ajustam pela tela `/cronograma/:id/editar` na Fase 6.

---

#### Escalas em equipe e escala de Almoço (pós-Fase 10)

Pedido da base: uma atribuição pode ter várias pessoas (um grupo de quatro no
almoço) e, opcionalmente, um responsável geral sobre elas.

1. **A equipe é um par de arrays na linha, não uma tabela filha.** Uma tabela
   `scale_assignment_members` é o modelo relacional certo e o errado aqui: uma
   equipe de quatro viraria cinco entradas na outbox para uma única edição
   feita offline, e o rollback do cache otimista — hoje "restaura a linha
   anterior" — precisaria virar transação distribuída no cliente. Com arrays a
   escrita continua atômica e o motor de sync não muda. O preço é não ter FK
   por elemento (o Postgres não faz): quem cobre é `delete_own_account()`.
2. **`assignee_id`/`assignee_name` passaram a significar "responsável geral"**,
   sem renomear as colunas. O app instalado lê `assignee_name` para desenhar a
   escala; uma coluna que some derruba esses aparelhos até todo mundo
   atualizar. Com o nome preservado, a versão antiga mostra o responsável geral
   e degrada em vez de quebrar.
3. **Apagar a conta não apaga mais a escala dos outros.** Antes, uma atribuição
   era de uma pessoa só e o tombstone da linha inteira era correto. Agora só
   quem era a única pessoa escalada derruba a linha; nos grupos, o uid sai de
   `member_ids` e o resto do grupo continua escalado.
4. **Excluir a própria conta nunca funcionou para obreiro comum.** Descoberto
   ao cobrir `delete_own_account()` no harness de RLS (§11 das asserções): o
   RPC termina zerando `is_approved` no próprio perfil, e o trigger
   `protect_profile_privileges` recusa isso para quem não é admin —
   `FORBIDDEN_PRIVILEGE_CHANGE`. Ou seja, o caminho que a Google Play exige
   só funcionava para admin. Corrigido na migration `20260917000200` com o
   mesmo mecanismo de `redeem_invite`: uma flag local à transação
   (`app.deleting_own_account`) que o trigger reconhece.
5. **Bug encontrado pelo teste (e corrigido só em `ScalesRepository`).**
   `into(tabela).insertOnConflictUpdate(linha)` monta os valores com
   `toColumns(nullToAbsent: true)`, que **omite as colunas nulas**. Num update
   isso significa que limpar um campo não limpa nada no cache — o valor antigo
   fica até o próximo pull. A edição de atribuição passou a usar
   `update(...).write(Companion(...))`, em que `Value(null)` grava null.
   **O mesmo padrão está em `agenda_repository`, `home_repository`,
   `prayer_repository` e `documents_repository`** e continua lá: não foi tocado
   por estar fora do escopo do pedido.

#### Convite sem limite de usos e edição do convite (pós-Fase 10)

A base passou de ~20 para ~30 obreiros. O convite `VEREDAS2026` nasceu no seed
com `max_uses = 20` ("um por obreiro") e o 21º cadastro bateria em
`INVITE_EXHAUSTED` — sem saída pelo app: não havia RPC de edição de convite, e
criar outro com o mesmo código esbarra no índice único em `upper(code)`.

1. **`max_uses` null = sem limite**, em vez de um número grande. Um teto alto
   é o mesmo bug adiado, e some da tela: ninguém lembra que existe até alguém
   bater nele. O CHECK `max_uses > 0` não precisou mudar — em SQL um CHECK só
   reprova quando a expressão é FALSE, e `null > 0` é NULL. Quem checa
   esgotamento (`redeem_invite`) passou a testar `max_uses is not null` antes.
2. **`update_invite` substitui todos os campos, não faz patch.** Null em
   `p_max_uses`/`p_expires_at`/`p_note` GRAVA null. Um patch parcial precisaria
   de um sentinela por campo para separar "não mexer" de "limpar", e é
   exatamente essa ambiguidade que já mordeu o cache antes (o
   `nullToAbsent` do `insertOnConflictUpdate`). A tela abre o formulário
   preenchido e devolve o estado inteiro, então não existe campo "não mexido".
3. **Trocar o código é a forma de rotacionar o convite.** Com ~30 pessoas, um
   código que circula por um ano vaza; revogar e criar outro funciona, mas
   perde o histórico de usos e não permite voltar a um código conhecido. Como
   o índice único não deixa duas linhas com o mesmo código (nem se a antiga
   estiver revogada), editar o código in loco era a peça que faltava.
4. **O mesmo bug do `nullToAbsent`, agora no pull.** `_upsertInvite` usava
   `insertOnConflictUpdate(InviteRow(...))`, que monta os valores com
   `toColumns(nullToAbsent: true)` e **omite as colunas nulas**. O admin tirar
   o teto no servidor não limparia o teto no cache de quem já tinha o convite
   sincronizado — a tela seguiria dizendo "Esgotado" para sempre. Trocado por
   `InviteRowsCompanion` com `Value(...)` explícito em cada coluna, onde
   `Value(null)` grava null. Coberto por teste (`test/sync/invites_test.dart`).
   **Os outros `_upsertX` de `sync_entity.dart` continuam com o padrão antigo**
   e têm o mesmo defeito para qualquer coluna nula — não foram tocados por
   estarem fora do escopo do pedido.
5. **Cache: schemaVersion 5 → 6.** O SQLite não afrouxa um NOT NULL com ALTER
   TABLE, então a v6 usa `m.alterTable(TableMigration(inviteRows))`, que recria
   a tabela e copia as linhas. Nenhum valor muda de significado: quem tinha
   teto continua com ele.
6. **Segurança: um convite ilimitado e sem validade é uma porta aberta.**
   `redeem_invite` já aprova o perfil (`is_approved = true`), então quem souber
   o código entra sem passar por um admin — é assim desde a Fase 3, mas o teto
   de 20 limitava o estrago. Quem passa a limitar é a rotação: trocar o código
   pela tela de Convites invalida o antigo na hora. Se a base preferir a porta
   fechada, o caminho é pôr `expires_at` ou um teto de volta no mesmo
   formulário — nada disso saiu.

#### Excluir aviso arrastando para a esquerda (pós-Fase 10)

A exclusão de aviso só existia no aviso **fixado**, pelo menu de reticências.
Os avisos da lista "Avisos anteriores" não tinham como sair pelo app.

1. **`Dismissible` puro, sem dependência nova.** `flutter_slidable` daria o
   botão revelado que o iOS mostra de verdade, mas o `Dismissible` já vem no
   `package:flutter/widgets.dart` (não é Material, então não fere a regra da
   UI Cupertino) e entrega o mesmo gesto. `direction: endToStart` apenas: o
   sentido oposto é o gesto de voltar do iOS e a borda esquerda é dele.
2. **`confirmDismiss` devolve `false` mesmo quando exclui.** Devolver `true`
   faria o `Dismissible` tirar a célula da árvore por conta própria, mas a
   lista vem de um `StreamProvider` sobre o drift: enquanto o stream não
   emitisse, o item continuaria montado e o Flutter lançaria *"A dismissed
   Dismissible widget is still part of the tree"*. Com `false`, quem tira a
   célula é a emissão do stream — que chega junto, porque a escrita no cache é
   síncrona (a viagem ao servidor fica com a outbox). **Não "conserte" para
   `true`**; há teste cobrindo (`test/ui/home_announcement_swipe_test.dart`).
3. **O cartão da lista ganhou `clipBehavior: Clip.antiAlias`.** A faixa
   vermelha é um retângulo cheio e vazava por cima dos cantos arredondados na
   primeira e na última célula.
4. **O aviso fixado não ganhou o gesto.** É faixa de destaque, não célula de
   lista — arrastar ali moveria o banner inteiro. Continua com o menu.
5. **A janela padrão do `flutter_test` (800x600) não serve para a tela
   Início.** A seção de avisos cai fora da viewport e o que está fora não
   recebe arrasto (o finder acha o widget, o `drag` avisa "would not hit test"
   e o teste falha sem dizer por quê). O teste fixa `tester.view.physicalSize`
   em 1080x2400 com `devicePixelRatio = 1`, e desfaz com
   `addTearDown(tester.view.reset)`.

#### Administração das escalas pelo app (pós-Fase 10)

Pedido: o admin quer criar, renomear, reordenar e remover escalas sem depender
do SQL Editor.

1. **Escrita pela outbox, e não por RPC.** As outras ações de admin (aprovar,
   convidar, nomear responsável) chamam RPC e esperam o próximo pull. Aqui isso
   seria visível demais: `scale_types` alimenta a barra de abas da tela
   Escalas, que sai do mesmo cache drift — criar uma escala e não ver nada
   acontecer é o tipo de coisa que faz a pessoa tocar de novo. Pela outbox a
   linha aparece na hora, funciona sem sinal e o 403 reverte. Quem garante a
   permissão continua sendo a policy `scale_types_admin_write`, coberta por
   asserção no harness (§3 das asserções).
2. **O `slug` não está no formulário.** É a chave estável do tipo: derivado do
   nome na criação (sem acento, com sufixo numérico em caso de colisão, para a
   duplicata não estourar só depois da viagem ao servidor) e imutável depois.
   Renomear é troca de rótulo, não de identidade.
3. **Excluir é soft delete; ocultar é `is_active = false`.** As duas coisas
   existem porque significam coisas diferentes: a escala que acabou some, a que
   está fora de época volta. O diálogo de exclusão aponta a alternativa.
4. **A tela Escalas passou a guardar a aba aberta por id**, não por posição.
   Com a ordem editável, o índice deixou de ser identidade: uma reordenação
   chegando pelo sync trocaria a escala embaixo do dedo de quem está olhando.

#### Faixa de "aguardando envio" removida, e o envio que não acontecia (pós-Fase 10)

Pedido do solicitante: a faixa no topo da tela confunde o usuário. Ao olhar o
caso, apareceu um problema atrás dele.

1. **`drain()` só rodava na abertura, no login, na volta da conexão e no
   resume.** Salvar algo com internet funcionando não disparava nada: a linha
   entrava na outbox e ficava lá até o app ir para o segundo plano e voltar. A
   faixa "1 alteração aguardando envio" não era o bug — era o único sintoma
   visível dele. `SyncCoordinator` ganhou um quinto gatilho: a transição de
   outbox **vazia para não vazia**. Só a transição, porque a stream reemite a
   cada mudança na tabela e um ciclo por reemissão seria um ciclo por entrada.
2. **`pullAll()` descartava pedido concorrente, e isso prendia escritas.** O
   guard era `if (_isSyncing) return`. Uma escrita que entrasse na fila depois
   de o `drain()` daquele ciclo já ter lido as entradas ficava presa: a fila
   nunca voltava de vazia para cheia, então o gatilho novo também não
   dispararia de novo. Agora o pedido é anotado em `_syncRequested` e o ciclo
   se repete. Sem o gatilho concorrente não há loop — só um `pullAll()` externo
   levanta a flag, e entradas em backoff não a levantam.
3. **A faixa de pendentes saiu; a de "sem conexão" e a de erro ficaram.**
   Offline é informação que o usuário precisa (na base o sinal cai, e sem o
   aviso a pessoa lê dado velho achando que é o atual); "aguardando envio"
   expõe a outbox, que é detalhe de implementação. Com o gatilho do item 1 o
   estado de pendente vira questão de milissegundos.
4. **`error` passou a vir antes de `hasPending` em `SyncStatus`.** Enquanto a
   faixa de pendentes existia, a ordem inversa fazia sentido — "aguardando
   envio" já avisava que algo não subiu. Com ela removida, `syncing` na frente
   engoliria o aviso de falha exatamente no caso em que ele importa: a entrada
   que falhou continua na fila, `hasPending` fica `true`, e o banner de erro
   com "tentar de novo" nunca apareceria. `offline` continua na frente de tudo.
5. **A derivação do estado virou um método só** (`_derive`). Havia duas cópias
   da regra, no `build()` e no `finally` do `pullAll()`, e elas já divergiam.
6. **`offline_pending_changes` continua no `.arb`.** A chave ficou sem uso, de
   propósito: se a base pedir a faixa de volta (ou um indicador discreto), o
   plural ICU já está escrito e traduzido.
7. Coberto por `test/sync/sync_status_test.dart` (5 testes). Os dois casos
   centrais — erro visível com a fila cheia, e escrita que entra no meio do
   ciclo — foram confirmados falhando no código antigo antes de ficarem verdes.

#### Editar e excluir uma atribuição já montada (pós-Fase 10)

Pedido: depois de salvar uma escala, não havia como editar nem remover o
registro.

1. **Não faltava nada na camada de dados.** A rota `escalaAtribuicaoEditar`, o
   modo de edição do `ScaleAssignmentEditorScreen` (`assignmentId != null`) e o
   `ScalesRepository.deleteAssignment` já existiam e funcionavam desde a Fase 7
   — o que nunca foi escrito é o caminho da tela até eles. A `scale_tab_view`
   só tinha o botão de criar. A chave `scales_assignment_delete_confirm`
   estava no `.arb` desde o plano, sem nenhum uso.
2. **Toque na célula abre o editor; excluir mora dentro do editor.** A
   alternativa era uma `CupertinoActionSheet` com "Editar/Excluir" no toque,
   mas ela cobra um passo extra no caso comum (editar) e a exclusão teria de
   repetir a confirmação de qualquer forma. A linha vermelha no fim do
   formulário é o mesmo desenho de `admin/scale_type_editor_screen.dart`.
3. **Um gesto de arrastar sobre a célula ficou de fora.** Na grade de sete
   dias uma célula tem poucos milímetros de largura; arrastar ali erraria de
   coluna com frequência, e o `Dismissible` do aviso na tela Início (que
   funciona porque a célula ocupa a largura da tela) não se traduz para cá.
4. **O chevron só aparece para quem pode editar**, e na lista, não na grade.
   Célula com chevron que não abre nada engana; e na grade o ícone empurraria
   os nomes para fora da coluna. Quem pode editar descobre a grade pelo toque
   — tem `Semantics(button: true)` para o leitor de tela.
5. **`scaleTypeId` sai da própria linha, não da aba aberta.** Nas listas adhoc
   e "Anteriores" o recorte não é por período, e amarrar a rota à aba mandaria
   o editor para a escala errada se essas listas algum dia misturarem tipos.
6. **Responsável de escala também exclui, não só admin.** O gate da UI é
   `canEditScale`, e no servidor a exclusão é soft delete — um `update` de
   `deleted_at`, coberto por `scale_assignments_update`
   (`manages_scale(scale_type_id)`). A policy `scale_assignments_delete`, que
   exige `is_admin()`, vale só para o DELETE físico, que o app não usa.
7. Coberto por `test/ui/scale_tab_view_test.dart`: o toque abre o editor com o
   id certo na lista e na grade, e não abre nada para quem não pode editar.

#### Arquivo excluído voltava a cada sync — só para o admin (pós-Fase 10)

Sintoma relatado: um atalho na aba Arquivos sumia ao ser excluído e voltava na
sincronização seguinte, para sempre.

1. **A exclusão funcionava.** A linha no servidor estava com `deleted_at`
   preenchido. Nada errado no repositório, no outbox nem nas policies — o
   defeito estava no caminho de **volta**.
2. **`FOR ALL` inclui SELECT.** `documents_admin_write` é
   `for all ... using (is_admin())`, e no Postgres o `using` de uma policy
   `FOR ALL` vale também para SELECT. Policies permissivas se somam com **OR**,
   então para quem é admin `is_admin()` sozinho libera a leitura e o
   `deleted_at is null` da `documents_select` deixa de importar. O servidor
   devolvia a lápide.
3. **O pull `fullReplace` gravava a lápide como linha viva.** O descarte de
   `deleted_at != null` existia **só no ramo incremental** de
   `SyncService._doPull`; o `fullReplace` dava `upsert` em tudo o que chegava.
   Como o cache do drift não tem a coluna `deleted_at` (por desenho — nenhuma
   query de leitura precisa lembrar de filtrar), a lápide entrava como
   documento normal, em todo pull.
4. **Por que passou pelo harness de RLS.** A asserção de §7b media a
   visibilidade do arquivo excluído pelo **obreiro comum**, que de fato não o
   vê. O admin nunca foi testado. Adicionada a asserção
   `admin AINDA VE o arquivo excluido (policy FOR ALL)`, que documenta o
   comportamento do servidor em vez de escondê-lo.
5. **A correção é no cliente, não na policy.** Filtrar a lápide no pull vale
   mesmo que a policy mude, e o contrário não: o cliente não deve depender de
   o servidor lembrar de esconder a linha morta. Mexer nas 13 policies `FOR
   ALL` do schema seria uma mudança larga para nenhum ganho visível — e a
   leitura da lápide pelo admin é justamente o que permite recuperar o item.
6. **Era a mesma armadilha em todas as entidades `fullReplace`**, não só em
   `documents`: `profiles` (conta excluída pelo `delete_own_account`) e as três
   tabelas de cadastro da lavanderia têm policy `FOR ALL` de admin e são
   `fullReplace`. Um único filtro no pull fecha a classe inteira.
7. **Nada a limpar no aparelho.** O primeiro pull depois da atualização
   reconstrói a tabela sem a lápide.
8. Coberto por `test/sync/documents_test.dart` ("lápide não entra no cache,
   nem vinda do fullReplace"), que também verifica que ela não volta num
   segundo pull.

#### Eventos: dia inteiro de vários dias, marcação no calendário e exclusão (pós-Fase 10)

Três pedidos sobre a aba Eventos.

1. **"Dia inteiro" já existia; o que faltava era o campo de fim.** A chave
   estava lá desde a Fase 6, mas escondia a linha "Fim" — e com isso um evento
   de dia inteiro só podia durar um dia, o que exclui retiro, conferência e
   viagem de equipe. Agora o dia inteiro muda só duas coisas: a roda de seleção
   abre apenas a data e os rótulos passam a "Data de início"/"Data de fim".
   Mesmo desenho do Calendário do iOS.
2. **O calendário lia só `startsAt`.** `daysWithEventsProvider`,
   `eventsForDayProvider` e o `eventLoader` do `TableCalendar` comparavam a
   data de início com o dia, então um evento de sexta a domingo existia só na
   sexta. Passaram todos a usar `eventDayRange`/`eventOccursOn`
   (`agenda_providers.dart`), que devolvem o intervalo de dias ocupados.
3. **Fim à meia-noite é ambíguo, e a resposta depende do `all_day`.** Num
   evento com hora, 20:00→00:00 termina no instante em que o outro dia começa:
   marcar o dia seguinte poria bolinha em dia vazio. Num evento de dia inteiro,
   a meia-noite é exatamente como o editor grava a data de fim (a roda não pede
   hora) e significa "este dia todo" — descontar um dia encurtaria um retiro de
   21 a 23 para 21 a 22. A regra vale só quando `allDay` é falso.
4. **Aritmética de dia por componente, não por `Duration`.** `DateTime(y, m, d
   ± 1)` em vez de somar 24 h: na virada do horário de verão o `Duration` erra
   o dia. O Brasil não tem mais DST, mas as datas vêm do servidor.
5. **Teto de um ano no intervalo.** Erro de digitação na data (2126 em vez de
   2026) pontilharia o calendário por um século, e "tem algo todo dia" não é
   informação.
6. **O rótulo do cartão passou a dizer o intervalo** quando o evento atravessa
   dias — só "20:00 – 08:00" numa quarta, para um evento que começou na
   segunda, engana. E o `Text` do horário virou `Flexible`: o rótulo de
   intervalo é bem mais longo que um "20:00" e estourava a linha quando o
   evento também tinha local.
7. **Excluir só aparece para admin.** `deleteEvent` já existia no repositório;
   faltava o caminho na UI. A linha vermelha vai no fim do editor, como nos
   outros editores. O gate por `isAdminProvider` não é cosmético: o cartão do
   evento abre este editor para **qualquer** obreiro (ver o TODO da tela de
   detalhe), e `events_admin_write` exige `is_admin()` — oferecer a exclusão a
   quem a policy vai recusar faria o evento sumir e voltar no primeiro sync.
8. **Validação local de `ends_at >= starts_at`.** Espelha o CHECK
   `events_dates_ordered`; passou a poder acontecer de verdade agora que o dia
   inteiro tem campo de fim.
9. **Fica registrado o que não foi tocado:** o editor de evento continua
   abrindo para obreiro comum, e o botão Salvar dele continua visível — uma
   edição feita por quem não é admin sai otimista e é revertida no sync, sem
   mensagem. É anterior a esta mudança e o conserto certo é a tela de detalhe
   do evento, que o TODO da Fase 6 já prevê.
10. Coberto por `test/core/event_days_test.dart` (15 testes de intervalo de
    dias, incluindo meia-noite, dia inteiro, virada de mês e o teto) e
    `test/ui/event_editor_test.dart` (6 testes de rótulo, campo de fim e
    visibilidade do excluir).

#### Distribuição: APK à mão no Android, App Store não listada no iOS (pós-Fase 10)

Decisão do solicitante: não há conta paga na Play Store, e o app é interno —
não precisa ficar aberto ao público. Android sai como APK instalado à mão; iOS
vai para a App Store com **distribuição não listada**, por conta de
organização. Passo a passo em `docs/LANCAMENTO.md`.

1. **O build de release do Android passou a FALHAR sem a chave**, em vez de
   cair nas debug keys. O fallback silencioso era aceitável quando o destino
   era a Play, que recusa o artefato e avisa. Distribuindo APK à mão o silêncio
   cobra caro: um APK debug-signed **instala sem reclamar**, e o APK seguinte —
   assinado com a chave de verdade — não instala em cima
   (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`). As 30 pessoas teriam de desinstalar
   e entrar de novo, e quem descobre é o usuário, semanas depois. Escape
   explícito para medir tamanho: `-Pveredas.allowDebugSigning=true`.
2. **A chave deixou de ser "de upload".** Sem Play App Signing não existe o
   reset pelo suporte do Google que o §3 deste arquivo menciona: perder o
   `.jks` significa que ninguém atualiza o app instalado. O `keyAlias=upload` e
   o nome do arquivo ficaram impróprios e continuam assim — trocar o alias
   troca a chave.
3. **Os comandos de verificação do §3 são para o AAB e devolvem vazio num
   APK**, o que se lê como "não assinado" e "sem INTERNET" — os dois falsos. O
   `jarsigner` só entende assinatura v1, que o APK não tem (v2/v3 apenas), e o
   `AndroidManifest.xml` do APK é binário com strings em UTF-16, que o
   `strings` não acha sem `-el`. Para APK: `apksigner verify --print-certs` e
   `aapt2 dump badging`. Verificado num APK real: `CN=Base Missionaria JOCUM
   Veredas`, V2, `INTERNET` presente, versionCode 1, 67,5 MB.
4. **A impressão digital SHA-256 do certificado está em `docs/LANCAMENTO.md`.**
   Não é segredo, e permite conferir um APK sem ter o keystore.
5. **O workflow `android-release` do Codemagic virou APK e exige assinatura.**
   Antes gerava um AAB **sem signing config** — a máquina do CI não tem o
   `key.properties`, que é gitignored, então o artefato saía com debug keys e a
   Play o recusaria. Agora declara `android_signing: [veredas_upload]` e
   confere o signatário no artefato. Fica registrado que o workflow é
   dispensável: Android compila de graça na máquina Linux, e os 500 minutos
   gratuitos de macOS existem para o iOS.
6. **O `ios-release` continua parando no TestFlight de propósito.** A primeira
   submissão precisa da ficha da loja, do pedido de não listagem e da conta de
   demonstração — nada disso um build automático resolve. Comentado no
   `codemagic.yaml` para ninguém "consertar".
7. **A conta de demonstração é o que mais reprova este app.** O cadastro exige
   convite e aprovação de admin, então o revisor da Apple não entra sozinho
   (Guideline 2.1) — e a Play pergunta o mesmo em "Acesso ao app". Precisa de
   um perfil já aprovado, criado para isso, e confirmado antes de cada
   submissão.
8. **TestFlight não serve como destino final:** o build expira em 90 dias.
   Ad Hoc pede UDID de cada aparelho; o Enterprise Program custa US$ 299/ano e
   a Apple recusa organização pequena. A distribuição não listada é permanente
   e instala por link.
