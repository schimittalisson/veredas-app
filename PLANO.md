# Veredas App — Plano de Desenvolvimento

App de gerenciamento para a Base Missionária JOCUM Veredas (Joinville/SC).
Flutter (Android + iOS), backend Supabase, cache offline com drift.

> **Este documento é a especificação mestra.** Um agente de IA deve conseguir
> executá-lo fase por fase sem precisar de contexto adicional. Documentos
> complementares:
>
> | Arquivo | Conteúdo |
> |---|---|
> | `PLANO.md` (este) | Visão, arquitetura, decisões, fases de execução, critérios de aceite |
> | `SCHEMA.md` | SQL completo do Supabase: tabelas, RLS, funções, triggers, seeds |
> | `TELAS.md` | Especificação de UI tela por tela (layout, widgets, estados, permissões) |
> | `AGENTS.md` | Convenções de código, comandos e armadilhas — ler antes de escrever código |
> | `sample-images/` | Mockups de referência das telas Início, Agenda e Oração |

---

## 1. Visão do produto

A base tem ~20 obreiros. O app centraliza informação que hoje vive em grupos de
WhatsApp e planilhas soltas:

| Tab | Função |
|---|---|
| **Início** | Avisos da liderança, links das redes sociais, dados institucionais da base |
| **Agenda** | Eventos pontuais (com data/hora/local) + cronograma semanal fixo em formato de grade |
| **Escalas** | Abas por tipo de escala: Servir ao Todo, Lixo, Café da Manhã, Intercessão, Café da Gratidão |
| **Oração** | Mural de pedidos de oração no estilo feed, com busca por título |

Autenticação por e-mail/senha **com código de convite**, e permissões
granulares: cada tipo de escala tem um responsável, e só ele (ou um admin) pode
editá-la.

### Não-objetivos da v1

Explicitados para evitar escopo indefinido:

- Sem chat/mensagens diretas (o WhatsApp continua sendo o canal de conversa).
- Sem gestão financeira, doações ou pagamentos.
- Sem controle de presença/check-in em eventos.
- Sem versão web (o `drift` local é configurado apenas para native; suporte web
  exigiria WASM e está fora de escopo).

---

## 2. Decisões de arquitetura

### 2.1 Backend: Supabase

**Escolhido.** Justificativa:

- **Postgres de verdade.** O domínio é fortemente relacional (escala → tipo →
  responsável → obreiro). Modelar isso em Firestore geraria desnormalização e
  duplicação manual.
- **Row Level Security resolve o requisito central de permissão.** "Só o
  responsável pela escala de Servir ao Todo pode editá-la" é uma política SQL de
  5 linhas, aplicada no banco. Não há como um cliente comprometido burlar.
  Em Firestore isso viraria uma árvore de `security rules` bem menos legível.
- **Custo.** Free tier: 500 MB de banco, 1 GB de Storage, 50.000 MAU. Para ~20
  obreiros isso nunca será excedido — o app roda de graça indefinidamente. O
  único gatilho de cobrança seria inatividade (projetos free pausam após 7 dias
  sem requisições; um app em uso diário não pausa).
- **Sem backend próprio para manter.** Auth, Storage e Realtime vêm prontos.

**Alternativas rejeitadas:**

- *Firebase*: NoSQL inadequado ao domínio relacional; regras de segurança menos
  expressivas para o modelo de papéis.
- *Backend próprio*: custo de infra e manutenção injustificável para 20 usuários.

**Risco assumido:** vendor lock-in moderado. Mitigado por ser Postgres puro — os
dados são exportáveis com `pg_dump` e o schema roda em qualquer Postgres. O
acoplamento real está em Auth e Storage, isoláveis atrás das interfaces de
repositório (ver §2.4).

### 2.2 SDK: atualizar o Flutter antes de começar

O SDK instalado em `~/development/flutter` é **Flutter 3.24.5 / Dart 3.5.4
(nov/2024)**. Isso é um bloqueio real, verificado empiricamente:

```
$ flutter pub get   # com drift ^2.32.1 no Dart 3.5.4
Because drift_dev >=2.28.2 depends on source_gen >=3.0.0, and source_gen >=2.0.0
requires SDK version >=3.6.0, version solving failed.
```

`supabase_flutter` atual exige Flutter ≥ 3.35, `flutter_riverpod` 3.x exige Dart
≥ 3.12, `drift` 2.34 exige Dart ≥ 3.10. Além disso, a App Store rejeita builds
feitos com SDKs de iOS antigos — publicar em 2026 com um SDK de 2024 não é
viável.

**Ação obrigatória na Fase 0:** `flutter upgrade` para o stable atual
(**3.44.8 / Dart 3.12.2**, verificado em 2026-08-03).

> Isso **não** afeta o CalorieMate: o projeto tem `pubspec.lock` commitado e
> continua resolvendo as mesmas versões. Se o build dele quebrar por causa do
> AGP/Gradle antigo (AGP 8.1.0, Gradle 8.3), rode `flutter downgrade` ou instale
> os dois SDKs em diretórios separados alternando o `PATH`.

### 2.3 Gerenciamento de estado: Riverpod 3.x

Mantemos Riverpod (paridade com o CalorieMate), mas na versão **3.4.x**, estável
desde set/2025. **A API mudou em relação ao CalorieMate (Riverpod 2.5).** Não
copie os providers do CalorieMate literalmente — ver a tabela de diferenças em
`AGENTS.md` §4.

Sem `riverpod_generator`: providers escritos à mão, como no CalorieMate. Menos
codegen, menos superfície de falha.

### 2.4 Camadas

```
UI (screens/widgets)
  ↕ Riverpod providers
Repositories          ← única camada que a UI conhece
  ├─ Local: drift (cache + fila de escrita)
  └─ Remote: Supabase (interface abstrata + impl.)
```

Regras:

- **A UI nunca toca no `SupabaseClient` nem em DAOs do drift.** Só em providers.
- **Todo repositório de leitura expõe `Stream` vindo do drift**, nunca do
  Supabase direto. A tela lê do cache local; o `SyncService` alimenta o cache.
  Isso dá offline de graça e elimina spinners em navegação repetida.
- **Cada fonte remota fica atrás de uma interface abstrata** (ex.:
  `AuthService`, `ScalesRemoteSource`), com a implementação Supabase separada.
  Esse é o padrão que já deu certo no CalorieMate (`NutritionService` /
  `UsdaService`) e é o que torna os testes viáveis sem rede.

### 2.5 Estratégia offline-first

O requisito é "funcionar offline". Concretamente:

**Leitura — cache espelhado.** O drift local replica as tabelas do servidor. O
`SyncService` faz *pull* incremental por marca d'água:

1. Para cada entidade, lê `sync_state.last_synced_at`.
2. `select * from <tabela> where updated_at > (last_synced_at - 2 min)`.
   A janela de segurança de 2 minutos cobre desvio de relógio entre servidor e
   dispositivo; o upsert é idempotente, então reprocessar linhas é inofensivo.
3. Faz upsert no drift e grava `last_synced_at = max(updated_at)` recebido.
4. Linhas com `deleted_at != null` são removidas do cache local.

Por isso **toda tabela sincronizada tem `updated_at` (com trigger) e
`deleted_at`**. Nada é apagado fisicamente pelo cliente — *soft delete* é o que
permite propagar remoções para quem estava offline.

**Escrita — fila de saída (outbox).** Uma escrita do usuário, numa única
transação drift:

1. aplica a mudança otimisticamente na tabela de cache local (a UI atualiza na
   hora, porque a tela observa o `Stream` do drift);
2. insere uma linha em `outbox(entity, op, row_id, payload, attempts)`.

O `OutboxWorker` drena a fila em ordem de inserção quando há conectividade
(`connectivity_plus`), com backoff exponencial. Tratamento por tipo de falha:

| Falha | Ação |
|---|---|
| Rede/timeout | mantém na fila, retenta com backoff |
| `PostgrestException` 401/403 (RLS negou) | remove da fila, **reverte** o cache local, mostra erro ao usuário |
| 409/constraint | remove da fila, marca como conflito, força *pull* da entidade |

**Conflitos: last-write-wins pelo servidor.** É adequado aqui — dois obreiros
editando o mesmo slot de escala no mesmo minuto é raro, e o `updated_at` do
servidor define o vencedor. Merge de campo a campo seria complexidade sem
retorno neste domínio. **Documente isso na UI**: após um *pull*, se o valor
local otimista foi sobrescrito, a tela simplesmente reflete o servidor.

**Realtime é opcional e entra só na Fase 10.** Com 20 usuários, *pull* no
`resume` do app + pull-to-refresh cobre bem. Realtime é um upgrade de UX no
mural de oração, não um requisito.

### 2.6 Modelo de permissões

Três níveis, resolvidos no banco via RLS:

| Nível | Quem | Pode |
|---|---|---|
| **Não aprovado** | Cadastrou-se, convite não resgatado | Nada. Só vê a tela "aguardando aprovação" |
| **Obreiro** | Convite resgatado | Ler tudo; criar/editar/excluir os **próprios** posts de oração e comentários; marcar "estou orando" |
| **Responsável de escala** | Obreiro em `scale_managers` para um tipo | Tudo de obreiro + criar/editar/excluir atribuições **daquele tipo de escala** |
| **Admin** | Liderança | Tudo: avisos, agenda, cronograma, dados da base, convites, aprovar obreiros, definir responsáveis, editar qualquer escala, moderar mural |

Funções SQL `is_approved()`, `is_admin()` e `manages_scale(scale_type_id)`
concentram a lógica; as políticas apenas as invocam. Detalhes em `SCHEMA.md`.

> **Importante:** as mesmas permissões precisam ser refletidas na UI (esconder
> botões de edição), mas a UI é conveniência — **a garantia é o RLS**. Nunca
> confie apenas em ocultar o botão.

### 2.7 Identidade do app

| Item | Valor |
|---|---|
| Nome exibido | Veredas |
| Nome do pacote Dart | `veredas` |
| Bundle ID (Android/iOS) | `br.com.veredas.app` |
| Cor primária | a definir a partir da logo da base (mockup usa roxo `#8B00C7`; **confirmar com o solicitante**) |
| Idioma | pt-BR único (infra de l10n mantida, sem strings hardcoded) |

---

## 3. Stack e versões

Todas verificadas em 2026-08-03 contra Flutter 3.44.8 / Dart 3.12.2.

```yaml
name: veredas
description: "App de gerenciamento da Base Missionária JOCUM Veredas."
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: ^3.12.0

dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  intl: any

  cupertino_icons: ^1.0.8

  # Backend
  supabase_flutter: ^2.16.0

  # Estado
  flutter_riverpod: ^3.4.2

  # Navegação
  go_router: ^17.3.0

  # Cache local (offline)
  drift: ^2.34.3
  drift_flutter: ^0.3.1
  path_provider: ^2.1.6
  path: ^1.9.1

  # Infra
  connectivity_plus: ^7.3.1
  flutter_secure_storage: ^10.3.1
  package_info_plus: ^10.2.1

  # UI
  table_calendar: ^3.2.0
  cached_network_image: ^3.4.1
  url_launcher: ^6.3.2
  image_picker: ^1.2.3
  timeago: ^3.7.1

  # Modelos
  freezed_annotation: ^3.1.0
  json_annotation: ^4.12.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
  build_runner: ^2.16.0
  drift_dev: ^2.34.5
  freezed: ^3.2.5
  json_serializable: ^6.14.1
  flutter_launcher_icons: ^0.14.4
  mocktail: ^1.0.5

flutter:
  uses-material-design: true
  generate: true
  assets:
    - assets/images/
```

**Notas de armadilha nas dependências:**

- **Não adicione `sqlite3_flutter_libs`.** Foi descontinuado (`0.6.0+eol`,
  descrição literal: *"Not used anymore, update to version 3.x of
  package:sqlite3 instead"*). O `sqlite3` 3.x carrega a biblioteca nativa via
  *build hooks*. Use `drift` + `drift_flutter` + `path_provider`, que é o setup
  oficial atual. **Isto difere do CalorieMate**, que usa o esquema antigo.
- `freezed` 3.x mudou a sintaxe: as classes agora são
  `abstract class X with _$X`. A sintaxe do CalorieMate (freezed 2.x) não compila.
- `flutter_lints` 6.0 é mais rígido que o 4.0 do CalorieMate. Espere avisos novos.
- `intl: any` é intencional — deixa o `flutter_localizations` fixar a versão.

---

## 4. Estrutura de diretórios

```
lib/
  main.dart                      # bootstrap: Supabase.initialize, ProviderScope
  app.dart                       # MaterialApp.router (tema, l10n, router)
  core/
    config/
      env.dart                   # leitura de --dart-define (URL e anon key)
      constants.dart
    theme/
      app_theme.dart             # AppTheme.light()/dark()
      app_colors.dart            # ThemeExtension com cores fora do ColorScheme
    error/
      app_exception.dart         # AppException + mapeamento de PostgrestException/AuthException
      error_mapper.dart
    utils/
      date_utils.dart            # semana ISO, formatação pt-BR, grade semanal
      permissions.dart           # helpers de checagem de papel na UI
  data/
    models/                      # domínio (freezed) + DTOs (json_serializable)
      profile.dart
      invite.dart
      scale_type.dart
      scale_assignment.dart
      event.dart
      weekly_slot.dart
      prayer_post.dart
      prayer_comment.dart
      announcement.dart
      base_info.dart
      social_link.dart
    local/
      app_database.dart          # @DriftDatabase
      tables.dart                # tabelas de cache + sync_state + outbox
      daos/
        profile_dao.dart
        scale_dao.dart
        agenda_dao.dart
        prayer_dao.dart
        home_dao.dart
        sync_dao.dart            # sync_state + outbox
    remote/
      auth_service.dart          # interface
      supabase_auth_service.dart
      remote_source.dart         # interface genérica de pull/push por entidade
      supabase_remote_source.dart
    sync/
      sync_service.dart          # pull incremental
      outbox_worker.dart         # drenagem da fila de escrita
      sync_entity.dart           # enum/registro das entidades sincronizadas
    repositories/
      auth_repository.dart
      profile_repository.dart
      scales_repository.dart
      agenda_repository.dart
      prayer_repository.dart
      home_repository.dart
      admin_repository.dart
  providers/
    infra_providers.dart         # DI: supabase, db, daos, repos, services
    auth_providers.dart
    scales_providers.dart
    agenda_providers.dart
    prayer_providers.dart
    home_providers.dart
    admin_providers.dart
  ui/
    navigation/
      app_router.dart            # GoRouter + guard de autenticação
    widgets/
      root_scaffold.dart         # NavigationBar de 4 tabs
      app_avatar.dart
      empty_state.dart
      error_state.dart
      loading_state.dart
      offline_banner.dart
      section_header.dart
      confirm_dialog.dart
    screens/
      auth/
        splash_screen.dart
        login_screen.dart
        signup_screen.dart       # inclui código de convite
        forgot_password_screen.dart
        pending_approval_screen.dart
      home/
        home_screen.dart
        announcement_editor_screen.dart
      agenda/
        agenda_screen.dart       # tabs: Eventos | Cronograma
        event_detail_screen.dart
        event_editor_screen.dart
        weekly_slot_editor_screen.dart
      scales/
        scales_screen.dart       # TabBar dinâmica por scale_type
        scale_tab_view.dart
        assignment_editor_screen.dart
      prayer/
        prayer_wall_screen.dart
        prayer_detail_screen.dart
        prayer_composer_screen.dart
      profile/
        profile_screen.dart
        edit_profile_screen.dart
      admin/
        admin_screen.dart
        members_screen.dart      # aprovar/promover obreiros
        invites_screen.dart
        scale_managers_screen.dart
l10n/
  app_pt.arb
supabase/
  migrations/                    # SQL versionado (ver SCHEMA.md)
  seed.sql
test/
  helpers/
  ...
```

---

## 5. Fases de execução

Cada fase tem **critério de aceite verificável**. Não avance sem cumpri-lo.
Faça um commit por fase.

### Fase 0 — Ambiente e esqueleto do projeto

**Objetivo:** projeto compilando, vazio mas configurado.

1. `flutter upgrade` → confirmar `flutter --version` ≥ 3.44.8.
2. Criar o projeto:
   `flutter create --org br.com.veredas --project-name veredas --platforms=android,ios .`
   (executar dentro de `/home/alisson.silva/Documentos/veredas-app/`; o
   `create` preserva os `.md` e `sample-images/` já existentes).
3. `git init`, `.gitignore` (garantir `.env`, `*.jks`, `ios/Pods/`).
4. Escrever o `pubspec.yaml` de §3 e rodar `flutter pub get`.
5. `analysis_options.yaml`:
   ```yaml
   include: package:flutter_lints/flutter.yaml
   analyzer:
     exclude: ["**/*.g.dart", "**/*.freezed.dart", "lib/l10n/**"]
     errors:
       invalid_annotation_target: ignore
   ```
6. `l10n.yaml` + `l10n/app_pt.arb` (com `"@@locale": "pt"`), `generate: true`.
7. Android: `minSdk = 23` (exigido pelo `flutter_secure_storage` 10.x),
   `compileSdk`/`targetSdk` no padrão do Flutter, Java 17.
8. Configuração de segredos **por `--dart-define`, não por `.env`**:
   `lib/core/config/env.dart` com
   `static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');`
   Criar `env/dev.json` (gitignored) e `env/dev.example.json`. Rodar com
   `flutter run --dart-define-from-file=env/dev.json`.
   *Por que não `.env` como no CalorieMate:* o `.env` declarado como asset fica
   legível dentro do APK. A `anon key` do Supabase é pública por design (a
   proteção é o RLS), mas a URL/`anon key` via `dart-define` evita o hábito de
   empacotar segredos como asset.

**Aceite:** `flutter analyze` sem erros; `flutter build apk --debug` conclui.

---

### Fase 1 — Backend Supabase

**Objetivo:** banco pronto, com RLS ativo e dados de teste.

1. Criar projeto em supabase.com (região `sa-east-1` / São Paulo — menor
   latência para Joinville). Guardar `SUPABASE_URL` e `anon key`.
2. Aplicar os SQLs de `SCHEMA.md` **na ordem indicada**, como migrations em
   `supabase/migrations/`.
3. Aplicar `supabase/seed.sql`: os 5 `scale_types`, `base_info`, `social_links`.
4. Criar buckets no Storage: `avatars` e `event-covers` (privados, com policies
   de `SCHEMA.md` §7).
5. **Auth settings** (painel → Authentication):
   - Habilitar "Confirm email".
   - **Configurar SMTP próprio** (Resend ou Brevo, ambos com free tier). O SMTP
     embutido do Supabase é limitado a ~2 e-mails/hora e **vai falhar** no
     cadastro de 20 obreiros. Isto é um bloqueio prático real, não um detalhe.
   - Site URL / Redirect URLs: incluir o deep link
     `br.com.veredas.app://login-callback/`.
   - Desabilitar signup anônimo.
6. Criar um usuário admin manualmente e promovê-lo:
   `update profiles set role='admin', is_approved=true where email='...';`
7. Gerar um convite de teste:
   `insert into invites (code, role, max_uses) values ('VEREDAS2026','obreiro',20);`

**Aceite (verificar com dois usuários no SQL Editor / `supabase` CLI):**

- Usuário não aprovado recebe 0 linhas em `select * from events`.
- Obreiro aprovado **não** consegue `insert` em `scale_assignments` de um tipo
  que não gerencia (erro de RLS).
- Responsável de `servir-ao-todo` consegue inserir naquele tipo e **falha** em
  `lixo`.
- Obreiro consegue `update` no próprio `prayer_post` e falha no de outro.

> Esse teste de RLS é o momento mais importante da Fase 1. Se ele passar, a
> segurança do app está resolvida.

---

### Fase 2 — Fundação Flutter

**Objetivo:** app navega entre 4 tabs vazias, com tema e i18n.

1. `main.dart`: `WidgetsFlutterBinding.ensureInitialized()`,
   `await Supabase.initialize(url: Env.supabaseUrl, anonKey: Env.supabaseAnonKey)`,
   `runApp(ProviderScope(child: VeredasApp()))`.
2. `core/theme/app_theme.dart`: `AppTheme.light()`/`dark()` com
   `ColorScheme.fromSeed(seedColor: ...)` + sub-temas centralizados
   (`appBarTheme`, `cardTheme`, `navigationBarTheme`, `inputDecorationTheme`,
   `filledButtonTheme`).
   *Diferente do CalorieMate*, que escreve dois `ColorScheme` const à mão —
   `fromSeed` gera M3 correto com uma fração do código.
   Cores extras (categorias de escala, status) em `ThemeExtension<AppColors>`.
3. `ui/navigation/app_router.dart`: `StatefulShellRoute.indexedStack` com 4
   branches (`/inicio`, `/agenda`, `/escalas`, `/oracao`) + rotas *pushed*.
   O guard de autenticação entra na Fase 3.
4. `ui/widgets/root_scaffold.dart`: `NavigationBar` M3, mesmo padrão do
   CalorieMate (`goBranch(index, initialLocation: index == currentIndex)`).
5. Telas *skeleton* das 4 tabs (só `Scaffold` + título do l10n).
6. Widgets compartilhados: `EmptyState`, `ErrorState`, `LoadingState`,
   `ConfirmDialog`, `SectionHeader`.

**Aceite:** app roda, as 4 tabs alternam preservando estado, tema claro/escuro
segue o sistema, nenhuma string hardcoded nas telas.

---

### Fase 3 — Autenticação e papéis

**Objetivo:** fluxo completo de entrada, com bloqueio real por aprovação.

1. `data/remote/auth_service.dart` (interface):
   `signIn`, `signUpWithInvite`, `signOut`, `resetPassword`,
   `Stream<AuthState> authStateChanges`, `Session? currentSession`.
2. `supabase_auth_service.dart`: implementação. `signUpWithInvite` faz
   `auth.signUp(...)` e, com a sessão ativa, chama
   `client.rpc('redeem_invite', params: {'invite_code': code})`.
   Mapear erros da RPC (`INVITE_NOT_FOUND`, `INVITE_EXPIRED`,
   `INVITE_EXHAUSTED`) para `AppException` com mensagem localizada.
   > Se "Confirm email" estiver ativo, não há sessão imediatamente após o
   > `signUp`. Guarde o código de convite localmente (`flutter_secure_storage`) e
   > resgate no primeiro login bem-sucedido. Trate os dois caminhos.
3. `authRepositoryProvider` + `authStateProvider` (`StreamProvider`) +
   `currentProfileProvider` (perfil do usuário logado, do cache drift).
4. **Guard no router.** O `GoRouter` passa a ser um provider
   (`routerProvider`), com `refreshListenable` ligado ao stream de auth.
   Lógica de `redirect`:
   - sem sessão → `/login` (exceto rotas de auth);
   - com sessão e `profile.is_approved == false` → `/aguardando`;
   - com sessão aprovada em rota de auth → `/inicio`.
5. Telas: `splash`, `login`, `signup` (nome, e-mail, senha, **código de
   convite**), `forgot_password`, `pending_approval` (com botão "verificar
   novamente" e "sair").
6. Sessão persistida: o `supabase_flutter` já persiste por padrão. Validar que
   reabrir o app mantém o login.
7. `profile_screen.dart`: dados do usuário, papel, escalas que gerencia,
   trocar foto (`image_picker` → bucket `avatars`), sair.

**Aceite:**

- Cadastro com código inválido mostra erro claro e **não** dá acesso.
- Cadastro com código válido → usuário aprovado com papel `obreiro`.
- Usuário sem aprovação fica preso em `/aguardando`, mesmo digitando `/escalas`
  na URL (testar com deep link).
- Fechar e reabrir o app mantém a sessão.

---

### Fase 4 — Camada de dados e sincronização

**A fase mais crítica.** Faça-a antes de qualquer tela de conteúdo, e teste-a
isoladamente.

1. `data/local/tables.dart`: tabelas de cache espelhando o servidor. Regras:
   - PK `TextColumn get id => text()()` (UUIDs do servidor, **não**
     `autoIncrement`);
   - todas têm `updatedAt` (`DateTimeColumn`);
   - `SyncState(entity text pk, lastSyncedAt datetime nullable)`;
   - `Outbox(id autoIncrement, entity text, op text, rowId text, payload text,
     createdAt datetime, attempts int, lastError text nullable)`.
2. `app_database.dart`: `@DriftDatabase`, `schemaVersion = 1`, conexão via
   `driftDatabase(name: 'veredas')` do `drift_flutter`,
   `beforeOpen: PRAGMA foreign_keys = ON`.
   **Migrations reais desde o início** (`onUpgrade` com steps por versão) — não
   repita o `onUpgrade: createAll()` do CalorieMate, que falha silenciosamente
   em mudança de coluna.
3. DAOs por área, expondo `Stream` para leitura e `Future` para escrita local.
4. `data/sync/sync_entity.dart`: registro declarativo das entidades
   sincronizadas (nome da tabela remota, DAO, conversor DTO↔linha do drift,
   ordem de sincronização respeitando FKs) **e o modo de sync**:
   `enum SyncMode { incremental, fullReplace }`.
   Duas tabelas não podem usar modo incremental porque sofrem `DELETE` físico —
   `scale_managers` usa `fullReplace`, e `prayer_interactions` não é cacheada
   (o mural espelha a **view** `prayer_feed`). Ver `SCHEMA.md` §
   "Estratégia de sincronização por tabela" antes de implementar.
5. `sync_service.dart`: `pullAll()` e `pull(entity)` conforme §2.5.
6. `outbox_worker.dart`: drenagem com backoff, tratamento por tipo de erro
   conforme a tabela em §2.5, `connectivity_plus` como gatilho.
7. Providers: `syncStatusProvider` (`idle`/`syncing`/`error`/`offline`) e
   `OfflineBanner` na UI.
8. Gatilhos de sync: no login, no `AppLifecycleState.resumed`, ao voltar a ter
   conexão, e por pull-to-refresh manual em cada tela.

**Aceite (testes automatizados, drift in-memory + `SupabaseClient` mockado):**

- `pull` insere, atualiza e remove (via `deleted_at`) linhas no cache.
- `pull` é idempotente: rodar duas vezes com os mesmos dados não duplica nada.
- Escrita offline aparece imediatamente no `Stream` do drift e fica na `outbox`.
- Ao voltar a conexão, a `outbox` esvazia e o registro chega ao servidor.
- Falha 403 do RLS remove o item da fila, **reverte** o cache e emite erro.

---

### Fase 5 — Tela Início

Ver `TELAS.md` §1. Aviso fixado da liderança, links de redes sociais
(`url_launcher`), acordeão de dados da base, editor de avisos para admin.

**Aceite:** obreiro vê tudo em modo leitura e não vê nenhum botão de edição;
admin cria/edita/exclui avisos; conteúdo visível com o avião ligado.

---

### Fase 6 — Tela Agenda

Ver `TELAS.md` §2. Duas abas:

- **Eventos**: `table_calendar` com marcadores + lista do dia selecionado;
  detalhe do evento; editor para admin.
- **Cronograma**: grade semanal fixa (dias nas colunas, horários nas linhas),
  com scroll horizontal e vertical sincronizados; editor de slot para admin.

**Aceite:** grade legível em tela de 360 dp; evento criado pelo admin aparece no
dia correto; fuso e horário de verão tratados via `DateTime` local (guardar
`timestamptz` no servidor, exibir em local).

---

### Fase 7 — Tela Escalas

Ver `TELAS.md` §3. `TabBar` **gerada dinamicamente** a partir de `scale_types`
(assim adicionar "Café da Gratidão" ou uma escala nova é um `insert` no banco,
não um release do app).

Cada aba: seletor de semana/mês + lista/grade das atribuições. FAB e ações de
edição visíveis **apenas** se `manages_scale(tipo)` ou admin.

**Aceite:**

- Obreiro comum vê as 5 abas em leitura, sem FAB.
- Responsável de "Servir ao Todo" vê o FAB só naquela aba.
- Se a UI for burlada, o servidor recusa (já validado na Fase 1).
- Escalas da semana atual visíveis offline.

---

### Fase 8 — Mural de Oração

Ver `TELAS.md` §4. Feed estilo Twitter: cartão com autor, `timeago`, título em
destaque, corpo, contador "estou orando", comentários. Composer com título +
corpo + opção anônimo. **Busca por título** via RPC `search_prayers`, com
debounce de 400 ms (mesmo padrão de debounce do `food_search_screen.dart` do
CalorieMate). Marcar pedido como respondido. Autor edita/exclui o próprio; admin
modera qualquer um.

**Aceite:** busca por "cura" encontra "Cura" e "curá" (acento e caixa
ignorados); post criado offline entra na fila e sobe depois; contador de "estou
orando" não duplica ao tocar duas vezes.

---

### Fase 9 — Administração

Ver `TELAS.md` §6. Visível só para admin: aprovar/reprovar obreiros, promover a
admin, gerar/revogar convites (com compartilhamento do código), definir
responsáveis por tipo de escala, editar dados da base e redes sociais.

**Aceite:** admin promove um obreiro a responsável por "Lixo" e, no dispositivo
daquele obreiro, o FAB da aba Lixo aparece após o sync.

---

### Fase 10 — Qualidade, iOS e lançamento

1. **Testes.** Meta mínima: sync/outbox (Fase 4), mapeamento de erros,
   permissões na UI, `date_utils`. Widget tests com `tester.pump()` explícito —
   **nunca `pumpAndSettle` sobre stream infinita do drift**, que é exatamente o
   que travou os 4 widget tests do CalorieMate. Use
   `ProviderScope(overrides: [...])` + `GoRouter` de teste (as telas usam
   `context.push`, que quebra em `MaterialApp` simples).
2. **Ícone e splash**: `flutter_launcher_icons` com a logo da base.
3. **Realtime (opcional)**: assinaturas em `prayer_posts` e `scale_assignments`
   disparando `pull` da entidade.
4. **Notificações (opcional, avaliar custo/benefício)**: push exige FCM +
   APNs + uma Edge Function reagindo a triggers. Só faça se o usuário priorizar.
5. **Release Android**: keystore próprio (`keytool -genkey ...`), `signingConfig`
   real, `minifyEnabled`/`shrinkResources` + `proguard-rules.pro` (reaproveitar
   o do CalorieMate), `flutter build appbundle --release`.
6. **iOS** (requer macOS + Xcode): `Info.plist` com `CFBundleDisplayName`,
   `CFBundleLocalizations` (`pt`, `pt-BR`), `NSPhotoLibraryUsageDescription`
   (por causa do `image_picker`); `CFBundleURLTypes` com o scheme do deep link;
   `cd ios && pod install`; signing no Xcode; `flutter build ipa --release`.
7. **LGPD**: o app guarda nome, e-mail, telefone e foto de pessoas
   identificáveis. Escrever uma política de privacidade curta (obrigatória para
   publicar nas duas lojas) e um caminho de exclusão de conta
   (`auth.admin.deleteUser` via Edge Function, ou solicitação ao admin).

**Aceite:** `flutter analyze` limpo, testes passando, AAB assinado instalando em
dispositivo real, fluxo completo validado com 2 contas de papéis diferentes.

---

## 6. Riscos e armadilhas conhecidas

| # | Risco | Mitigação |
|---|---|---|
| 1 | **Rate limit de e-mail do Supabase** (~2/h no SMTP embutido) trava o cadastro dos obreiros | Configurar SMTP próprio na Fase 1. Bloqueante. |
| 2 | **Recursão infinita em policy de RLS** ao consultar `profiles` dentro de uma policy de `profiles` | Todas as funções auxiliares são `security definer` com `search_path` fixo (ver `SCHEMA.md` §3) |
| 3 | Sync perde linhas por desvio de relógio | Janela de segurança de 2 min no filtro `updated_at` + upsert idempotente |
| 4 | Deleção não propaga para quem estava offline | *Soft delete* obrigatório (`deleted_at`) em toda tabela sincronizada |
| 5 | Complexidade do outbox estoura o prazo | Se necessário, degradar escopo: escrita exige conexão (com UI otimista), leitura permanece offline. Decisão consciente, não acidente. |
| 6 | Projeto Supabase free **pausa após 7 dias sem requisições** | Uso diário evita. Se o app ficar parado entre fases, reative no painel. |
| 7 | Riverpod 3 pausa providers fora de vista e retenta erros automaticamente — comportamento diferente do CalorieMate | Ler `AGENTS.md` §4 antes de escrever providers |
| 8 | `freezed` 3.x e `flutter_lints` 6.x têm sintaxe/regras diferentes das do CalorieMate | Não copiar modelos do CalorieMate literalmente |
| 9 | Grade do cronograma quebra em telas estreitas | Testar em 360 dp desde a Fase 6; scroll horizontal com cabeçalho fixo |
| 10 | Convite vazando permite cadastro indevido | `max_uses` + `expires_at` + admin pode revogar; aprovação manual como segunda barreira |

---

## 7. O que reaproveitar do CalorieMate

Caminho: `/home/alisson.silva/Documentos/CalorieMateFlutter`

**Copiar o padrão (não o código):**

| Padrão | Arquivo de referência |
|---|---|
| Shell de navegação com 4 tabs | `lib/ui/navigation/app_router.dart`, `lib/ui/widgets/root_scaffold.dart` |
| Separação DI vs estado de feature | `lib/providers/providers.dart` vs `lib/providers/app_providers.dart` |
| Interface remota abstrata + impl. injetável | `lib/data/remote/nutrition_service.dart` / `usda_service.dart` |
| Repositório fino expondo `Stream` + transação encapsulada | `lib/data/repositories/meal_repository.dart` |
| DAO drift | `lib/data/database/daos/macro_plan_dao.dart` |
| Lista com modo de seleção múltipla | `lib/ui/screens/home_screen.dart` |
| Formulário com validators do l10n | `lib/ui/screens/macro_calculator_screen.dart` |
| Debounce + `OverlayEntry` para busca | `lib/ui/screens/food_search_screen.dart` (~linhas 237-460) |
| Sub-temas centralizados no `ThemeData` | `lib/core/theme/app_theme.dart` |
| Helpers de teste com DB in-memory e override de provider | `test/helpers/test_helpers.dart` |

**Não repetir (erros conhecidos daquele projeto):**

1. `integer().withDefault(Constant(0))` como PK + `insertOrReplace` universal —
   aqui as PKs são UUIDs do servidor.
2. `onUpgrade: (m, from, to) => m.createAll()` — não migra colunas de verdade.
3. Mensagens de erro hardcoded em inglês dentro dos notifiers — usar
   `AppException` + l10n na UI.
4. `Notifier` sem tipo genérico (`extends Notifier` cru) — perde type safety.
5. `copyWith` com `errorMessage: errorMessage` (sem `??`) — comportamento sutil
   e traiçoeiro; se for intencional, comente.
6. `.env` empacotado como asset — usar `--dart-define-from-file`.
7. Dependências não usadas no `pubspec` (`fl_chart`, `crypto`,
   `cached_network_image`) — manter o pubspec enxuto.
8. Widget tests desabilitados com `@Skip` por travarem — resolver com `pump()`
   explícito desde o início.

---

## 8. Ordem de execução resumida

```
Fase 0  Ambiente + esqueleto            → flutter build apk --debug OK
Fase 1  Supabase: schema + RLS + seeds  → testes de RLS passando
Fase 2  Tema, router, 4 tabs vazias     → navegação funcionando
Fase 3  Auth + convite + guard + papéis → não aprovado não passa
Fase 4  drift + sync + outbox           → testes de sync passando  ⚠ crítica
Fase 5  Início
Fase 6  Agenda (eventos + cronograma)
Fase 7  Escalas (5 abas dinâmicas)
Fase 8  Mural de Oração (feed + busca)
Fase 9  Administração
Fase 10 Testes, ícone, iOS, release
```

## 9. Pendências a confirmar com o solicitante

Itens que o agente executor **não deve inventar**:

1. **Paleta de cores e logo.** O mockup usa o roxo padrão da ferramenta no-code.
   Pedir a logo da base e definir a cor semente a partir dela.
2. **Redes sociais reais** (URLs de Instagram, Facebook, X, YouTube, TikTok).
3. **Dados institucionais**: endereço, CEP, telefone, CNPJ.
4. **Cronograma semanal atual** da base, para popular o seed.
5. **Tipos de escala**: confirmar os 5 e seus turnos/tarefas (ex.: "Servir ao
   Todo" é por área — cozinha, banheiros, pátio? — ou por pessoa/semana?).
6. **Quem são os admins** iniciais.
7. **Push notifications** são desejadas na v1? (impacta Fase 10)
