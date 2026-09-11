-- =========================================================================
-- Arquivos — catálogo de documentos da base (aba "Arquivos")
--
-- Pedido de um líder da base: um lugar para PDFs de treinamento e afins.
--
-- **Nesta versão o app só cadastra ATALHOS** para documentos que já vivem em
-- outro serviço (Google Drive, por exemplo). Nada é hospedado aqui.
--
-- Ainda assim a tabela nasce com `source_type` e `storage_path`, e não só com
-- `url`. O motivo é concreto: hospedar no Supabase Storage não é problema de
-- custo (o plano free inclui 1 GB, e um PDF de treinamento tem poucos MB), e o
-- que hoje falta é só o lado do app — os buckets privados de `avatars` e
-- `event-covers` já existem com policies na 0700. Quando alguém pedir "esse
-- manual precisa abrir sem internet", basta um bucket novo e o caminho de
-- upload: sem migração de dados, sem reescrever a entidade de sync, sem mexer
-- no cache do drift.
--
-- Segue a convenção do §4: `updated_at` (marca d'água do pull incremental,
-- trigger no fim deste arquivo) e `deleted_at` (soft delete, senão um
-- dispositivo offline nunca descobre que a linha saiu).
-- =========================================================================

create table public.documents (
  id           uuid primary key default gen_random_uuid(),
  title        text not null check (length(trim(title)) between 1 and 120),
  description  text,

  -- 'link' = atalho para um serviço externo (o caso de hoje).
  -- 'file' = arquivo hospedado num bucket do Storage (caminho em storage_path).
  source_type  text not null default 'link'
                 check (source_type in ('link', 'file')),
  url          text,
  storage_path text,

  created_by   uuid references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz,

  -- Garante no banco que a linha é utilizável. Sem isto um atalho poderia ser
  -- salvo sem destino nenhum e só apareceria como um item que não abre.
  constraint documents_source_target_check check (
    (source_type = 'link' and url is not null and length(trim(url)) > 0)
    or
    (source_type = 'file' and storage_path is not null
                          and length(trim(storage_path)) > 0)
  )
);

-- A ordenação da lista acontece no cliente, sobre o cache do drift (a tela
-- deixa o usuário escolher entre nome e data), então não há índice de ordenação
-- aqui — o servidor só devolve o catálogo inteiro.
--
-- **O sync desta tabela é `fullReplace`, não incremental.** A policy
-- `documents_select` abaixo filtra `deleted_at is null`, então um documento
-- removido apenas desaparece da consulta: o cliente nunca recebe a linha com
-- `deleted_at` preenchido que o pull incremental usaria como lápide para
-- limpar o cache. Com incremental, um arquivo apagado continuaria visível para
-- sempre em quem já o tinha sincronizado. Baixar dezenas de linhas a cada sync
-- é barato e sempre correto — mesma escolha de `scale_managers` e `prayer_feed`.
--
-- Por isso não existe índice em `updated_at`: nada filtra por ele nesta tabela.
create index documents_active_idx
  on public.documents (title) where deleted_at is null;

-- -------------------------------------------------------------------------
-- RLS — leitura para obreiro aprovado, escrita só admin.
--
-- Mesmo desenho de `announcements` e `events`: o conteúdo institucional é
-- publicado pela liderança e lido por todos os aprovados.
-- -------------------------------------------------------------------------
alter table public.documents enable row level security;

create policy documents_select on public.documents
  for select to authenticated
  using (public.is_approved() and deleted_at is null);

create policy documents_admin_write on public.documents
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- -------------------------------------------------------------------------
-- updated_at automático.
--
-- A 0800 aplica este trigger a uma lista fixa de tabelas; uma tabela criada
-- depois precisa registrar o seu.
--
-- Aqui o `updated_at` não serve de marca d'água (o sync é fullReplace), mas
-- alimenta a ordenação "alterados recentemente" da tela. Sem o trigger, a
-- coluna ficaria congelada na hora do insert e essa ordenação mentiria — e
-- confiar no valor mandado pelo app seria confiar no relógio do celular.
-- -------------------------------------------------------------------------
create trigger documents_touch_updated_at
  before update on public.documents
  for each row execute function public.touch_updated_at();
