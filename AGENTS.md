# Veredas App — Regras do Projeto

**Leia este arquivo antes de escrever qualquer código.** Ele contém as
convenções, os comandos e — o mais importante — as armadilhas de versão que vão
te custar tempo se você ignorá-las.

Ordem de leitura: `PLANO.md` → este arquivo → `SCHEMA.md` / `TELAS.md`.

---

## 1. Contexto

App de gerenciamento da Base Missionária Veredas (Joinville/SC), ~20 obreiros.
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
  deep links) e documente; o build só roda em macOS com Xcode.

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
dart run build_runner build --delete-conflicting-outputs
dart run build_runner watch --delete-conflicting-outputs   # durante o desenvolvimento

# Localizações
flutter gen-l10n

# Builds
flutter build apk --debug
flutter build appbundle --release --dart-define-from-file=env/prod.json
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
    redirect: (context, state) { /* guard, ver PLANO.md Fase 3 */ },
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
   drift in-memory + `SupabaseClient` mockado (`mocktail`).
   Casos mínimos: pull insere/atualiza/remove; pull idempotente; escrita offline
   entra na fila; fila drena; 403 reverte o cache.
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

Helpers em `test/helpers/test_helpers.dart`: `createTestDatabase()`,
`createTestContainer({overrides})`, fábricas de modelos
(`makeProfile()`, `makeScaleAssignment()`), `FakeAuthService`.

---

## 8. Segurança — regras não negociáveis

1. **RLS habilitado em toda tabela.** No Supabase, tabela sem RLS é pública para
   a `anon key`.
2. **Nunca** embarcar a chave `service_role` no app.
3. Ocultar um botão na UI **não é** controle de acesso. Toda permissão tem
   policy correspondente no banco (`SCHEMA.md` §6).
4. Funções que consultam `profiles` dentro de policies de `profiles` precisam ser
   `security definer` com `search_path` fixo — senão: recursão infinita de RLS.
5. Usuário comum **não pode** alterar o próprio `role`/`is_approved`. Garantido
   por policy **e** por trigger (`SCHEMA.md` §8).
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
- [~] Fase 1 — Backend Supabase (schema + RLS + seeds) — **SQL escrito, não
      aplicado.** Falta criar o projeto no supabase.com e seguir
      `supabase/README.md`. O aceite (validação de RLS) só é possível depois.
- [x] Fase 2 — Fundação Flutter (tema, router, 4 tabs)
- [ ] Fase 3 — Autenticação, convite e papéis
- [ ] Fase 4 — Camada de dados e sincronização ⚠ crítica
- [ ] Fase 5 — Tela Início
- [ ] Fase 6 — Tela Agenda
- [ ] Fase 7 — Tela Escalas
- [ ] Fase 8 — Mural de Oração
- [ ] Fase 9 — Administração
- [ ] Fase 10 — Qualidade, iOS e lançamento

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

**Correções no PLANO.md §3 — as versões declaradas não resolvem**

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

**Correção no SCHEMA.md §3 — `manages_scale` na ordem errada**

O `SCHEMA.md` diz que "o corpo de uma função `language sql` só é resolvido na
execução, então criar a função antes da tabela funciona". **Isso é falso** com
`check_function_bodies = on`, que é o padrão no Supabase: o corpo é validado já
no `CREATE FUNCTION`, e `manages_scale` referencia `public.scale_managers`
(criada no §4). Aplicar na ordem do documento falha com
`relation "public.scale_managers" does not exist`.

Extraída para `migrations/20260803000450_manages_scale.sql`, aplicada **depois**
das tabelas de domínio. As outras funções (`is_approved`, `is_admin`,
`norm_text`) não dependem de tabela de domínio e ficaram na `0300`.

**Correção no PLANO.md — `minSdk`**

O plano manda fixar `minSdk = 23`. O default do Flutter 3.44 é **24**, então 23
seria um downgrade, e o `flutter build` reescreve o `build.gradle.kts` na
migração do Gradle, revertendo o valor fixado. Mantido
`minSdk = flutter.minSdkVersion`, que já satisfaz o `flutter_secure_storage`.

**Depreciação no supabase_flutter 2.16**

`Supabase.initialize(anonKey:)` foi depreciado em favor de `publishableKey:`.
O `PLANO.md` e este arquivo citam o nome antigo. A variável de ambiente segue
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
`AppLocalizations.of(context)` — **sem** o `!` que o `TELAS.md` §"Padrões
obrigatórios" prescreve. Com o getter não-nulo, o `!` seria erro de lint
(`unnecessary_non_null_assertion`). Escolhido o getter não-nulo por eliminar
uma classe inteira de null-assertions ruidosas.

**Tema: paleta da logo (decisão do solicitante)**

O mockup usava o roxo padrão do construtor no-code. A logo real da base (o
vitral) definiu a paleta, com a orientação do solicitante de "branco e preto com
detalhes nas cores":

- **Semente do `ColorScheme`**: marrom `#6E5849` (traço e tipografia da logo).
- **`surface` no tema claro**: creme `#F2EDE6` (fundo do vitral), em vez de
  branco puro.
- **5 acentos do vitral** em `ThemeExtension<AppColors>`: verde-água, azul,
  laranja, amarelo, roxo. São **semânticos**, não decorativos: identificam tipo
  de escala e categoria de evento.
- `AppColors.accentFor(key)` deriva a cor de uma **string** (o `slug` do tipo de
  escala), não do índice da lista — assim inserir um tipo novo no meio não muda
  a cor dos existentes, e não é preciso uma coluna de cor no banco. A soma de
  code units é usada em vez de `hashCode` porque o `hashCode` do Dart **não é
  estável entre execuções**.
- Cada acento tem par `accent` (vivo, para bordas/ícones) e `accentContainer`
  (dessaturado, para fundos). **Nunca escreva texto sobre `accent` puro**: o
  amarelo e o laranja da logo reprovam em WCAG AA como fundo.

**Pendências que dependem do solicitante**

- Salvar a logo em `assets/images/logo.png` (splash, launcher icon, tela de
  login). Hoje não há asset de imagem.
- Criar o projeto Supabase e aplicar `supabase/README.md`.
- Substituir os `TODO` de `base_info` e `social_links` pelos dados reais.
- Cronograma semanal real da base (o seed tem 3 slots de exemplo).
