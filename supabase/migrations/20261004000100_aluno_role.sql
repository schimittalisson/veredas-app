-- =========================================================================
-- Papel `aluno` — alunos da ETED
--
-- Sozinho num arquivo de propósito. Um valor novo de enum só pode ser USADO
-- depois que a transação que o criou faz commit ("unsafe use of new value").
-- A migration seguinte (`20261004000200_eted.sql`) cria funções `language
-- sql` que comparam com 'aluno', e o corpo delas é validado no CREATE
-- FUNCTION (check_function_bodies = on). Se o `add value` estivesse no mesmo
-- arquivo, e o Supabase aplicasse o arquivo numa transação só, ela falharia.
--
-- O que o papel significa está documentado na migration seguinte.
-- =========================================================================

alter type public.app_role add value if not exists 'aluno';
