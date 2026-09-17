-- =========================================================================
-- Escalas em equipe + escala de Almoço
--
-- Pedido da base: uma atribuição pode ter MAIS DE UMA pessoa (um grupo de
-- quatro no almoço, por exemplo) e, opcionalmente, um responsável geral
-- sobre esse grupo.
--
-- -------------------------------------------------------------------------
-- Por que arrays na própria linha, e não uma tabela `scale_assignment_members`
-- -------------------------------------------------------------------------
--
-- A tabela filha é o modelo relacional "certo", mas custa caro exatamente
-- onde este app é frágil: uma equipe de quatro viraria cinco linhas em duas
-- tabelas, ou seja, cinco entradas na outbox para uma única edição feita
-- offline. Se três subissem e duas falhassem, a escala ficaria pela metade no
-- servidor — e o rollback do cache otimista, que hoje é "restaura a linha
-- anterior", teria de virar uma transação distribuída no cliente. Além disso
-- exigiria uma entidade de sync nova, com suas policies e seu modo de pull.
--
-- Com arrays, uma atribuição continua sendo UMA linha: a escrita é atômica,
-- o rollback continua trivial e nada muda no motor de sync. O preço é não ter
-- FK nos ids da equipe (o Postgres não faz FK por elemento de array); quem
-- cobre isso é `delete_own_account()`, redefinida no fim deste arquivo, que
-- tira o uid das equipes ao apagar a conta. O app também ignora id que não
-- resolve para um perfil do cache.
--
-- -------------------------------------------------------------------------
-- O que `assignee_id` / `assignee_name` passam a significar
-- -------------------------------------------------------------------------
--
-- Viram o **responsável geral** (opcional) da atribuição; a equipe mora em
-- `member_ids` / `member_names`.
--
-- As colunas não foram renomeadas nem removidas de propósito: o app instalado
-- hoje lê `assignee_name` para desenhar a escala, e uma coluna que some
-- derruba esses aparelhos até que todo mundo atualize. Com o nome preservado,
-- a versão antiga continua exibindo o responsável geral quando há um — degrada
-- em vez de quebrar. Renomear fica para quando não houver mais cliente antigo
-- em campo.
-- =========================================================================

alter table public.scale_assignments
  add column if not exists member_ids   uuid[] not null default '{}',
  add column if not exists member_names text[] not null default '{}';

comment on column public.scale_assignments.member_ids is
  'Equipe escalada, para quem tem conta no app. Sem FK: o Postgres não faz '
  'FK por elemento de array — delete_own_account() é quem remove o uid daqui.';
comment on column public.scale_assignments.member_names is
  'Equipe escalada, para quem NÃO tem conta no app (nome digitado à mão).';
comment on column public.scale_assignments.assignee_id is
  'Responsável geral do grupo (opcional). A equipe está em member_ids.';
comment on column public.scale_assignments.assignee_name is
  'Responsável geral sem conta no app (opcional).';

-- A regra continua sendo "a linha precisa apontar para alguém", só que agora
-- a equipe também conta. Sem trocar o CHECK, uma atribuição de quatro pessoas
-- sem responsável geral seria recusada.
alter table public.scale_assignments
  drop constraint if exists assignment_has_assignee;

alter table public.scale_assignments
  add constraint assignment_has_someone check (
    assignee_id is not null
    or nullif(trim(assignee_name), '') is not null
    or cardinality(member_ids) > 0
    or cardinality(member_names) > 0
  );

-- "Em quais escalas eu estou?" agora também pergunta pela equipe, e `@>` em
-- array só usa índice se ele for GIN. O índice btree de assignee_id continua
-- servindo à busca pelo responsável geral.
create index if not exists scale_assignments_members_idx
  on public.scale_assignments using gin (member_ids);

-- -------------------------------------------------------------------------
-- Escala de Almoço
-- -------------------------------------------------------------------------
--
-- Sem `slots`: o pedido é um grupo por dia, não sub-áreas. A tela escolhe o
-- formato a partir daqui — array vazio renderiza a lista por dia, que é onde
-- a equipe e o responsável geral aparecem inteiros. Se um dia a base quiser
-- dividir em "Preparo"/"Louça", como no Café da Manhã, é um UPDATE em `slots`,
-- não um release.
insert into public.scale_types (slug, name, description, icon, cadence, slots, ordering)
values
  ('almoco', 'Almoço',
   'Preparo do almoço da base.', 'restaurant', 'weekly',
   array[]::text[], 6)
on conflict (slug) do nothing;

-- -------------------------------------------------------------------------
-- delete_own_account() — agora a pessoa também sai das equipes
-- -------------------------------------------------------------------------
--
-- Só a parte de escalas muda; o resto é idêntico à migration 0807. A mudança
-- de fundo: apagar a conta não pode mais apagar a escala dos outros. Antes,
-- uma atribuição era sempre de uma pessoa só, então derrubar a linha inteira
-- era o certo. Hoje, se quem sai era um dos quatro do almoço, a linha fica —
-- só o nome dela sai.
create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_active_admins integer;
  v_is_admin boolean;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select (role = 'admin' and is_approved and deleted_at is null)
    into v_is_admin
    from public.profiles
   where id = v_uid;

  if v_is_admin is null then
    raise exception 'USER_NOT_FOUND';
  end if;

  -- Mesma proteção de set_role e soft_delete_user: a base não pode ficar sem
  -- ninguém capaz de aprovar novos obreiros. O último admin passa o bastão
  -- antes de sair.
  if v_is_admin then
    select count(*) into v_active_admins
      from public.profiles
     where role = 'admin' and is_approved and deleted_at is null;

    if v_active_admins <= 1 then
      raise exception 'CANNOT_DELETE_LAST_ADMIN';
    end if;
  end if;

  -- Escalas FUTURAS em que a pessoa era a única escalada: tombstone, como
  -- antes. A condição extra é o que impede derrubar a escala de um grupo.
  update public.scale_assignments
     set deleted_at = now(),
         updated_at = now()
   where starts_on >= current_date
     and deleted_at is null
     and (assignee_id = v_uid or member_ids @> array[v_uid])
     and cardinality(array_remove(member_ids, v_uid)) = 0
     and cardinality(member_names) = 0
     and (assignee_id is null or assignee_id = v_uid);

  -- Escalas FUTURAS que sobraram: têm mais gente, então a pessoa apenas sai
  -- da equipe (e deixa de ser responsável geral). As linhas do tombstone
  -- acima já não entram aqui, porque `deleted_at` deixou de ser nulo.
  update public.scale_assignments
     set member_ids = array_remove(member_ids, v_uid),
         assignee_id = case when assignee_id = v_uid then null else assignee_id end,
         updated_at = now()
   where starts_on >= current_date
     and deleted_at is null
     and (assignee_id = v_uid or member_ids @> array[v_uid]);

  -- Escalas PASSADAS ficam como registro histórico, sem identificar a pessoa:
  -- o id sai e entra o nome "Removido" no lugar — numa única instrução, senão
  -- o CHECK `assignment_has_someone` reprovaria no meio. Todas as expressões
  -- do SET enxergam a linha ANTES do update, que é o que faz os `case`
  -- abaixo decidirem pelo valor antigo.
  update public.scale_assignments
     set member_ids = array_remove(member_ids, v_uid),
         -- `array_append` e não `|| 'Removido'`: com text[] do lado esquerdo,
         -- o Postgres resolve o literal sem tipo como array e estoura com
         -- "malformed array literal".
         member_names = case when member_ids @> array[v_uid]
                             then array_append(member_names, 'Removido')
                             else member_names end,
         assignee_id = case when assignee_id = v_uid then null else assignee_id end,
         assignee_name = case when assignee_id = v_uid
                              then 'Removido'
                              else assignee_name end,
         updated_at = now()
   where starts_on < current_date
     and deleted_at is null
     and (assignee_id = v_uid or member_ids @> array[v_uid]);

  -- Conteúdo autoral no mural.
  update public.prayer_posts
     set deleted_at = now(), updated_at = now()
   where author_id = v_uid and deleted_at is null;

  update public.prayer_comments
     set deleted_at = now(), updated_at = now()
   where author_id = v_uid and deleted_at is null;

  delete from public.prayer_interactions where user_id = v_uid;

  -- Convites que gerou e ninguém usou. Um convite já resgatado fica: apagá-lo
  -- destruiria o rastro de como outra pessoa entrou na base.
  update public.invites
     set deleted_at = now(), updated_at = now()
   where created_by = v_uid
     and uses = 0
     and deleted_at is null;

  -- Deixa de ser responsável por qualquer escala.
  delete from public.scale_managers where user_id = v_uid;

  -- Libera o trigger protect_profile_privileges para esta transação. Sem
  -- isto, o UPDATE abaixo (que zera `is_approved`) é recusado com
  -- FORBIDDEN_PRIVILEGE_CHANGE para todo mundo que não é admin — ou seja, a
  -- exclusão de conta **nunca funcionou** para um obreiro comum, que é
  -- justamente quem ela existe para atender (exigência da Google Play). Ver a
  -- migration 20260917000200, que ensina o trigger a reconhecer a flag.
  --
  -- `is_local = true` faz a permissão morrer no fim da transação, igual à de
  -- `redeem_invite`: ela não vaza para outras operações da mesma conexão.
  perform set_config('app.deleting_own_account', 'on', true);

  -- O perfil por último: sobrescreve o que identifica a pessoa e marca o
  -- tombstone, que é o que os outros aparelhos vão receber no próximo pull.
  update public.profiles
     set full_name = 'Removido',
         email = null,
         phone = null,
         avatar_url = null,
         bio = null,
         is_approved = false,
         deleted_at = now(),
         updated_at = now()
   where id = v_uid;
end;
$$;

revoke all on function public.delete_own_account() from public, anon;
grant execute on function public.delete_own_account() to authenticated;

comment on function public.delete_own_account() is
  'Apaga a conta do usuário autenticado e o conteúdo dele, por soft delete. '
  'Exigência da Google Play para apps com cadastro. Ver PRIVACIDADE.md §6.';
