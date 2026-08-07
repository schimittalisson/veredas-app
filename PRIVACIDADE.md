# Política de Privacidade — Veredas

**Última atualização:** 4 de agosto de 2026

## 1. Quem somos

O app Veredas é o aplicativo oficial da Base Missionária JOCUM Veredas
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

Você pode excluir a sua conta **dentro do app**, sem depender de um
administrador: toque no seu avatar na tela Início e escolha
*Excluir minha conta*.

A exclusão remove:

- Perfil: nome, e-mail, telefone, foto e bio são apagados.
- Posts e comentários no mural de oração.
- Atribuições de escala futuras.
- Convites que você gerou e que ninguém usou ainda.

Atribuições de escala **passadas** são mantidas para registro histórico da
base, com o nome substituído por "Removido" — não é possível identificar você
a partir delas.

Convites seus que **já foram usados** por outra pessoa são mantidos, porque
apagá-los destruiria o registro de como aquele obreiro entrou na base.

A exclusão é imediata e encerra a sua sessão. O identificador de login fica
retido por até 30 dias no sistema de autenticação, para o caso de exclusão
acidental, e depois é apagado em definitivo.

Se você for o **único administrador ativo**, o app não permite a exclusão até
que outra pessoa seja promovida a administrador — sem isso a base ficaria sem
ninguém capaz de aprovar novos obreiros.

Para solicitar a exclusão sem acesso ao app, contate a liderança da Base
Missionária JOCUM Veredas.

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
 JOCUM Veredas.
