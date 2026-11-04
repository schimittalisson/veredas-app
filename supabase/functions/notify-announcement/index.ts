// Edge Function: envia push de aviso novo.
//
// Chamada pelo trigger `announcements_notify` (migration
// 20261104000200_push_notifications.sql) via pg_net, com o segredo
// compartilhado no header Authorization. Deploy SEM verificação de JWT do
// Supabase (`--no-verify-jwt`): quem chama é o banco, não um usuário, e a
// autenticação é o segredo. Passo a passo em supabase/README.md, Passo 10.
//
// Secrets (supabase secrets set ...):
//   PUSH_WEBHOOK_SECRET       o mesmo valor de `push_webhook_secret` no Vault
//   FIREBASE_SERVICE_ACCOUNT  o JSON da conta de serviço do Firebase, inteiro
// SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY já vêm no ambiente da função.

import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import {
  announcementMessage,
  getAccessToken,
  sendToDevice,
  type ServiceAccount,
} from "./fcm.ts";

const BATCH = 20;

Deno.serve(async (req) => {
  const secret = Deno.env.get("PUSH_WEBHOOK_SECRET");
  if (!secret || req.headers.get("Authorization") !== `Bearer ${secret}`) {
    return new Response("unauthorized", { status: 401 });
  }

  let payload: { type?: string; id?: string };
  try {
    payload = await req.json();
  } catch {
    return new Response("bad json", { status: 400 });
  }
  if (payload.type !== "announcement" || !payload.id) {
    return new Response("ignored", { status: 200 });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  const { data: announcement, error: aErr } = await supabase
    .from("announcements")
    .select("id, title, body, author_id, deleted_at")
    .eq("id", payload.id)
    .maybeSingle();
  if (aErr) return new Response(aErr.message, { status: 500 });
  // Apagado entre o insert e a chamada: não avisa ninguém.
  if (!announcement || announcement.deleted_at) {
    return new Response("gone", { status: 200 });
  }

  // Aparelhos de quem está aprovado e não foi removido. Quem escreveu o aviso
  // não recebe — acabou de escrever.
  let query = supabase
    .from("push_devices")
    .select("fid, user_id, profiles!inner(is_approved, deleted_at)")
    .eq("profiles.is_approved", true)
    .is("profiles.deleted_at", null);
  if (announcement.author_id) {
    query = query.neq("user_id", announcement.author_id);
  }
  const { data: rows, error: tErr } = await query;
  if (tErr) return new Response(tErr.message, { status: 500 });
  if (!rows || rows.length === 0) {
    return Response.json({ sent: 0, invalid: 0, failed: 0 });
  }

  const sa = JSON.parse(
    Deno.env.get("FIREBASE_SERVICE_ACCOUNT")!,
  ) as ServiceAccount;
  const accessToken = await getAccessToken(sa);
  const msg = announcementMessage(
    announcement.id,
    announcement.title,
    announcement.body,
  );

  let sent = 0;
  let failed = 0;
  const invalid: string[] = [];
  for (let i = 0; i < rows.length; i += BATCH) {
    const batch = rows.slice(i, i + BATCH);
    const results = await Promise.all(
      batch.map((r) => sendToDevice(sa.project_id, accessToken, r.fid, msg)),
    );
    results.forEach((res, j) => {
      if (res === "ok") sent++;
      else if (res === "invalid") invalid.push(batch[j].fid);
      else failed++;
    });
  }

  // Aparelho de app desinstalado nunca volta a valer; manter só gera erro a
  // cada aviso.
  if (invalid.length > 0) {
    await supabase.from("push_devices").delete().in("fid", invalid);
  }

  return Response.json({ sent, invalid: invalid.length, failed });
});
