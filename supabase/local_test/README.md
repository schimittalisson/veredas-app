# Harness de validação do RLS

Aplica as migrations e as policies num **Postgres local em Docker** e roda 47
asserções sobre o modelo de permissões. Não toca no Supabase.

```bash
./supabase/local_test/run.sh          # exit 0 = tudo passou
KEEP=1 ./supabase/local_test/run.sh   # mantém o container para inspecionar
docker exec -it veredas-pgtest psql -U postgres -d veredas
```

## Por que isto existe

O RLS é a **única** coisa que protege os dados do app: a `anon key` vai
embarcada no APK e qualquer pessoa a extrai. Ocultar um botão na UI não é
controle de acesso.

O problema prático é que uma policy errada falha em silêncio — os dados vazam
sem nenhum erro visível. Reverificar à mão pelo SQL Editor, com UUIDs colados
na mão, é lento e ninguém faz depois da terceira vez.

**Rode isto depois de qualquer alteração em `supabase/migrations/`.**

Já pegou três problemas reais antes de chegarem ao banco de produção:

1. **`manages_scale` na ordem errada.** O `SCHEMA.md` §3 afirma que o corpo de
   uma função `language sql` só é resolvido na execução. É falso com
   `check_function_bodies = on` (padrão no Supabase): o corpo é validado no
   `CREATE FUNCTION`, e a função referencia uma tabela criada depois.
   → extraída para a migration `0450`.
2. **Era impossível criar o primeiro admin.** O trigger
   `protect_profile_privileges` avalia `is_admin()`, que é falso no SQL Editor
   (ali `auth.uid()` é `NULL`). O `UPDATE` de promoção do passo 7 do
   `../README.md` morria com `FORBIDDEN_PRIVILEGE_CHANGE` — sem saída.
   → exceção para `auth.uid() is null` na migration `0800`.
3. **`authenticated` sem `USAGE` em `extensions`.** `norm_text()` não pode ser
   `security definer` (precisa ser `immutable` para servir de índice), então
   executa como quem chama e a busca do mural falhava com
   `permission denied for schema extensions`.
   → grant explícito na migration `0100`.

## Arquivos

| Arquivo | Papel |
|---|---|
| `00_stubs.sql` | O que o Supabase dá de fábrica e um Postgres cru não tem: schemas `auth`/`storage`/`extensions`, roles `anon`/`authenticated`/`service_role`, `auth.uid()`, `storage.foldername()` |
| `01_fixtures.sql` | 3 usuários cobrindo os estados de permissão + grants padrão do Supabase |
| `02_assertions.sql` | As asserções. Cada uma imprime `PASS` ou `FAIL` |
| `run.sh` | Orquestra tudo e devolve exit code |

Nada daqui vai para produção. O `00_stubs.sql` e o schema `test` existem só no
container.

## O que é coberto

| # | Grupo |
|---|---|
| 1 | Usuário não aprovado não vê nada (mas vê o próprio perfil) |
| 2 | Obreiro aprovado lê o conteúdo, mas não os convites |
| 3 | **Escalas** — responsável escreve na sua e falha nas outras |
| 4 | Escalada de privilégio (auto-promoção a admin) |
| 5 | Resgate de convite: válido, inexistente, caixa, idempotência |
| 6 | Mural: autoria, edição alheia, publicar em nome de outro |
| 7 | Tela Início: só admin escreve |
| 8 | Busca ignorando acento e caixa |
| 9 | Bootstrap do primeiro admin |
| 10 | Nenhuma tabela `public` sem RLS |

## Uma semântica do RLS que engana

Ao escrever asserções novas, atenção:

- **`INSERT`** (e `UPDATE` que produza linha proibida) reprova no `WITH CHECK` e
  **lança erro** `42501 insufficient_privilege`. Use `test.expect_denied`.
- **`UPDATE`/`DELETE`** cujas linhas reprovam no `USING` são **filtrados em
  silêncio**: 0 linhas afetadas, **nenhum erro**. Use `test.expect_rowcount(...,
  0)`. Um `expect_denied` aqui dá falso negativo.

Isso não é detalhe de teste — tem consequência direta no `OutboxWorker`
(Fase 4). Ver `AGENTS.md`, seção "Decisões tomadas".

## Limitações

O harness valida **schema, policies, triggers, funções e seeds**. Não valida o
que só existe no Supabase gerenciado: envio de e-mail/SMTP, políticas reais de
Storage sob a implementação deles, Realtime e configurações do painel de Auth.
Esses continuam sendo verificação manual, pelo `../README.md`.
