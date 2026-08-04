#!/usr/bin/env bash
#
# Concatena as migrations + o seed num único arquivo, para colar de uma vez no
# SQL Editor do Supabase em vez de abrir 9 abas.
#
#   ./supabase/build_apply_all.sh
#   -> supabase/apply_all.generated.sql
#
# O arquivo gerado é gitignored de propósito: ter duas cópias do schema no
# repositório garante que uma delas fique desatualizada. Gere quando precisar.
#
# A ordem alfabética dos prefixos numéricos É a ordem de aplicação — há
# dependências entre os blocos (tipos -> funções -> tabelas -> policies).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/apply_all.generated.sql"

{
  echo "-- ==================================================================="
  echo "-- GERADO por supabase/build_apply_all.sh em $(date -Iseconds)"
  echo "-- NÃO EDITE ESTE ARQUIVO. Edite supabase/migrations/ e regenere."
  echo "--"
  echo "-- Cole tudo no SQL Editor do Supabase e execute uma única vez."
  echo "-- Pré-validado em Postgres 17: ./supabase/local_test/run.sh"
  echo "-- ==================================================================="
  echo

  for f in "$HERE"/migrations/*.sql; do
    echo
    echo "-- ///////////////////////////////////////////////////////////////////"
    echo "-- $(basename "$f")"
    echo "-- ///////////////////////////////////////////////////////////////////"
    cat "$f"
    echo
  done

  echo
  echo "-- ///////////////////////////////////////////////////////////////////"
  echo "-- seed.sql"
  echo "-- ///////////////////////////////////////////////////////////////////"
  cat "$HERE/seed.sql"
} > "$OUT"

echo "Gerado: $OUT"
echo "  $(wc -l < "$OUT") linhas, $(du -h "$OUT" | cut -f1)"
