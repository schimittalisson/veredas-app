# Política de Privacidade — Veredas

**Última atualização:** 4 de agosto de 2026

## 1. Quem somos

O app Veredas é o aplicativo oficial da Base Missionária Veredas
(Joinville/SC), usado para gerenciamento interno de obreiros, escalas,
eventos, avisos e pedidos de oração.

## 2. Dados que coletamos

O app coleta e processa os seguintes dados pessoais identificáveis:

| Dado | Finalidade | Obrigatório |
|---|---|---|
| Nome completo | Identificação do obreiro em escalas, avisos e mural | Sim |
| E-mail | Autenticação e comunicação | Sim |
| Telefone | Contato entre obreiros | Não |
| Foto de perfil | Identificação visual | Não |
| Biografia | Apresentação no perfil | Não |

Dados de uso (logs de acesso, métricas) podem ser coletados pelo Supabase
para fins de diagnóstico e segurança, conforme a política do provedor.

## 3. Como usamos seus dados

- **Autenticação:** e-mail e senha são usados para login.
- **Gestão:** nome, telefone e foto aparecem para outros obreiros aprovados
  em escalas, avisos e mural de oração.
- **Convites:** admins podem gerar códigos de convite para novos obreiros.
  O código não contém dados pessoais.
- **Sincronização:** os dados são cacheados localmente no dispositivo para
  funcionamento offline. O cache é removido ao desinstalar o app.

## 4. Compartilhamento

Nenhum dado é compartilhado com terceiros. O app é de uso interno da Base
Missionária Veredas. O processamento é feito pelo Supabase (provedor de
backend em conformidade com a LGPD).

## 5. Seus direitos (LGPD)

Conforme a Lei Geral de Proteção de Dados (Lei 13.709/2018), você tem
direito a:

- **Acesso:** solicitar uma cópia dos seus dados.
- **Correção:** corrigir dados incompletos ou inexatos.
- **Exclusão:** solicitar a exclusão da sua conta e dados associados.
- **Portabilidade:** receber seus dados em formato estruturado.

Para exercer qualquer direito, contate a liderança da base ou use o botão
"Excluir minha conta" no perfil do app.

## 6. Exclusão de conta

A exclusão de conta remove permanentemente:

- Perfil (nome, e-mail, telefone, foto, bio).
- Atribuições de escala futuras.
- Posts e comentários no mural de oração.
- Convites gerados pelo usuário.

Atribuições de escala passadas podem ser mantidas para registro histórico,
com o nome substituído por "Removido".

## 7. Segurança

- Senhas são armazenadas com hash pelo Supabase (Auth).
- A comunicação entre o app e o servidor usa HTTPS/TLS.
- O acesso aos dados é controlado por RLS (Row Level Security) — cada
  obreiro só vê o que tem permissão de ver.
- A chave `service_role` do Supabase nunca entra no app.

## 8. Retenção

- Dados de obreiros ativos: enquanto a conta existir.
- Dados de obreiros removidos: o nome é substituído por "Removido" em
  registros históricos (escalas passadas, avisos antigos).
- Convites: retidos por 90 dias após revogação ou expiração, depois
  removidos.

## 9. Crianças

O app não é direcionado a menores de 18 anos e não coleta dados de
crianças.

## 10. Contato

Para dúvidas sobre esta política, contate a liderança da Base Missionária
Veredas.
