// Envio pelo FCM HTTP v1, sem SDK.
//
// O SDK `firebase-admin` não roda no Deno das Edge Functions sem shims, e o
// que ele faz aqui é pouco: trocar a conta de serviço por um access token
// (JWT RS256 assinado com a chave privada) e chamar um endpoint REST. Usa só
// WebCrypto e fetch, que existem igual no Deno e no Node 20 — é assim que
// `fcm_test.ts` roda localmente sem Deno.

export interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri?: string;
}

export interface PushMessage {
  title: string;
  body: string;
  data: Record<string, string>;
}

/** Resultado por aparelho: `invalid` quer dizer "apague este registro". */
export type SendResult = "ok" | "invalid" | "error";

const SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
const DEFAULT_TOKEN_URI = "https://oauth2.googleapis.com/token";

function base64url(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64urlJson(value: unknown): string {
  return base64url(new TextEncoder().encode(JSON.stringify(value)));
}

function pemToPkcs8(pem: string): Uint8Array {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\\n/g, "") // chave colada com "\n" literal no secret
    .replace(/\s+/g, "");
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

/** JWT assinado que o Google troca por um access token (RFC 7523). */
export async function signServiceAccountJwt(
  sa: ServiceAccount,
  nowSeconds = Math.floor(Date.now() / 1000),
): Promise<string> {
  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: sa.client_email,
    scope: SCOPE,
    aud: sa.token_uri ?? DEFAULT_TOKEN_URI,
    iat: nowSeconds,
    exp: nowSeconds + 3600,
  };
  const unsigned = `${base64urlJson(header)}.${base64urlJson(claims)}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  return `${unsigned}.${base64url(new Uint8Array(signature))}`;
}

export async function getAccessToken(
  sa: ServiceAccount,
  fetchFn: typeof fetch = fetch,
): Promise<string> {
  const jwt = await signServiceAccountJwt(sa);
  const res = await fetchFn(sa.token_uri ?? DEFAULT_TOKEN_URI, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!res.ok) {
    throw new Error(`OAuth do Google recusou: ${res.status} ${await res.text()}`);
  }
  const json = await res.json();
  return json.access_token as string;
}

/**
 * Corpo do `messages:send` para um aparelho.
 *
 * O alvo é `fid` (Firebase Installation ID). O campo `token` está depreciado
 * no FCM HTTP v1, e o app registra FID — ver `push_messaging.dart`.
 */
export function buildFcmMessage(fid: string, msg: PushMessage) {
  return {
    message: {
      fid,
      notification: { title: msg.title, body: msg.body },
      data: msg.data,
      android: {
        priority: "high",
        // O canal é criado pelo app (`NotificationService`). Sem ele, o
        // Android 8+ cai no canal genérico "Diversos".
        notification: { channel_id: "announcements" },
      },
      apns: { payload: { aps: { sound: "default" } } },
    },
  };
}

/**
 * Classifica a resposta do FCM. App desinstalado, ou aparelho que saiu do
 * FCM no logout, volta 404 `UNREGISTERED`: nunca mais vai funcionar e deve
 * sair da tabela.
 *
 * Um 400 genérico **não** apaga: pode ser erro na própria mensagem, e apagar
 * por isso tiraria da lista todos os aparelhos da base de uma vez.
 */
export function classifyFcmResponse(status: number, body: string): SendResult {
  if (status >= 200 && status < 300) return "ok";
  if (status === 404 || body.includes("UNREGISTERED")) return "invalid";
  return "error";
}

export async function sendToDevice(
  projectId: string,
  accessToken: string,
  fid: string,
  msg: PushMessage,
  fetchFn: typeof fetch = fetch,
): Promise<SendResult> {
  const res = await fetchFn(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(buildFcmMessage(fid, msg)),
    },
  );
  return classifyFcmResponse(res.status, await res.text());
}

/** Texto da notificação de um aviso. */
export function announcementMessage(
  id: string,
  title: string | null,
  body: string,
): PushMessage {
  const clean = body.replace(/\s+/g, " ").trim();
  const short = clean.length > 180 ? `${clean.slice(0, 177)}…` : clean;
  const hasTitle = title != null && title.trim().length > 0;
  return {
    title: hasTitle ? `Novo aviso: ${title!.trim()}` : "Novo aviso",
    body: short,
    data: { type: "announcement", id },
  };
}
