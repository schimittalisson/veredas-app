# Veredas App — Especificação de Telas

Referência visual: `sample-images/tela-inicio.jpeg`, `tela-agenda.jpeg`,
`tela-mural-oracao.jpeg`.

> **Sobre os mockups:** foram feitos em um construtor no-code (Wix/Bubble). O
> **layout e a hierarquia de informação** devem ser seguidos; o **estilo visual
> não** — o roxo, as fontes e os cartões são o tema padrão daquela ferramenta.
> Use Material 3 com a cor semente da logo da base (`PLANO.md` §9).

## Navegação

`StatefulShellRoute.indexedStack` com 4 branches:

| Índice | Rota | Tab | Ícone (outlined / filled) |
|---|---|---|---|
| 0 | `/inicio` | Início | `home_outlined` / `home` |
| 1 | `/agenda` | Agenda | `calendar_month_outlined` / `calendar_month` |
| 2 | `/escalas` | Escalas | `assignment_outlined` / `assignment` |
| 3 | `/oracao` | Oração | `favorite_outline` / `favorite` |

Rotas *pushed* (fora do shell, sem bottom bar):

```
/login  /cadastro  /esqueci-senha  /aguardando
/perfil  /perfil/editar
/admin  /admin/membros  /admin/convites  /admin/responsaveis
/admin/escalas  /admin/escalas/nova  /admin/escalas/editar
/aviso/novo  /aviso/:id/editar
/evento/:id  /evento/novo  /evento/:id/editar
/cronograma/novo  /cronograma/:id/editar
/escala/:tipo/atribuicao/novo  /escala/:tipo/atribuicao/:id/editar
/oracao/novo  /oracao/:id  /oracao/:id/editar
```

## AppBar comum a todas as tabs

Espelha o mockup (avatar à esquerda, ações à direita):

- **Leading**: `AppAvatar` (foto do perfil, 32 dp) → `context.push('/perfil')`.
- **Título**: nome da seção.
- **Actions**: `IconButton` de sync/offline (`OfflineBanner` cuida do estado
  persistente), e — **apenas para admin** — `IconButton(Icons.settings_outlined)`
  → `/admin`.

## Padrões obrigatórios em todas as telas

1. `final l = AppLocalizations.of(context)!;` e `final theme = Theme.of(context);`
   no topo do `build`. Zero strings hardcoded.
2. Listas: `AsyncValue.when(data:, loading:, error:)` com `EmptyState`,
   `LoadingState` e `ErrorState` compartilhados.
3. **Pull-to-refresh** (`RefreshIndicator`) em toda tela de lista, chamando
   `syncService.pull(entidade)`.
4. `OfflineBanner` fino no topo do `body` quando sem conexão ou com `outbox`
   pendente: *"Sem conexão — mostrando dados salvos"* / *"N alteração(ões)
   aguardando envio"*.
5. Botões de escrita são **renderizados condicionalmente** pela permissão. Isso é
   UX; a garantia é o RLS.
6. `if (!mounted) return;` após todo `await` que antecede `setState` ou navegação.
7. `padding: EdgeInsets.only(bottom: 80)` em listas com FAB.
8. Ações destrutivas passam por `ConfirmDialog`.

---

## §1 — Início (`/inicio`)

Referência: `tela-inicio.jpeg`.

`ListView` com as seções, na ordem:

### 1.1 Aviso fixado

Cartão no topo, equivalente ao "Proprietário · 17 hours ago" do mockup.

- Avatar do autor + nome + `timeago.format(createdAt, locale: 'pt_BR')`.
- Título (se houver, `titleMedium`) + corpo.
- Se admin: `PopupMenuButton` com Editar / Excluir.
- Fonte: `announcementsProvider` → primeiro item com `pinned = true`.

### 1.2 Redes sociais

`Row` centralizada de `IconButton`s circulares (`CircleAvatar` +
`Icons`/`flutter_svg` se precisar de logos de marca), um por `social_links`
ativo, ordenados por `ordering`. Toque → `url_launcher.launchUrl(mode:
LaunchMode.externalApplication)`.

Se a URL falhar em abrir, `SnackBar` com o erro — não falhe em silêncio.

### 1.3 Dados da Base

`SectionHeader('Dados da Base')` + lista de `ExpansionTile`, um por `base_info`
(o acordeão do mockup: "Endereço da base?", "CEP da base", ...).

- `title`: `label`; conteúdo expandido: `value` (`SelectableText`, para permitir
  copiar CNPJ/CEP).
- Ordenar por `ordering`.
- Se admin: ícone de edição no `trailing`, abrindo um `showModalBottomSheet` com
  `TextFormField` do valor.

### 1.4 Avisos anteriores

`SectionHeader` + lista dos `announcements` não fixados (limite 10) + "Ver tudo".

### Permissões

| Ação | Quem |
|---|---|
| Ver tudo | obreiro aprovado |
| Criar/editar/excluir aviso | admin |
| Editar `base_info` / `social_links` | admin |

**FAB**: só admin → `/aviso/novo`.

---

## §2 — Agenda (`/agenda`)

Referência: `tela-agenda.jpeg` (lista de cartões com capa) + requisito do
cronograma "bem estilo planilha".

`TabBar` de 2 abas no `AppBar` (`bottom`): **Eventos** | **Cronograma**.

### 2.1 Aba Eventos

1. **`TableCalendar`** (`table_calendar`) no formato `month`, recolhível para
   `week`:
   - `locale: 'pt_BR'`;
   - `eventLoader` marca os dias com evento;
   - `calendarFormat` alternável, `availableCalendarFormats` em pt-BR;
   - estilo herdado do `ColorScheme` (não hardcodar cores).
2. **Lista do dia selecionado** abaixo. Cartão de evento (`EventCard`):
   - capa `cached_network_image` 16:9 quando houver `cover_image_url`
     (placeholder com ícone da categoria quando não houver);
   - título (`titleMedium`), horário formatado (`08:00 – 10:00` ou "Dia inteiro"),
     local com `Icons.place_outlined`;
   - `Chip` da categoria.
   - Toque → `/evento/:id`.
3. Se nenhum evento no dia: `EmptyState` compacto ("Nenhum evento neste dia").
4. Abaixo do calendário, seção **"Próximos eventos"** quando o dia selecionado é
   hoje e não há eventos — evita a tela parecer vazia.

**Detalhe do evento** (`/evento/:id`): capa em `SliverAppBar` expandida, título,
data/hora completa, local (com botão "Abrir no mapa" via `url_launcher` +
`geo:`/Google Maps), descrição, autor. Admin: editar/excluir no `AppBar`.

**Editor** (`/evento/novo`, `/evento/:id/editar`) — só admin:
`Form` + `ListView` com título, descrição (multiline), `SwitchListTile`
"Dia inteiro", `showDatePicker`/`showTimePicker` para início e fim, local,
categoria (`DropdownButtonFormField`), capa (`image_picker` → bucket
`event-covers`). Validar `ends_at >= starts_at` antes de salvar.

### 2.2 Aba Cronograma (grade semanal)

O "estilo planilha" pedido. Implementação:

```
┌──────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┐
│ hora │ Seg │ Ter │ Qua │ Qui │ Sex │ Sáb │ Dom │  ← cabeçalho fixo (sticky)
├──────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
│ 06h  │  ▓  │     │     │     │     │     │     │
│ 07h  │  ▓  │     │  ▓  │     │     │     │     │
└──────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┘
   ↑ coluna de horas fixa       scroll horizontal →
```

Estrutura de widgets:

- `Row`:
  - **coluna fixa** de horários (largura 56 dp), com scroll vertical
    sincronizado;
  - `SingleChildScrollView(scrollDirection: Axis.horizontal)` contendo as 7
    colunas de dias (largura mínima 96 dp cada).
- Scroll vertical compartilhado entre a coluna de horas e a grade: use **um
  único `ScrollController`** para os dois, ou envolva tudo num
  `SingleChildScrollView` vertical externo. Não use dois controllers com
  listeners — gera jitter.
- Linha de hora = intervalo de 1 h, do menor `starts_at` ao maior `ends_at` dos
  slots ativos (não fixe 00h–23h: desperdiça espaço).
- Célula = `weekly_slots` daquele dia/hora: contêiner colorido pela categoria
  (do `ThemeExtension<AppColors>`), com título truncado em 2 linhas.
- Toque na célula → `showModalBottomSheet` com detalhes completos (título,
  horário, local, observações) e, para admin, ações de editar/excluir.

**Responsividade (obrigatório testar em 360 dp):** com 7 colunas de 96 dp a
grade tem 672 dp e sempre exigirá scroll horizontal — isso é esperado e
aceitável. Ofereça um `SegmentedButton` para alternar entre **Grade** e
**Lista por dia** (`ExpansionTile` por dia da semana), que é mais confortável no
celular. A grade é o diferencial pedido; a lista é o *fallback* de conforto.

**Editor de slot** (`/cronograma/novo`) — só admin: dia da semana
(`SegmentedButton` ou dropdown), hora início/fim (`showTimePicker`), título,
local, categoria, observações, `SwitchListTile` "Ativo".

### Permissões

Obreiro: leitura. Admin: tudo. **FAB** só para admin, criando na aba ativa
(evento ou slot).

---

## §3 — Escalas (`/escalas`)

Não há mockup — especificado a partir do requisito.

`TabBar` **gerada dinamicamente** de `scale_types` (ordenada por `ordering`,
`is_active = true`), com `isScrollable: true` (6 abas não cabem fixas em 360 dp):

```
Servir ao Todo │ Lixo │ Café da Manhã │ Intercessão │ Café da Gratidão │ Almoço
```

> Nunca hardcode as abas. Adicionar uma escala nova deve ser um `INSERT` no
> banco, não um release. Use `DefaultTabController` com `length` derivado do
> provider, e trate o caso `data.isEmpty`.

### 3.1 Conteúdo de cada aba (`ScaleTabView`)

1. **Seletor de período** no topo, conforme `cadence` do tipo:
   - `weekly`: navegador de semana — `‹ 3 – 9 de agosto ›` + botão "Hoje".
     A semana começa na **segunda** (ISO); usar helper em `core/utils/date_utils.dart`.
   - `monthly`: navegador de mês.
   - `adhoc`: sem navegador; lista as próximas atribuições e um `ExpansionTile`
     "Anteriores".
2. **Corpo**, conforme o tipo ter `slots` ou não:
   - **Com `slots`** (Servir ao Todo, Café da Manhã, Intercessão): tabela
     compacta — linhas = slots/áreas, células = a equipe escalada, um nome por
     linha. `Card` com `Table` ou `DataTable` (largura `Expanded`, sem scroll
     horizontal se couber).
   - **Sem `slots`** (Lixo, Almoço): lista simples por dia da semana:
     `ListTile(leading: dia, title: os nomes da equipe)`.
   - Uma atribuição pode ter **várias pessoas** (a equipe) e, opcionalmente, um
     **responsável geral** sobre elas — o caso do almoço, feito por um grupo de
     quatro com um líder. O responsável geral aparece como "responsável: Fulano"
     junto da equipe; quando não há equipe, ele ocupa o lugar dela (é assim que
     as atribuições anteriores às equipes continuam legíveis).
3. **Destaque do próprio nome.** Atribuições em que o usuário está na equipe
   (`member_ids`) **ou** é o responsável geral (`assignee_id`) recebem cor de
   fundo `primaryContainer` e um `Chip` "Você". É a informação mais útil da
   tela — o obreiro abre para saber *do que ele* está escalado.
4. **Resumo no topo**: "Você está escalado 2× nesta semana" quando aplicável.
5. `EmptyState` quando não há atribuições: "Escala desta semana ainda não foi
   montada" (+ botão "Montar escala" se o usuário gerencia o tipo).

### 3.2 Edição

**FAB visível apenas se `canEditScale(tipo)`**, onde:

```dart
bool canEditScale(Profile me, ScaleType t) =>
    me.role == AppRole.admin || me.managedScaleTypeIds.contains(t.id);
```

`managedScaleTypeIds` vem de `scale_managers`, cacheado no drift.

**Editor de atribuição** (`/escala/:tipo/atribuicao/novo`): data (ou intervalo,
para escala semanal), `slot` (seletor com os `slots` do tipo), `task`,
**equipe** (seleção múltipla sobre os obreiros aprovados → `member_ids`, mais
um campo livre separado por vírgula para quem não tem conta → `member_names`),
**responsável geral** (seletor com "—" como primeira opção, porque escala sem
responsável geral é o caso comum → `assignee_id`/`assignee_name`), observações.

Salvar exige ao menos uma pessoa entre equipe e responsável geral — a mesma
regra do CHECK `assignment_has_someone` no servidor.

Toque longo em uma atribuição → modo de seleção múltipla com exclusão em lote
(mesmo padrão do `home_screen.dart` do CalorieMate), **só para quem gerencia**.

Ação extra útil para o responsável: **"Duplicar semana anterior"** — copia as
atribuições da semana passada para a atual. Reduz drasticamente o trabalho
manual e é o tipo de recurso que faz o app ser adotado.

### Permissões

| Ação | Quem |
|---|---|
| Ver as abas | obreiro aprovado |
| Criar/editar/excluir atribuição de um tipo | responsável **daquele** tipo, ou admin |
| Criar/renomear/reordenar/excluir escalas | admin (via `/admin/escalas`) |
| Definir responsáveis | admin (via `/admin/responsaveis`) |

---

## §4 — Mural de Oração (`/oracao`)

Referência: `tela-mural-oracao.jpeg`.

### 4.1 Feed

`AppBar` com campo de busca embutido (ou `SearchAnchor` do M3):

- `TextField` com `Icons.search`, `hintText: "Buscar por título..."`;
- **debounce de 400 ms** antes de disparar `search_prayers`
  (mesmo padrão do `food_search_screen.dart` do CalorieMate, com
  `Timer? _debounce` e `_debounce?.cancel()` no `dispose`);
- com o campo vazio, exibe o feed cronológico; com texto, o resultado da busca;
- `IconButton` de limpar quando há texto.

**Composer inline** no topo do feed (como no mockup: "Compartilhe algo..."):
`Row` com avatar + campo falso (`InkWell` com aparência de `TextField`) que
navega para `/oracao/novo`. Não faça composição inline real — título + corpo +
opção anônimo pedem uma tela dedicada.

**Cartão do post** (`PrayerCard`):

```
┌────────────────────────────────────────┐
│ ⬤  Maria Silva · 17 h              ⋯  │
│                                        │
│ Cura da minha mãe                      │  ← título, titleMedium bold
│ Ela está internada desde terça...      │  ← corpo, 3 linhas + "ver mais"
│                                        │
│ 🙏 12 orando       💬 3 comentários    │  ← ✅ Respondido (se answered_at)
└────────────────────────────────────────┘
```

- Autor anônimo: avatar genérico + "Anônimo".
- `timeago` em pt-BR.
- **Botão "Estou orando"**: toggle otimista. `is_praying` vem da view
  `prayer_feed`; a PK composta de `prayer_interactions` impede duplicidade, mas
  **desabilite o botão durante o request** para evitar duplo toque.
- Badge "Respondido" (verde) quando `answered_at != null`.
- `PopupMenuButton` (⋯): Editar / Excluir se autor ou admin; "Marcar como
  respondido" se autor; "Denunciar" — omitir na v1 (sem moderação assíncrona).
- Toque → `/oracao/:id`.

`ListView.builder` com paginação: carregar 20 e buscar mais ao chegar a ~80% do
scroll. Com poucos posts isso é irrelevante, mas evita retrabalho depois.

### 4.2 Detalhe (`/oracao/:id`)

Post completo + contador de orações + lista de comentários (avatar, nome,
`timeago`, corpo) + campo de comentário fixo no rodapé
(`bottomNavigationBar` com `SafeArea` + `TextField` + botão enviar).

Se `answered_at != null`, um cartão destacado no topo com o `answer_note`.

### 4.3 Composer (`/oracao/novo`, `/oracao/:id/editar`)

`Form` com:
- **Título** (obrigatório, 3–120 chars) — é a chave da busca; deixe isso
  explícito no `helperText`: *"Use um título curto e específico — é por ele que
  o pedido será encontrado depois."*
- **Corpo** (obrigatório, até 4000 chars, `maxLines: null`, contador).
- `SwitchListTile` **"Publicar como anônimo"**.
- `FilledButton` "Publicar".

Offline: salva local + `outbox`, aparece no feed com indicador "enviando…".

### Permissões

| Ação | Quem |
|---|---|
| Ver feed, buscar, comentar, "estou orando" | obreiro aprovado |
| Criar post | obreiro aprovado |
| Editar/excluir post ou comentário | autor, ou admin |
| Marcar como respondido | autor, ou admin |

---

## §5 — Autenticação

### 5.1 Splash (`/`)

Logo centralizada + `CircularProgressIndicator`. Resolve a sessão e redireciona.
Nunca fica visível mais de ~1 s.

### 5.2 Login (`/login`)

Logo, e-mail, senha (com `Icons.visibility` toggle), `FilledButton "Entrar"`,
`TextButton "Esqueci minha senha"`, divisor, `TextButton "Tenho um convite —
criar conta"`.

Erros mapeados para mensagens em pt-BR: credenciais inválidas, e-mail não
confirmado (com botão "Reenviar confirmação"), sem conexão. **Nunca** mostrar
`AuthException` cru.

### 5.3 Cadastro (`/cadastro`)

Campos: nome completo, e-mail, telefone (opcional), senha, confirmar senha,
**código de convite** (`textCapitalization: characters`).

Validação: senha ≥ 8 caracteres, confirmação igual, código não vazio.

Fluxo (tratar os dois caminhos, ver `PLANO.md` Fase 3):
1. `signUp` → se retornar sessão, chama `redeem_invite` na hora → `/inicio`.
2. Se exigir confirmação de e-mail (o caso de produção), guarda o convite em
   `flutter_secure_storage` e troca o formulário pela tela de **código de 6
   dígitos**. O `verifyEmailOtp` confirma o e-mail, resgata o convite na mesma
   chamada e o redirect leva para `/inicio`. Botão "Reenviar código" para quem
   perder o prazo.

> A confirmação é por **código**, não por link: o link dependia do deep link
> `br.com.veredas.app://` e do mesmo aparelho do cadastro (PKCE), então abrir o
> e-mail no computador travava a pessoa. Ver `supabase/README.md` §6-A.

Erros da RPC em pt-BR:

| Código | Mensagem |
|---|---|
| `INVITE_NOT_FOUND` | "Código de convite não encontrado. Confira com a liderança." |
| `INVITE_EXPIRED` | "Este convite expirou." |
| `INVITE_EXHAUSTED` | "Este convite já foi utilizado o número máximo de vezes." |
| `INVITE_REVOKED` | "Este convite foi cancelado." |

### 5.4 Aguardando aprovação (`/aguardando`)

Ícone + "Sua conta está aguardando aprovação da liderança." + botão "Verificar
novamente" (refaz o fetch do perfil) + "Tenho um código de convite" (resgata
agora) + "Sair".

Tela **inescapável** enquanto `is_approved == false` — o `redirect` do router
garante isso mesmo com deep link.

### 5.5 Recuperar senha (`/esqueci-senha`)

E-mail + `resetPasswordForEmail`, com deep link de retorno
(`br.com.veredas.app://login-callback/`). Configurar
`CFBundleURLTypes` (iOS) e `intent-filter` (Android).

### 5.6 Perfil (`/perfil`)

Avatar (toque → `image_picker` → bucket `avatars`), nome, e-mail, telefone, bio,
`Chip` do papel ("Admin" / "Obreiro"), lista das escalas que gerencia, versão do
app (`package_info_plus`), botão "Editar perfil", botão "Sair" (com
`ConfirmDialog`), e "Excluir minha conta" (LGPD — abre solicitação ao admin ou
Edge Function).

---

## §6 — Administração (`/admin`)

Acessível só para admin (guard no router **e** botão oculto no AppBar).

`ListView` de `ListTile` navegando para:

### 6.1 Membros (`/admin/membros`)

Lista de perfis com busca por nome. Cada item: avatar, nome, e-mail, `Chip` do
papel, badge "Pendente" se `is_approved == false`.

Ações por item (`PopupMenuButton`): Aprovar / Revogar acesso / Promover a admin /
Rebaixar a obreiro / Remover (soft delete).

Seção "Pendentes de aprovação" fixa no topo quando houver — é a ação mais
urgente do admin.

> **Proteção:** impedir que o admin revogue ou rebaixe a si mesmo se for o
> **único** admin ativo. Isso trancaria a base fora da administração. Validar no
> cliente e, idealmente, com um trigger no banco.

### 6.2 Convites (`/admin/convites`)

Lista de convites com código, papel, `uses/max_uses`, validade, status
(ativo/expirado/esgotado/revogado).

FAB → diálogo de criação: papel, número de usos, validade
(`showDatePicker`, opcional), observação. Código gerado automaticamente
(6 caracteres alfanuméricos maiúsculos, sem `0/O/1/I` para evitar confusão ao
ditar por telefone) e editável.

Ações: copiar código, compartilhar (`share_plus` — adicionar a dependência se
usar), revogar.

### 6.3 Responsáveis por escala (`/admin/responsaveis`)

Um `ExpansionTile` por `scale_type`, listando os responsáveis atuais com botão de
remover, e "Adicionar responsável" abrindo um seletor de obreiros aprovados.

Esta tela é o que materializa o requisito *"o obreiro que tem a
responsabilidade da escala do Servir ao Todo será a única pessoa a poder
editá-la"*.

### 6.4 Escalas da base (`/admin/escalas`)

A lista de `scale_types` — ou seja, as abas da tela Escalas — com **todas** as
escalas, inclusive as ocultas (`is_active = false`), que não aparecem na tela
Escalas e só podem voltar a existir aqui.

- **Reordenar**: arrastar pela alça (`ReorderableList` de
  `package:flutter/widgets.dart`, não o `ReorderableListView` do Material).
  Cada linha que mudou de posição vira uma escrita de `ordering`.
- **Criar** (`/admin/escalas/nova`) e **editar** (`/admin/escalas/editar?id=`):
  nome, período (semanal/mensal/pontual), áreas (separadas por vírgula) e
  "Visível na tela Escalas". O `slug` **não** aparece no formulário: é derivado
  do nome na criação e imutável depois, porque é a chave estável do tipo.
- **Excluir**: soft delete, com aviso de que as escalas já montadas deixam de
  aparecer. Para só tirar a aba do caminho, o caminho é desativar.

Escritas pela outbox (não por RPC, como as outras ações de admin): a barra de
abas sai deste mesmo cache, então o efeito é imediato e sobrevive a estar sem
sinal. Quem garante a permissão é a policy `scale_types_admin_write`.

> A tela Escalas guarda a aba aberta **por id**, não por posição — senão uma
> reordenação vinda do sync trocaria a escala na tela de quem está olhando.

### 6.5 Dados da base (`/admin/base`)

Edição de `base_info` (chave/valor, reordenável) e `social_links` (plataforma,
URL, ativo).

---

## §7 — Estados vazios e mensagens

Centralizar no `.arb`. Textos sugeridos (pt-BR):

| Contexto | Texto |
|---|---|
| Início sem avisos | "Nenhum aviso por aqui ainda." |
| Agenda sem eventos no dia | "Nenhum evento neste dia." |
| Cronograma vazio | "O cronograma semanal ainda não foi cadastrado." |
| Escala vazia | "A escala desta semana ainda não foi montada." |
| Mural vazio | "Seja o primeiro a compartilhar um pedido de oração." |
| Busca sem resultado | "Nenhum pedido encontrado para \"{termo}\"." |
| Offline | "Sem conexão — mostrando dados salvos." |
| Fila pendente | "{n} alteração(ões) aguardando envio." |
| Erro genérico | "Algo deu errado. Tente novamente." |
| Sem permissão | "Você não tem permissão para esta ação." |

Use plural ICU no `.arb` (`{n, plural, =1{...} other{...}}`) — **não** repita o
`"(s)"` textual do CalorieMate.

---

## §8 — Acessibilidade e polimento

- Área de toque mínima 48×48 dp em todos os `IconButton`.
- `tooltip` em todo `IconButton` e `FloatingActionButton`.
- `Semantics`/`semanticLabel` nas células da grade do cronograma e nos avatares.
- Contraste: garantir que as cores de categoria tenham `onColor` legível nos dois
  temas. Verificar com `flutter run --dart-define=...` nos modos claro e escuro.
- Testar com fonte do sistema em 200% (`textScaleFactor`) — a grade do
  cronograma é o ponto que mais quebra; permitir truncamento com `ellipsis` em
  vez de overflow.
