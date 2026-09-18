# Backend Supabase — passo a passo

Roteiro da **Fase 1** do `docs/PLANO.md`. Siga na ordem; cada passo depende do
anterior.

Ao final, a segurança do app está resolvida: as permissões ("só o responsável
pela escala de Servir ao Todo pode editá-la") ficam garantidas pelo banco, não
pela interface. Um app modificado não consegue burlá-las.

---

## Passo 1 — Criar o projeto

1. Acesse <https://supabase.com> e entre com GitHub ou e-mail.
2. **New project**:
   - **Name**: `veredas`
   - **Database Password**: gere uma senha forte e **guarde num gerenciador de
     senhas**. Ela não é a senha do app — é o acesso direto ao Postgres. Você
     vai precisar dela se algum dia usar `psql` ou `pg_dump`.
   - **Region**: `South America (São Paulo)` — menor latência para Joinville.
   - **Plan**: Free.
3. Aguarde ~2 minutos até o projeto provisionar.

> **Sobre o free tier:** 500 MB de banco e 1 GB de Storage. Para ~30 obreiros
> isso não será excedido. O único gatilho de pausa é inatividade (7 dias sem
> requisição); um app em uso diário não pausa.

---

## Passo 2 — Guardar as credenciais

No painel: **Project Settings → API**. Copie:

| Campo no painel | Onde usar |
|---|---|
| **Project URL** | `SUPABASE_URL` |
| **anon public** | `SUPABASE_ANON_KEY` |
| **service_role** | **NÃO USE.** Nunca entra no app, em nenhuma circunstância. |

Crie o arquivo `env/dev.json` na raiz do projeto (já está no `.gitignore`):

```json
{
  "SUPABASE_URL": "https://xxxxxxxx.supabase.co",
  "SUPABASE_ANON_KEY": "eyJhbGci..."
}
```

> A `anon key` é **pública por design** — ela vai embarcada no APK e qualquer
> pessoa pode extraí-la. A proteção dos dados é o RLS, não o sigilo da chave.
> Mesmo assim não a commite: rotacioná-la depois de vazar no histórico do git é
> trabalhoso.
>
> A `service_role`, ao contrário, **ignora todo o RLS**. Se ela vazar, todos os
> dados da base estão comprometidos.

---

## Passo 3 — Conferir o schema das extensões

Antes de aplicar as migrations, rode isto no **SQL Editor**:

```sql
select e.extname, n.nspname as schema
  from pg_extension e join pg_namespace n on n.oid = e.extnamespace
 where e.extname in ('pg_trgm', 'unaccent');
```

- Se o resultado for **`extensions`** (ou vazio): siga normalmente. As migrations
  já usam esse prefixo.
- Se for **`public`**: rode `alter extension unaccent set schema extensions;` e
  o equivalente para `pg_trgm`. Alternativamente, remova o prefixo
  `extensions.` das migrations `0300` e `0400`.

Um prefixo errado aqui gera `function ... does not exist` na criação do índice
trigram, e é chato de diagnosticar depois.

---

## Passo 4 — Aplicar as migrations

**SQL Editor → New query.** Cole o conteúdo de cada arquivo e execute
**um por vez, nesta ordem**. Confirme "Success" antes de passar ao próximo.

| # | Arquivo | O que cria |
|---|---|---|
| 1 | `migrations/20260803000100_extensions_and_types.sql` | extensões `pg_trgm`/`unaccent`, enum `app_role` |
| 2 | `migrations/20260803000200_profiles_and_invites.sql` | `profiles`, `invites`, trigger de criação de perfil |
| 3 | `migrations/20260803000300_helper_functions.sql` | `is_approved()`, `is_admin()`, `norm_text()` |
| 4 | `migrations/20260803000400_domain_tables.sql` | as 11 tabelas de domínio e seus índices |
| 5 | `migrations/20260803000450_manages_scale.sql` | `manages_scale()` — depende da tabela do passo 4 |
| 6 | `migrations/20260803000500_views_and_rpcs.sql` | view `prayer_feed`, `search_prayers()`, `redeem_invite()` |
| 7 | `migrations/20260803000600_rls_policies.sql` | **RLS e todas as policies** |
| 8 | `migrations/20260803000700_storage.sql` | buckets `avatars` e `event-covers` + policies |
| 9 | `migrations/20260803000800_triggers.sql` | `updated_at` automático, bloqueio de escalada de privilégio |

> **Por que a `0450` existe.** A função `manages_scale` referencia a tabela
> `scale_managers`, criada na `0400`. Com `check_function_bodies = on` (o padrão
> no Supabase), o corpo de uma função `language sql` é validado já no
> `CREATE FUNCTION` — criá-la antes da tabela falha com
> `relation "public.scale_managers" does not exist`. Por isso ela ficou separada
> das outras funções de permissão.

Depois de aplicar a `0600`, confirme que nenhuma tabela ficou sem RLS:

```sql
select c.relname from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;
```

**Deve retornar 0 linhas.** Qualquer tabela listada aqui está pública para a
`anon key`, ou seja, para qualquer pessoa com o APK.

### Migrations incrementais (aplicar depois das 9 acima)

A lista acima é o schema inicial. O que veio depois entra na mesma ordem
cronológica do nome do arquivo — **um ambiente novo precisa destas também**, e
sem elas o app compila mas quebra em funcionalidades específicas:

| # | Arquivo | O que adiciona | Sem ela |
|---|---|---|---|
| 10 | `20260804000100_admin_rpcs.sql` | RPCs de administração (gerar convite etc.) | Telas de admin falham |
| 11 | `20260806000100_color_index.sql` | `color_index` em eventos e cronograma | Cor escolhida não salva |
| 12 | `20260807000100_delete_own_account.sql` | RPC `delete_own_account` | Exclusão de conta falha (exigência da Play) |
| 13 | `20260828000100_documents.sql` | tabela `documents` (aba Arquivos) | **O sync inteiro passa a falhar** — ver abaixo |
| 14 | `20260917000100_scale_teams_and_lunch.sql` | equipe na atribuição (`member_ids`/`member_names`), escala de Almoço, `delete_own_account` ciente de equipes | Salvar escala em grupo falha (coluna inexistente); aba Almoço não aparece |
| 15 | `20260917000200_fix_self_delete_privilege.sql` | trigger `protect_profile_privileges` reconhece a flag de `delete_own_account` | **Obreiro não consegue excluir a própria conta** (`FORBIDDEN_PRIVILEGE_CHANGE`) — exigência da Play |

> **A 14 também vai antes do app.** Ela não derruba o pull (o app tolera a
> linha sem as colunas de equipe), mas enquanto ela não estiver aplicada toda
> tentativa de salvar uma escala volta com erro de coluna inexistente.

> **A 13 precisa ser aplicada ANTES de distribuir a versão do app que tem a aba
> Arquivos.** O `SyncService.pullAll()` para no primeiro erro, então uma tabela
> que o app espera e o banco não tem derruba o ciclo de sync e deixa o banner
> vermelho de erro permanente na tela. A ordem correta é: migration primeiro,
> app depois.

Para reconferir tudo sem tocar no Supabase, o harness local aplica as migrations
numa base limpa e roda as asserções de RLS:

```bash
./supabase/local_test/run.sh
```

---

## Passo 5 — Aplicar os seeds

Execute `seed.sql`. Ele cria os 5 tipos de escala, os itens de "Dados da Base",
as redes sociais, um cronograma de exemplo e o convite `VEREDAS2026`.

O arquivo é **reaplicável**: rodar duas vezes não duplica nada.

Os valores `TODO` aparecem literalmente na tela Início do app. Troque-os pelos
dados reais quando os tiver:

```sql
update public.base_info set value = 'Rua Exemplo, 123 - Joinville/SC' where key = 'endereco';
update public.base_info set value = '89200-000'                       where key = 'cep';
update public.base_info set value = '(47) 99999-9999'                 where key = 'telefone';
update public.base_info set value = '00.000.000/0001-00'              where key = 'cnpj';

update public.social_links set url = 'https://instagram.com/veredasjocum' where platform = 'instagram';
```

---

## Passo 6 — Configurar o Auth

**Authentication → Sign In / Providers → Email:**

- **Confirm email**: **habilitado**.
- **Enable email provider**: habilitado.
- Desabilite qualquer provedor anônimo.

**Authentication → URL Configuration:**

- **Site URL**: `br.com.veredas.app://login-callback/`
- **Redirect URLs**: adicione `br.com.veredas.app://login-callback/`

Isso é o que faz o link de recuperação de senha voltar para o app. **Confira que
o Site URL não ficou no `http://localhost:3000`**, que é o valor padrão de um
projeto novo — com ele, o link do e-mail leva a uma página que não existe.

### Passo 6-A — Confirmação de cadastro por código, não por link

**Authentication → Emails → template "Confirm signup":** troque o botão com
`{{ .ConfirmationURL }}` por `{{ .Token }}`, que renderiza um código de 6
dígitos.

Exemplo de corpo:

```html
<h2>Confirme seu e-mail</h2>
<p>Seu código de confirmação é:</p>
<p style="font-size:32px;font-weight:bold;letter-spacing:4px">{{ .Token }}</p>
<p>Digite este código no app para concluir seu cadastro.</p>
```

**Por que não o link.** O link de confirmação aponta para o deep link
`br.com.veredas.app://`, que só resolve num celular com o app instalado — e o
fluxo PKCE do `supabase_flutter` ainda amarra a confirmação ao **mesmo aparelho**
onde a pessoa se cadastrou. Quem abrir o e-mail no computador, ou noutro
celular, trava sem saída. O código digitado não tem nenhum desses vínculos.

De quebra, isso fecha um buraco do fluxo antigo: confirmando pelo link, a sessão
nascia dentro do `supabase_flutter` sem passar pelo `signIn`, e o convite
guardado no cadastro nunca era resgatado — o obreiro caía no `/aguardando` tendo
que digitar o código de convite de novo. O `verifyEmailOtp` resgata o convite na
mesma chamada que confirma o e-mail.

O tempo de validade do código é o **Email OTP Expiration** em
**Authentication → Providers → Email** (padrão 1 hora; 15 minutos é suficiente e
mais seguro). A tela de confirmação tem "Reenviar código" para quem passar do
prazo.

### SMTP próprio — não é opcional

O SMTP embutido do Supabase envia **2 e-mails por hora** (valor oficial, não
estimativa) e existe apenas para desenvolvimento. Com 30 obreiros se cadastrando,
os e-mails de confirmação não chegam e o obreiro fica preso fora do app. É um
bloqueio prático real, não um detalhe de polimento.

Provedor escolhido: **Brevo** (300 e-mails/dia no free tier).

#### 6.1 No Brevo — verificar o remetente

Não se pode enviar de um endereço arbitrário. Em **Settings → Senders, Domains &
Dedicated IPs**:

- **Sem domínio próprio**: aba *Senders* → *Add a sender*. Cadastre um e-mail
  real (ex.: o Gmail da base), confirme pelo link que chega nele. Funciona, mas a
  entrega é pior — Gmail e Outlook tendem a marcar como spam mail não
  autenticado.
- **Com domínio próprio** (recomendado): aba *Domains* → *Add a domain* e
  publique os registros DKIM/DMARC no DNS. É o que mantém os e-mails fora do
  spam. Se a base tiver um domínio, use este caminho.

#### 6.2 No Brevo — pegar as credenciais SMTP

**Settings → SMTP & API → aba SMTP.**

| Campo | Valor |
|---|---|
| SMTP server | `smtp-relay.brevo.com` |
| Port | `587` |
| Login | o valor do campo **Login**, no formato `xxxxxxx@smtp-brevo.com` |
| Password | uma **SMTP key** — clique em *Generate a new SMTP key* |

Duas armadilhas que causam a maioria dos erros `535 Authentication failed`:

1. **O login NÃO é o e-mail da sua conta Brevo.** É o endereço
   `...@smtp-brevo.com` mostrado no campo *Login*. Também não é
   `smtp-relay.brevo.com` — esse é o host.
2. **A senha é a SMTP key, não a senha da conta e nem uma API key.** A key é
   exibida **uma única vez**, na criação. Salve num gerenciador de senhas na
   hora; se perder, gere outra.

#### 6.3 No Supabase — configurar

**Authentication → Emails → SMTP Settings**, habilite *Enable Custom SMTP*:

| Campo | Valor |
|---|---|
| Sender email | o remetente verificado no passo 6.1 |
| Sender name | `Base Veredas` |
| Host | `smtp-relay.brevo.com` |
| Port | `587` |
| Username | o login `...@smtp-brevo.com` |
| Password | a SMTP key |

#### 6.4 Levantar o rate limit do Supabase (passo esquecido)

Ao habilitar SMTP próprio, o Supabase **impõe automaticamente 30 e-mails/hora**
para proteger a reputação do serviço novo. Isso é do Supabase, não do Brevo —
configurar o Brevo sozinho não resolve.

Em **Authentication → Rate Limits**, suba *Rate limit for sending emails* para
algo como **100/hora**.

Com 30 obreiros, 30/hora parece suficiente, mas não é no dia do lançamento: cada
pessoa gera pelo menos um e-mail de confirmação, mais reenvios de quem não achou
a mensagem, mais recuperações de senha de quem errou. Bater no limite nesse dia
significa obreiro travado na tela de confirmação — exatamente o problema que o
SMTP próprio existe para evitar.

#### 6.5 Testar antes de confiar

Crie um usuário de teste pelo painel (**Authentication → Users → Add user**, sem
marcar *Auto Confirm*) e confirme que o e-mail chega. **Olhe também a caixa de
spam** — se caiu lá, falta autenticar o domínio (passo 6.1).

No Brevo, **Transactional → Logs** mostra cada tentativa de envio com o motivo da
falha. É o primeiro lugar a olhar quando um e-mail não chega.

---

### 6.6 Rede de segurança: confirmar e-mail manualmente

Se o e-mail de confirmação de algum obreiro não chegar (spam, caixa cheia,
endereço digitado errado), **o admin confirma na mão**:

**Authentication → Users** → clique no usuário → confirmar o e-mail.

Para ~20 pessoas isso é perfeitamente viável, e é o que torna a exigência de
confirmação de e-mail um risco baixo: ninguém fica travado permanentemente
esperando uma mensagem que não vem.

### 6.7 Estado atual e plano B

O domínio `jocum.org.br` é **Google Workspace** e a base **não tem acesso ao
DNS** dele. Consequência para o envio via Brevo:

| Checagem | Resultado | Por quê |
|---|---|---|
| SPF | *softfail* | O SPF do domínio é `include:_spf.google.com ~all` — autoriza só o Google, não o Brevo |
| DKIM | não alinhado | O Brevo assina com o domínio dele |
| DMARC | falha, **sem punição** | A política do domínio é `p=none`, que instrui os servidores a não rejeitar nem quarentenar |

Ou seja: **os e-mails são entregues**, com risco de cair no spam de vez em
quando. Aceito conscientemente pelo solicitante (os obreiros são avisados).

**Plano B, se a entrega incomodar:** enviar pelo SMTP do próprio Google, em vez
do Brevo. O `jocum.org.br` já tem SPF **e** DKIM configurados para o Google
(`google._domainkey` existe), então SPF, DKIM e DMARC passariam **alinhados, sem
tocar em nenhum registro DNS**:

| Campo | Valor |
|---|---|
| Host | `smtp.gmail.com` |
| Port | `587` |
| Username | `veredas@jocum.org.br` |
| Password | uma **App Password** do Google (exige 2FA na conta) |

Ressalva: se o admin do Workspace da JOCUM exigir apenas OAuth, as senhas de app
ficam indisponíveis e este plano B não funciona — aí o Brevo permanece.

---

## Passo 7 — Criar o admin

O `role` não pode ser definido no cadastro (senão qualquer um se promoveria).
O primeiro admin é promovido manualmente:

1. Crie sua conta em **Authentication → Users → Add user**, marcando
   **Auto Confirm User**. Isso dispensa o e-mail de confirmação — útil para não
   depender do SMTP estar pronto.
   (Alternativa: cadastrar pelo app com o código `VEREDAS2026`.)
2. No SQL Editor:

```sql
update public.profiles
   set role = 'admin', is_approved = true
 where email = 'seu-email@exemplo.com';
```

Confirme:

```sql
select id, email, full_name, role, is_approved from public.profiles;
```

A partir daí, novos admins são promovidos pela tela `/admin/membros` do app.

---

## Passo 8 — Validar o RLS (o passo que não pode ser pulado)

> **O schema já foi pré-validado.** Antes de você aplicar qualquer coisa, todas
> as migrations, o seed e o modelo de permissões foram rodados num Postgres 17
> local com 47 asserções — todas passando. Ver `local_test/README.md`; para
> reverificar depois de mudar uma policy:
> ```bash
> ./supabase/local_test/run.sh
> ```
> Isso já pegou três bugs que travariam o projeto, incluindo um que tornava
> **impossível criar o primeiro admin**.

Ainda assim, vale validar no banco real — o harness não cobre o que só existe no
Supabase gerenciado. Abra `validacao_rls.sql` e siga as instruções no topo do
arquivo: crie 3 contas de teste, substitua os UUIDs e execute os blocos.

Resumo do que cada bloco prova:

| Bloco | Prova |
|---|---|
| 1 | Usuário não aprovado não vê nada além do próprio perfil |
| 2 | Obreiro que não gerencia escala não consegue inserir atribuição |
| 3 | Responsável escreve na **sua** escala e **falha** nas outras |
| 4 | Obreiro não consegue se promover a admin |
| 5 | ...mas o resgate de convite funciona |
| 6 | Nenhuma tabela ficou sem RLS |

**Os blocos 4 e 5 são complementares e ambos precisam passar.** Se apenas um
passar, a flag transacional `app.redeeming_invite` está errada:

- só o 4 passa → o trigger está bloqueando o resgate; ninguém consegue se cadastrar;
- só o 5 passa → a flag está vazando; qualquer obreiro pode virar admin.

Se algum bloco divergir do esperado, **corrija a policy antes de seguir para o
app**. Depois de ter usuários reais, mexer em RLS é muito mais arriscado.

---

## Passo 9 — Storage

A migration `0700` já cria os buckets. Confirme em **Storage** que existem
`avatars` e `event-covers`, ambos com **Public: false**.

Se preferir criá-los pelo painel, desmarque "Public bucket" nos dois.

---

## Apêndice — usando o Supabase CLI (opcional)

Se preferir versionar as migrations em vez de colar SQL no painel:

```bash
npm install -g supabase          # ou: brew install supabase/tap/supabase
supabase login
supabase link --project-ref <ref-do-projeto>
supabase db push                 # aplica supabase/migrations/ na ordem
```

O CLI aplica os arquivos de `supabase/migrations/` em ordem alfabética — que é
exatamente a ordem numérica dos prefixos. Ele também mantém uma tabela de
controle, então reaplicar é seguro.

Para desenvolver offline com Postgres local (exige Docker):

```bash
supabase start                   # sobe Postgres + Auth + Storage locais
supabase db reset                # aplica migrations + seed.sql do zero
```

`supabase start` imprime uma `API URL` e uma `anon key` locais — use-as num
`env/local.json` para rodar o app contra o banco local.
