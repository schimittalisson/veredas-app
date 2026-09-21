# Veredas

App de gerenciamento da **Base Missionária JOCUM Veredas** (Joinville/SC), para
cerca de 30 obreiros. Flutter (Android + iOS), backend Supabase e cache local
offline com drift.

O app cobre escalas de serviço, agenda de eventos, cronograma semanal, avisos,
mural de oração e arquivos da base, com um painel de administração para
aprovar membros, gerar convites e definir responsáveis por escala.

---

## Índice

- [Começando](#começando)
- [Comandos do dia a dia](#comandos-do-dia-a-dia)
- [Documentação do projeto](#documentação-do-projeto)
- [Estrutura de pastas](#estrutura-de-pastas)
- [Como a arquitetura funciona](#como-a-arquitetura-funciona)
- [Como fazer alterações comuns](#como-fazer-alterações-comuns)
- [Testes](#testes)
- [Build e publicação](#build-e-publicação)

---

## Começando

Pré-requisitos: Flutter com Dart SDK `^3.12.0` (ver `environment` no
[pubspec.yaml](pubspec.yaml)).

```bash
# 1. Dependências
flutter pub get

# 2. Código gerado (drift, freezed, json_serializable)
dart run build_runner build

# 3. Strings localizadas
flutter gen-l10n

# 4. Credenciais do Supabase
cp env/dev.example.json env/dev.json
#   preencha SUPABASE_URL e SUPABASE_ANON_KEY

# 5. Rodar
flutter run --dart-define-from-file=env/dev.json
```

> **Os segredos entram por `--dart-define-from-file`, nunca como asset.** Um
> arquivo `.env` declarado em `assets:` vai dentro do APK e pode ser extraído.
> `env/dev.json` e `env/prod.json` são gitignored; só o `dev.example.json` é
> versionado.

Sem o passo 2 o projeto **não compila** — `app_database.g.dart`,
`profile.freezed.dart` e `profile.g.dart` não são versionados.

---

## Comandos do dia a dia

```bash
flutter analyze                                   # análise estática
flutter test                                      # suíte completa
flutter test test/sync/                           # só uma suíte
flutter test --plain-name "nome do teste"         # um teste específico

dart run build_runner build                       # codegen
dart run build_runner watch                       # codegen contínuo
flutter gen-l10n                                  # regenerar strings
```

> **Não passe `--delete-conflicting-outputs`** no build_runner: a flag foi
> removida na versão 2.15 e o comando apenas avisa que foi ignorada.

As armadilhas de versão das dependências estão comentadas direto no
[pubspec.yaml](pubspec.yaml) — leia antes de subir qualquer pacote. Em resumo:
`build_runner` e `drift_dev` estão travados por conflitos reais de resolução
com o `freezed` e com o `meta` que o SDK fixa.

---

## Documentação do projeto

| Arquivo | Conteúdo |
|---|---|
| [AGENTS.md](AGENTS.md) | **Regras do projeto.** Convenções de código, comandos, armadilhas de versão. Fica na raiz porque é o arquivo que as ferramentas de IA leem automaticamente |
| [docs/PLANO.md](docs/PLANO.md) | Especificação mestra: visão, arquitetura, decisões e fases de execução |
| [docs/SCHEMA.md](docs/SCHEMA.md) | Schema do Supabase — SQL completo, RLS, triggers e a estratégia de sync por tabela |
| [docs/TELAS.md](docs/TELAS.md) | Especificação de telas e navegação |
| [PRIVACIDADE.md](PRIVACIDADE.md) | Política de privacidade pública, exigida pelas lojas |
| [supabase/README.md](supabase/README.md) | Passo a passo para provisionar um projeto Supabase do zero |
| [supabase/local_test/README.md](supabase/local_test/README.md) | Testes das policies RLS em Postgres local |

Ordem de leitura sugerida: `docs/PLANO.md` → `AGENTS.md` → `docs/SCHEMA.md` /
`docs/TELAS.md`.

---

## Estrutura de pastas

```
veredas-app/
├── AGENTS.md              regras do projeto (lido por ferramentas de IA)
├── PRIVACIDADE.md         política de privacidade pública
├── README.md              este arquivo
├── codemagic.yaml         CI/CD (builds iOS e Android)
├── l10n.yaml              configuração da geração de strings
├── pubspec.yaml           dependências (com as travas de versão comentadas)
├── analysis_options.yaml  regras do linter
│
├── assets/images/         imagens embarcadas no app (logo, foto da equipe)
├── docs/                  documentação de contexto do projeto
├── env/                   credenciais por ambiente (só o .example é versionado)
├── sample-images/         mockups de referência citados em docs/TELAS.md
├── supabase/              migrations, seed e testes de RLS
│
├── lib/                   código do app
└── test/                  testes
```

### `lib/` — o código do app

```
lib/
├── main.dart              bootstrap: Supabase.initialize + ProviderScope
│
├── core/                  infraestrutura sem dependência de features
│   ├── config/env.dart    lê as variáveis de --dart-define
│   ├── error/             AppException + error_mapper (Postgrest/Auth → AppException)
│   └── theme/             cores, tipografia, tema Cupertino, compat com Material
│
├── data/                  camada de dados
│   ├── local/             drift: tabelas, conversores, AppDatabase
│   ├── daos/              consultas ao cache, uma DAO por área
│   ├── models/            modelos de domínio (freezed)
│   ├── remote/            serviços que falam direto com o Supabase (auth, admin)
│   ├── repositories/      a API que a UI enxerga: Stream para ler, Future para escrever
│   └── sync/              motor de sincronização (detalhado abaixo)
│
├── l10n/                  app_pt.arb (as strings) + código gerado
├── providers/             providers Riverpod, um arquivo por área
│
└── ui/
    ├── navigation/        app_router.dart: rotas e regras de redirecionamento
    ├── screens/           telas, agrupadas por área
    └── widgets/           componentes compartilhados
```

### `lib/data/sync/` — o motor de sincronização

| Arquivo | Papel |
|---|---|
| `sync_entity.dart` | Catálogo declarativo: uma `SyncEntity` por tabela, com modo de sync e conversores JSON ↔ drift |
| `sync_service.dart` | Faz o *pull* (servidor → cache), incremental ou substituição total |
| `outbox_worker.dart` | Faz o *push* (cache → servidor), drenando a fila de escritas |
| `remote_source.dart` | Abstração sobre o PostgREST — é o que os testes substituem por um fake |
| `connectivity_monitor.dart` | Detecta volta de conexão para disparar a drenagem |

### `test/`

| Pasta | Cobre |
|---|---|
| `test/sync/` | Pull, outbox, reversão em erro, backoff, janela de segurança. É a área mais crítica |
| `test/auth/` | Login, cadastro com convite, confirmação por código, aprovação |
| `test/core/` | Mapeamento de erros do Supabase para `AppException` |
| `test/local/` | Schema do drift, conversores, ordem da outbox |
| `test/ui/` | Testes de widget das telas |
| `test/helpers/` | `FakeRemoteSource`, `FakeAuthService`, builders de widget |

---

## Como a arquitetura funciona

**Offline-first.** As telas nunca leem do Supabase; leem do cache drift. O
`SyncService` alimenta esse cache. Consequência prática: o app abre e funciona
sem rede, com os dados da última sincronização.

**Toda escrita passa pela outbox.** A UI grava no cache local de forma otimista
e enfileira a operação; o `OutboxWorker` drena a fila quando há rede. Se o
servidor recusar, o cache é revertido. As exceções conscientes a essa regra
(login e upload de imagem) estão comentadas no código explicando o porquê.

**Fluxo de leitura:**

```
Supabase → SyncService → drift (cache) → DAO → Repository → Provider → Tela
```

**Fluxo de escrita:**

```
Tela → Repository → drift (otimista) + outbox → OutboxWorker → Supabase
```

**Permissões vivem no banco, não na UI.** Toda leitura passa pela função
`public.is_approved()` nas policies RLS. Esconder um botão é conveniência
visual; a barreira real é o Postgres. Ver [docs/SCHEMA.md](docs/SCHEMA.md).

**Duas estratégias de sync**, escolhidas por tabela em `sync_entity.dart`:

- **Incremental** — busca `updated_at` recente e remove do cache o que voltar
  com `deleted_at`. Eficiente, mas só funciona se o servidor nunca apagar a
  linha de verdade.
- **Substituição total** — limpa a tabela local e reinsere tudo. Usada onde há
  `DELETE` físico (`profiles`, `scale_managers`, `documents`,
  `prayer_interactions`). A tabela completa com o motivo de cada escolha está
  em [docs/SCHEMA.md](docs/SCHEMA.md).

---

## Como fazer alterações comuns

### Mudar um texto da interface

Nenhuma string fica hardcoded na UI. Edite [lib/l10n/app_pt.arb](lib/l10n/app_pt.arb)
e rode `flutter gen-l10n`. Na tela, use `AppLocalizations.of(context).a_chave`.

Para adicionar um idioma, basta um novo `.arb` na mesma pasta — a infra já está
montada.

### Adicionar uma tela

1. Crie o arquivo em `lib/ui/screens/<área>/`.
2. Registre a rota em [lib/ui/navigation/app_router.dart](lib/ui/navigation/app_router.dart):
   uma constante em `Routes` e um `GoRoute`.
3. Se a tela não deve ser acessível a quem não está aprovado, confira as listas
   `Routes.unauthenticated` e `Routes.unapproved`, que o `redirect` consulta.
4. Strings novas vão para o `.arb`.

### Adicionar um campo a uma tela existente

O caminho completo, de baixo para cima:

1. **Banco** — nova migration em `supabase/migrations/`, com prefixo ordenável.
2. **Cache** — coluna em [lib/data/local/tables.dart](lib/data/local/tables.dart),
   depois `dart run build_runner build`.
3. **Sync** — o conversor `_upsert<Entidade>` em
   [lib/data/sync/sync_entity.dart](lib/data/sync/sync_entity.dart) precisa ler
   o campo novo do JSON.
4. **Leitura** — a DAO em `lib/data/daos/` e o repositório em
   `lib/data/repositories/`.
5. **Tela** — o widget e as strings.

### Adicionar uma tabela sincronizada

Além dos passos acima, registre uma `SyncEntity` nova na lista `syncEntities`
de `sync_entity.dart`, com os quatro conversores (`upsert`, `remove`, `clear`,
`restore`) e o modo de sync. Escolha o modo pela regra acima: se a linha pode
ser apagada de verdade no servidor, use substituição total.

### Mudar uma regra de permissão

No banco, sempre. As policies estão em
`supabase/migrations/20260803000600_rls_policies.sql` e os testes delas em
`supabase/local_test/`. Ajustar só a UI não protege nada.

### Mexer no tema

Cores em [lib/core/theme/app_colors.dart](lib/core/theme/app_colors.dart),
tipografia em `app_typography.dart`. O app usa widgets Cupertino; o
`material_compat.dart` existe para os poucos componentes Material que ainda
aparecem.

---

## Testes

```bash
flutter test
```

A prioridade, do mais para o menos importante, está em
[AGENTS.md §7](AGENTS.md): sync e outbox primeiro, depois mapeamento de erros,
helpers puros e por fim widgets.

Os testes de sync usam drift **in-memory** e um `FakeRemoteSource` com dados
pré-configurados — não se mocka a cadeia fluente do `supabase_flutter`.

Ao corrigir um bug, o hábito do projeto é escrever o teste e **confirmar que
ele falha sem a correção** antes de considerá-lo pronto. Vários testes trazem,
no comentário de cima, qual era o bug que fixam.

---

## Build e publicação

```bash
# Android
flutter build appbundle --release --dart-define-from-file=env/prod.json

# iOS
flutter build ipa --release --dart-define-from-file=env/prod.json
```

### Distribuição

**Android é APK instalado à mão** (não há conta na Play Store) e **iOS é App
Store não listada**. O passo a passo das duas pontas, com os comandos de
verificação e o checklist de release, está em
[docs/LANCAMENTO.md](docs/LANCAMENTO.md).

### Assinatura do Android

A chave fica **fora do repositório**, em `~/.android-keys/veredas-upload.jks`,
apontada por `android/key.properties` (gitignored).

> Sem Play App Signing, **esta é a chave de assinatura do app**, não só a de
> envio: perdê-la significa que ninguém atualiza o app instalado, só
> reinstala. Faça backup do `.jks` e da senha.
>
> O build de release **falha** sem ela, de propósito — um APK debug-signed
> instala sem reclamar e bloqueia a atualização seguinte. Confirme quem
> assinou no artefato:
>
> ```bash
> BT=$(ls -d "$ANDROID_HOME"/build-tools/*/ | tail -1)
> "$BT/apksigner" verify --print-certs \
>   build/app/outputs/flutter-apk/app-release.apk | grep "certificate DN"
> # esperado: CN=Base Missionaria JOCUM Veredas, ...
> ```
>
> O `jarsigner` do [AGENTS.md §3](AGENTS.md) serve para o **AAB**; num APK ele
> devolve vazio, porque o APK não tem assinatura v1.

O passo a passo completo, incluindo qual `keytool` usar, está em
[AGENTS.md §3](AGENTS.md).

### CI

[codemagic.yaml](codemagic.yaml) define três workflows: `ios-unsigned`
(validação), `ios-release` (IPA assinado) e `android-release` (AAB). Os
workflows recriam o `env/prod.json` a partir das variáveis do Codemagic e
rodam o codegen antes de compilar.

> Os arquivos de código gerado não são versionados, e o CI clona do git — então
> **todo arquivo novo precisa estar commitado**. Um `.dart` esquecido fora do
> git quebra o build com `No such file or directory`, mesmo compilando na sua
> máquina.

### Backend

Para provisionar um Supabase do zero, siga [supabase/README.md](supabase/README.md).
Ele cobre migrations, seed, configuração de Auth (confirmação de cadastro por
código de 6 dígitos) e o SMTP próprio, que não é opcional — o SMTP embutido do
Supabase envia 2 e-mails por hora e existe só para desenvolvimento.
