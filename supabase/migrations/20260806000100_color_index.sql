-- =========================================================================
-- Cor explícita em eventos e no cronograma
-- =========================================================================
--
-- Até aqui a cor de um registro era **derivada** do texto da categoria: o app
-- convertia a string num índice da paleta por soma de code units. Isso mantinha
-- a cor estável entre aparelhos sem custar uma coluna, mas tinha dois defeitos
-- que apareceram no uso real:
--
--   1. Colisão. A paleta tem 10 cores; a partir da 11ª categoria, duas
--      inevitavelmente recebem a mesma. Com 5 cores, três das 6 categorias em
--      uso já caíam no mesmo amarelo.
--   2. Nenhum controle. Não havia como dizer que "evangelismo" é laranja, nem
--      dar a mesma cor a duas categorias irmãs de propósito.
--
-- Guarda-se o **índice na paleta**, não um hex. O índice resolve para um trio
-- (traço, fundo, texto) já verificado em WCAG AA, e resolve de forma diferente
-- no tema claro e no escuro. Um hex fixo obrigaria a guardar duas cores, ou
-- ficaria ilegível num dos dois temas.
--
-- Nulo = comportamento antigo: a cor continua saindo da categoria. Assim os
-- registros existentes não mudam de cor ao aplicar esta migration, e o app
-- segue funcionando para quem não escolher cor nenhuma.

alter table public.events
  add column color_index smallint;

alter table public.weekly_slots
  add column color_index smallint;

-- Sem limite superior de propósito: a paleta pode crescer no app sem exigir
-- uma migration nova. O cliente resolve o índice com módulo, então um valor
-- fora da faixa degrada para outra cor em vez de quebrar.
alter table public.events
  add constraint events_color_index_non_negative
  check (color_index is null or color_index >= 0);

alter table public.weekly_slots
  add constraint weekly_slots_color_index_non_negative
  check (color_index is null or color_index >= 0);

comment on column public.events.color_index is
  'Índice na paleta de acentos do app. Nulo = cor derivada da categoria.';
comment on column public.weekly_slots.color_index is
  'Índice na paleta de acentos do app. Nulo = cor derivada da categoria.';
