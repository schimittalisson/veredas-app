// Teste local do fcm.ts, sem Deno: `npx tsx supabase/functions/notify-announcement/fcm_test.ts`.
// Gera uma chave RSA, assina o JWT e confere a assinatura com a pública.
import { generateKeyPairSync, createVerify } from "node:crypto";
import assert from "node:assert/strict";
import {
  announcementMessage,
  buildFcmMessage,
  classifyFcmResponse,
  signServiceAccountJwt,
} from "./fcm.ts";

async function main() {
const { privateKey, publicKey } = generateKeyPairSync("rsa", {
  modulusLength: 2048,
  privateKeyEncoding: { type: "pkcs8", format: "pem" },
  publicKeyEncoding: { type: "spki", format: "pem" },
});

// O JSON baixado do console traz a chave com "\n" de verdade; colado num
// secret às vezes chega com "\\n" literal. Os dois precisam funcionar.
for (const pem of [privateKey, privateKey.replace(/\n/g, "\\n")]) {
  const jwt = await signServiceAccountJwt(
    { project_id: "p", client_email: "sa@p.iam.gserviceaccount.com", private_key: pem },
    1_700_000_000,
  );
  const [h, c, s] = jwt.split(".");
  const v = createVerify("RSA-SHA256");
  v.update(`${h}.${c}`);
  assert.ok(v.verify(publicKey, Buffer.from(s, "base64url")), "assinatura inválida");
  const claims = JSON.parse(Buffer.from(c, "base64url").toString());
  assert.equal(claims.iss, "sa@p.iam.gserviceaccount.com");
  assert.equal(claims.aud, "https://oauth2.googleapis.com/token");
  assert.equal(claims.exp - claims.iat, 3600);
}

assert.equal(classifyFcmResponse(200, "{}"), "ok");
assert.equal(classifyFcmResponse(404, '{"error":{"status":"NOT_FOUND","details":[{"errorCode":"UNREGISTERED"}]}}'), "invalid");
// 400 genérico não apaga: pode ser erro na mensagem, não no aparelho.
assert.equal(classifyFcmResponse(400, '{"error":{"status":"INVALID_ARGUMENT"}}'), "error");
assert.equal(classifyFcmResponse(503, "unavailable"), "error");

const m = announcementMessage("a1", "Mutirão", "x".repeat(300));
assert.equal(m.title, "Novo aviso: Mutirão");
assert.equal(m.body.length, 178);
assert.deepEqual(m.data, { type: "announcement", id: "a1" });
assert.equal(announcementMessage("a1", "  ", "oi").title, "Novo aviso");
const built = buildFcmMessage("fid-1", m).message;
assert.equal(built.fid, "fid-1");
assert.equal("token" in built, false);
assert.equal(built.android.notification.channel_id, "announcements");

console.log("fcm_test: ok");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
