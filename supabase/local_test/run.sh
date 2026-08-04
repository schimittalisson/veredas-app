#!/usr/bin/env bash
#
# Valida as migrations e as policies de RLS num Postgres local, sem tocar no
# Supabase. Exige apenas Docker.
#
#   ./supabase/local_test/run.sh
#
# Por que isto existe: RLS é a única coisa que protege os dados do app — a anon
# key vai embarcada no APK. Mudar uma policy sem reverificar é como a segurança
# quebra em silêncio. Rode isto depois de qualquer alteração em
# supabase/migrations/.
#
# Já pegou dois bugs reais que travariam o projeto:
#   - manages_scale criada antes de scale_managers (check_function_bodies)
#   - trigger protect_profile_privileges impedindo criar o primeiro admin
set -euo pipefail

CONTAINER="veredas-pgtest"
IMAGE="postgres:17"          # Supabase roda PG 15+; security_invoker exige 15+
DB="veredas"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SB="$(cd "$HERE/.." && pwd)"

red()  { printf '\033[31m%s\033[0m\n' "$1"; }
grn()  { printf '\033[32m%s\033[0m\n' "$1"; }
info() { printf '\033[36m%s\033[0m\n' "$1"; }

cleanup() {
  if [[ "${KEEP:-0}" == "1" ]]; then
    info "KEEP=1: container $CONTAINER mantido (docker rm -f $CONTAINER para remover)."
  else
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

info "==> Subindo $IMAGE"
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run -d --name "$CONTAINER" \
  -e POSTGRES_PASSWORD=test -e POSTGRES_DB="$DB" \
  "$IMAGE" >/dev/null

# O entrypoint do Postgres sobe e reinicia o servidor durante a inicialização,
# então um pg_isready que passa cedo pode ser seguido de "shutting down".
# Exigimos consultas bem-sucedidas consecutivas antes de prosseguir.
ok=0
for _ in $(seq 1 60); do
  if docker exec "$CONTAINER" psql -U postgres -d "$DB" -tAc 'select 1' >/dev/null 2>&1; then
    ok=$((ok + 1))
    [[ $ok -ge 3 ]] && break
  else
    ok=0
  fi
  sleep 1
done
[[ $ok -ge 3 ]] || { red "Postgres não subiu."; exit 1; }

docker cp "$SB/." "$CONTAINER:/tmp/sb/" >/dev/null

psql_run() {
  docker exec "$CONTAINER" psql -U postgres -d "$DB" -v ON_ERROR_STOP=1 -q -f "$1"
}

info "==> Stubs do Supabase (auth, storage, roles)"
psql_run /tmp/sb/local_test/00_stubs.sql

info "==> Migrations"
for f in "$SB"/migrations/*.sql; do
  b="$(basename "$f")"
  printf '    %-48s' "$b"
  if psql_run "/tmp/sb/migrations/$b" >/tmp/veredas_mig.log 2>&1; then
    grn 'OK'
  else
    red 'FALHOU'
    cat /tmp/veredas_mig.log
    exit 1
  fi
done

info "==> Seed"
psql_run /tmp/sb/seed.sql

info "==> Seed é idempotente? (reaplicando)"
before=$(docker exec "$CONTAINER" psql -U postgres -d "$DB" -tAc \
  'select (select count(*) from weekly_slots)||:|:||(select count(*) from social_links)||:|:||(select count(*) from base_info)||:|:||(select count(*) from scale_types)' 2>/dev/null \
  || docker exec "$CONTAINER" psql -U postgres -d "$DB" -tAc \
  "select concat_ws('/', (select count(*) from weekly_slots), (select count(*) from social_links), (select count(*) from base_info), (select count(*) from scale_types))")
psql_run /tmp/sb/seed.sql
after=$(docker exec "$CONTAINER" psql -U postgres -d "$DB" -tAc \
  "select concat_ws('/', (select count(*) from weekly_slots), (select count(*) from social_links), (select count(*) from base_info), (select count(*) from scale_types))")
if [[ "$before" == "$after" ]]; then
  grn "    OK (contagens estáveis: $after)"
else
  red "    FALHOU: seed duplicou linhas ($before -> $after)"
  exit 1
fi

info "==> Fixtures"
psql_run /tmp/sb/local_test/01_fixtures.sql

info "==> Asserções de RLS"
# Sem -q: as asserções saem por RAISE NOTICE.
# O psql prefixa os notices com "psql:<arquivo>:<linha>: NOTICE:  ", então o
# filtro precisa casar no meio da linha, não no início.
docker exec "$CONTAINER" psql -U postgres -d "$DB" \
  -f /tmp/sb/local_test/02_assertions.sql 2>&1 \
  | grep -E 'NOTICE:  (PASS|FAIL)|^===========' \
  | sed -E 's/^.*NOTICE:  //' \
  | tee /tmp/veredas_assert.log

fails=$(grep -c '^FAIL' /tmp/veredas_assert.log || true)
passes=$(grep -c '^PASS' /tmp/veredas_assert.log || true)

echo
if [[ "$fails" -eq 0 && "$passes" -gt 0 ]]; then
  grn "RESULTADO: $passes asserções passaram, 0 falhas."
  exit 0
fi
red "RESULTADO: $fails falha(s) de $((passes + fails)) asserções."
grep '^FAIL' /tmp/veredas_assert.log || true
exit 1
