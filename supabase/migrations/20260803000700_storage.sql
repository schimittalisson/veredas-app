-- =========================================================================
-- §7 — Storage
--
-- Ambos os buckets são PRIVADOS: o app lê via URL assinada. Um bucket público
-- expõe as fotos dos obreiros a qualquer um que descubra a URL.
-- =========================================================================

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', false), ('event-covers', 'event-covers', false)
on conflict (id) do nothing;

-- -------------------------------------------------------------------------
-- avatars: cada usuário só escreve na própria pasta "<uid>/...".
-- storage.foldername(name) devolve o array de pastas do caminho, então
-- (storage.foldername(name))[1] é o primeiro nível — que exigimos ser o uid.
-- -------------------------------------------------------------------------
create policy avatars_read on storage.objects
  for select to authenticated
  using (bucket_id = 'avatars' and public.is_approved());

create policy avatars_write_own on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy avatars_update_own on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy avatars_delete_own on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- -------------------------------------------------------------------------
-- event-covers: leitura para aprovados, escrita só admin (só admin cria evento).
-- -------------------------------------------------------------------------
create policy covers_read on storage.objects
  for select to authenticated
  using (bucket_id = 'event-covers' and public.is_approved());

create policy covers_admin_write on storage.objects
  for all to authenticated
  using (bucket_id = 'event-covers' and public.is_admin())
  with check (bucket_id = 'event-covers' and public.is_admin());
