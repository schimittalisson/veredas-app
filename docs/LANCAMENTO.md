# Lançamento

Como colocar uma versão do Veredas na mão dos obreiros da base.

Ordem de leitura: `AGENTS.md` §3 (comandos e assinatura) → este arquivo.

---

## 1. O modelo de distribuição

Decisão do solicitante, e ela não é um contorno — é o desenho certo para um app
de ~30 pessoas de uma base:

| Plataforma | Como | Loja |
|---|---|---|
| Android | APK assinado, instalado à mão | **nenhuma** — não há conta na Play |
| iOS | App Store com **distribuição não listada** | conta de organização |

O app não fica aberto ao público geral em nenhuma das duas. Na Play isso é
consequência de não ter conta; no iOS é escolha: um app interno listado na
busca corre risco de recusa pela Guideline 4.2 ("não é útil ao público geral"),
e a distribuição não listada existe exatamente para este caso.

---

## 2. Android — APK direto

### 2.1 A chave deixou de ser "de upload"

Sem Play App Signing, `~/.android-keys/veredas-upload.jks` **é a chave de
assinatura do app**, não só a de envio. O nome do arquivo e o `keyAlias=upload`
ficaram impróprios e continuam assim de propósito: trocar o alias troca a
chave.

O que muda com isso:

1. **Todo APK futuro precisa ser assinado com ela.** Um APK com chave diferente
   não instala em cima do que já está no aparelho —
   `INSTALL_FAILED_UPDATE_INCOMPATIBLE`. A pessoa tem de desinstalar, e
   desinstalar apaga a sessão salva e o cache do drift (os dados em si estão no
   Supabase; o que se perde é o login e o modo offline até o primeiro sync).
2. **Perder a chave não tem reset.** Com a Play, o suporte do Google reemite a
   chave de upload. Aqui não existe esse caminho: perder o `.jks` significa que
   ninguém mais atualiza o app instalado, só reinstala. **Faça backup do `.jks`
   e da senha** (que está no `android/key.properties`) num gerenciador de
   senhas, hoje.
3. **O build de release falha sem a chave**, em vez de cair nas debug keys — ver
   `android/app/build.gradle.kts`. Era um fallback silencioso, aceitável
   enquanto o destino era a Play (que recusa o artefato e avisa). Entregando
   APK à mão, o silêncio cobra caro: o APK debug-signed instala sem reclamar, e
   o estrago só aparece na atualização seguinte.

Impressão digital do certificado, para conferir um APK sem ter o keystore:

```
SHA-256: E2:6F:7C:A3:92:83:85:EB:A4:24:43:25:5D:8C:EB:FF:B1:40:68:46:C9:AA:F8:92:87:2C:52:13:11:95:F4:39
```

### 2.2 Gerar o APK

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export ANDROID_HOME="$HOME/Android/Sdk"

flutter build apk --release --dart-define-from-file=env/prod.json
# -> build/app/outputs/flutter-apk/app-release.apk  (~67 MB)
```

**APK universal, um arquivo só. Não use `--split-per-abi`**: ele gera três
arquivos (armeabi-v7a, arm64-v8a, x86_64) e alguém vai instalar o errado e
receber "app não instalado" sem entender por quê. Os ~67 MB são o preço de não
ter essa conversa 30 vezes.

### 2.3 Conferir o artefato, não o fonte

**Os comandos do `AGENTS.md` §3 são para o AAB e devolvem vazio num APK** — o
que se lê como "não assinado" e "sem INTERNET", os dois falsos. Motivo: o APK
é assinado pelos esquemas v2/v3 e não tem assinatura v1 (JAR), que é a única
que o `jarsigner` entende; e o `AndroidManifest.xml` dentro do APK é binário
com strings em UTF-16, que o `strings` não acha por padrão.

Para APK, use as ferramentas do `build-tools`:

```bash
BT=$(ls -d "$ANDROID_HOME"/build-tools/*/ | tail -1)

# Quem assinou
"$BT/apksigner" verify --print-certs \
  build/app/outputs/flutter-apk/app-release.apk | grep "certificate DN"
# esperado: CN=Base Missionaria JOCUM Veredas, OU=TI, O=JOCUM Veredas, ...

# Permissão de rede e numeração, de uma vez
"$BT/aapt2" dump badging build/app/outputs/flutter-apk/app-release.apk \
  | grep -E "^package|INTERNET"
# esperado: package: ... versionCode='N' versionName='X.Y.Z'
#           uses-permission: name='android.permission.INTERNET'
```

Sem a linha do `INTERNET` o app instala, abre e não alcança o Supabase — e o
teste no emulador não pega, porque ali roda debug (ver `AGENTS.md` §3).

### 2.4 Numeração

O `versionCode` sai do `+N` do `version:` no `pubspec.yaml`. **Incremente o
`+N` a cada APK distribuído.** Com o mesmo `versionCode`, o Android trata a
instalação como reinstalação da mesma versão — funciona, mas você perde a
única forma de saber qual build está no aparelho de alguém.

```yaml
version: 1.0.0+1   # primeiro APK
version: 1.0.1+2   # correção seguinte
```

### 2.5 Entregar e atualizar

- **Primeira entrega**: por fora do app (grupo de WhatsApp, e-mail, Drive).
  Quem ainda não tem o app não alcança um link que esteja dentro dele.
- **Atualizações**: cadastre o link do APK na aba **Arquivos** do próprio app —
  é exatamente o que aquela aba faz. Aí o aviso de "saiu versão nova" pode ir
  num aviso da tela Início, e o link fica num lugar estável.
- **Avise antes sobre os dois sustos**: o Android vai pedir para permitir
  "instalar apps desconhecidos" na origem do arquivo, e o Play Protect vai
  mostrar "app não verificado" com um botão discreto de "instalar de qualquer
  forma". As duas coisas são normais para app fora da loja; sem aviso prévio,
  metade das pessoas desiste aí.
- **Não há atualização automática.** Ninguém recebe a versão nova sozinho.

---

## 3. iOS — App Store não listada

### 3.1 Por que essa e não as outras

| Caminho | Por que não |
|---|---|
| TestFlight (onde você está) | O build **expira em 90 dias**. Vira re-upload trimestral para sempre. |
| Ad Hoc | 100 aparelhos por ano e o UDID de cada um cadastrado à mão. |
| Apple Developer Enterprise Program | US$ 299/ano e exige empresa grande; a Apple recusa organização pequena. |
| Custom App via Apple Business Manager | Permanente, mas exige a base operar o ABM. Mais máquina do que o caso pede. |
| **Unlisted App Distribution** | **Permanente, instala por link, não aparece em busca nem nas listas.** |

### 3.2 Passos

1. **Conta de organização.** Precisa do número **D-U-N-S** da entidade (a base
   como pessoa jurídica, com CNPJ) e verificação legal pela Apple. Leva de dias
   a semanas — comece por aqui, é o passo mais lento.
2. **Isenção da anuidade.** A Apple dispensa os US$ 99/ano de organizações sem
   fins lucrativos em países elegíveis. Vale checar a elegibilidade da base no
   próprio fluxo de inscrição; não é automático, é um pedido.
3. **Ficha da versão** no App Store Connect: nome, descrição, categoria,
   screenshots, classificação de idade, URL de suporte e **URL da política de
   privacidade** (ver §4).
4. **Submeter à revisão.** App não listado **passa por revisão normalmente** —
   não listado é o modo de distribuição, não uma isenção.
5. **Pedir o status não listado** pelo formulário da Apple para Unlisted App
   Distribution. Peça **antes** de publicar como app público: converter depois
   depende de um caminho que pode não existir quando você precisar.
6. **Conta de demonstração é obrigatória** — ver §4. É o que mais reprova este
   app.

### 3.3 O CI continua parando no TestFlight, de propósito

O `ios-release` do `codemagic.yaml` publica no TestFlight e **não** submete à
App Store. Não é esquecimento: a primeira submissão precisa da ficha montada,
do pedido de não listagem e da conta de demonstração — nada disso um build
automático resolve. Depois de a versão 1.0 estar aprovada, se quiser que o CI
submeta as seguintes, é `submit_to_app_store: true` no bloco `publishing`.

---

## 4. O que vale para as duas pontas

### 4.1 Conta de demonstração — o que mais reprova

O cadastro exige **código de convite** e **aprovação por um admin**. O revisor
da Apple não tem como entrar sozinho: isso é recusa por Guideline 2.1 (App
Access), e a mesma pergunta existe na Play em "Acesso ao app".

Em "App Review Information", forneça:

- e-mail e senha de um perfil **já aprovado** (crie um só para isso);
- o código de convite válido, se a tela de cadastro pedir;
- uma nota explicando que o app é de uso interno de uma base missionária e que
  o acesso depende de aprovação.

Confirme que o perfil de demonstração continua aprovado antes de cada
submissão. Um `is_approved = false` derruba a revisão.

### 4.2 Política de privacidade precisa de URL pública

`PRIVACIDADE.md` é um arquivo do repositório; as duas lojas pedem uma **URL**.
GitHub Pages sobre o próprio repositório resolve. O questionário de App Privacy
da Apple deve bater com o §2 do documento: nome, e-mail, telefone, foto de
perfil e conteúdo criado pelo usuário.

### 4.3 Marcar o commit

O repositório **não tem tags**. Sem elas não há como voltar ao código exato de
um APK que já está instalado em 30 aparelhos.

```bash
git tag -a v1.0.0 -m "Versão 1.0.0 — primeiro release"
```

---

## 5. Checklist de cada release

- [ ] `flutter analyze` limpo e `flutter test` passando
- [ ] `./supabase/local_test/run.sh` verde, se houve mudança em `supabase/migrations/`
- [ ] `version:` do `pubspec.yaml` incrementado (nome **e** `+N`)
- [ ] Migrations novas aplicadas no Supabase **antes** de distribuir o app
- [ ] APK: `apksigner` mostra `CN=Base Missionaria JOCUM Veredas`
- [ ] APK: `aapt2 dump badging` mostra `INTERNET` e o `versionCode` novo
- [ ] Instalado por cima da versão anterior num aparelho real, sem desinstalar
- [ ] Perfil de demonstração ainda aprovado (se houver submissão iOS)
- [ ] `git tag` no commit distribuído
