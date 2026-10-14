# CI para o Pullglance: pesquisa

Pesquisa feita em 2026-10-14. Os workflows foram lidos direto dos repositórios via `gh api` na branch padrão de cada projeto, nessa data. Imagens, preços e docs também refletem essa data e mudam com frequência.

Convenção do documento: as seções 1 a 5 trazem **fatos** com fonte. Opiniões aparecem só em blocos marcados **Opinião** e na seção 6 (recomendação).

---

## 1. Como apps macOS open source fazem CI

### 1.1 Tabela comparativa

| Projeto | Runner | Seleção do Xcode | Build/teste | Cache | Triggers | Lint | Release |
|---|---|---|---|---|---|---|---|
| [Ice](https://github.com/jordanbaird/Ice/tree/main/.github/workflows) | `ubuntu-latest` (só lint) | nenhuma | nenhum build no CI | não | push `main` + PR, com `paths` | SwiftLint `--strict` via `norio-nomura/action-swiftlint` | não tem no CI |
| [Maccy](https://github.com/p0deje/Maccy) | sem workflows (`.github/` só tem FUNDING e templates) | | | | | | |
| [Rectangle](https://github.com/rxhanson/Rectangle/blob/main/.github/workflows/build.yml) | `xcode-27` | Xcode padrão da imagem | `xcodebuild archive` + export + `codesign -s -` + DMG + artifact | não | `[push, pull_request]` | não | fora do CI |
| [Stats](https://github.com/exelban/stats/tree/master/.github/workflows) | `macos-15` (e `macos-latest` nos testes SMC) | `sudo xcode-select -s /Applications/Xcode_26.3.app` | `xcodebuild archive CODE_SIGNING_ALLOWED=NO`; testes via `make test-smc` | não | push/PR em `master`; testes SMC com `paths` | SwiftLint no ubuntu com `paths` | tag `v*` + `workflow_dispatch` com `dry_run`; importa .p12, `notarytool` com Apple ID, `stapler`, `spctl`, `create-dmg`, `softprops/action-gh-release` |
| [Hidden Bar](https://github.com/dwarvesf/hidden) | sem `.github/` | | | | | | |
| [IINA](https://github.com/iina/iina/blob/develop/.github/workflows/ci.yml) | `xcode-27` | `DEVELOPER_DIR` por step, vindo da matrix | `xcodebuild -derivedDataPath .` + DMG como artifact | não | push/PR em `develop` | só checagem de ortografia | fora deste workflow |
| [Sparkle](https://github.com/sparkle-project/Sparkle/tree/2.x/.github/workflows) | matrix `macos-26` (Xcode 26.6) e `xcode-27` (Xcode 27.0) | `DEVELOPER_DIR` por step | `xcodebuild build-for-testing` / `test-without-building`, **inclusive UI tests**, `analyze` em PR | não | push/PR em `2.x`/`master` | `xcodebuild analyze` comenta no PR | `workflow_dispatch` cria release draft com PAT de bot |
| [swift-format](https://github.com/swiftlang/swift-format/blob/main/.github/workflows/pull_request.yml) (Apple/swiftlang) | reusable workflows de [swiftlang/github-workflows](https://github.com/swiftlang/github-workflows/blob/main/.github/workflows/swift_package_test.yml); macOS em runners **self-hosted** | `DEVELOPER_DIR=/Applications/Xcode_<v>.app/...` | `xcrun swift test` (macOS), container `swift:6.2` (Linux) | não | `pull_request` (com `ready_for_review`) | job "soundness" + swift-format | workflow próprio |
| [Nuke](https://github.com/kean/Nuke/blob/main/.github/workflows/ci.yml) | `macOS-26` | `DEVELOPER_DIR` global (Xcode 26.4) e re-execução com Xcode 26.0 | script único `.scripts/ci.sh` (o mesmo de `make ci`) | não | push `main` + PR | SwiftLint em container no ubuntu | não |
| [TCA](https://github.com/pointfreeco/swift-composable-architecture/tree/main/.github/workflows) | `macos-15` (CI), `macos-26` (format) | `sudo xcode-select` | `xcodebuild` via `make`, saída com `xcbeautify` | **DerivedData** em `actions/cache`, com `git-restore-mtime` e `IgnoreFileSystemDeviceInodeChanges` | push `main` + PR + `workflow_dispatch` | swift-format em push na `main` com auto-commit | workflow próprio |
| [AltTab](https://github.com/lwouis/alt-tab-macos/blob/master/.github/workflows/ci_cd.yml) | `macos-15` | `sudo xcode-select` (Xcode 26.0.1) | scripts shell | `setup-node` com `cache: npm` | **só push em `master`** | commitlint | tudo no mesmo job: testes, notarização, **appcast do Sparkle** com `SPARKLE_ED_PRIVATE_KEY`, semantic-release; `environment: production` |
| [MonitorControl](https://github.com/MonitorControl/MonitorControl) | sem workflows (só um `.dependabot.yml` legado) | | | | | | |
| [Hammerspoon](https://github.com/Hammerspoon/hammerspoon/blob/master/.github/workflows/ci_testbuild.yml) | `macos-15` | `maxim-lobanov/setup-xcode` (16.1.0) | scripts com `xcodebuild` | não | push `master` + PR | lint de docstrings | workflows separados (`new_tag.yml`) |
| [Loop](https://github.com/MrKai77/Loop/tree/develop/.github/workflows) | `macos-latest` (lint), `xcode-27` (dev build) | `sudo xcode-select` (Xcode 27.0) | `xcodebuild archive \| xcbeautify` | não | lint em PR com `paths`; build só `workflow_dispatch` | SwiftFormat pré-instalado, `--reporter github-actions-log` | keychain manual, `notarytool store-credentials`, `stapler`, `ncipollo/release-action` |
| [DuckDuckGo apple-browsers](https://github.com/duckduckgo/apple-browsers/blob/main/.github/workflows/macos_pr_checks.yml) | runners próprios (`[image:osx-tahoe-27, general-purpose]`) | action local que lê `.xcode-version` | `xcodebuild build-for-testing` / `test-without-building` + `xcbeautify --report junit` | SPM em `actions/cache` com chave em `Package.resolved` (só se todos os pins forem versões); cache de compilação | push com `paths` + PR + `schedule` | SwiftLint, ShellCheck, **actionlint** | dezenas de workflows dedicados |

### 1.2 Padrões observados

- **Runner.** Ninguém usa `macos-14`. Os projetos estão em `macos-15`, `macos-26` ou no novo rótulo `xcode-27`. Só Stats e Loop usam `macos-latest`, e apenas em jobs secundários.
- **Seleção do Xcode.** Três formas aparecem. A mais comum é `sudo xcode-select -s` (Stats, TCA, AltTab, Loop). A segunda é a variável `DEVELOPER_DIR` (IINA, Sparkle, Nuke e o swiftlang), que dispensa `sudo` e vale por job ou step. A terceira é `maxim-lobanov/setup-xcode` (Hammerspoon). O Rectangle usa o Xcode padrão da imagem.
- **Ferramenta de build.** Todos os apps usam `xcodebuild`, porque têm `.xcodeproj`. O único com `swift test` puro é o swiftlang, que é um pacote SwiftPM como o Pullglance.
- **Cache.** Quase ninguém faz cache. As exceções são o TCA (DerivedData) e o DuckDuckGo (pacotes SPM e cache de compilação).
- **Permissões.** Rectangle (`read-all`), IINA, Nuke, swiftlang e os testes SMC do Stats declaram `permissions` restritivo. Os demais herdam o padrão do repositório.
- **Concurrency com cancelamento.** Aparece em Stats, Nuke, TCA, swiftlang e DuckDuckGo.
- **Pinning.** **Nenhum** dos workflows estudados fixa actions por SHA; todos usam tags. Só o swiftlang usa `persist-credentials: false`. Só Nuke, DuckDuckGo e os testes SMC do Stats definem `timeout-minutes`.
- **Lint.** O lint costuma rodar no Ubuntu para não gastar concorrência de macOS. Nuke diz isso explicitamente em comentário ("On a Linux runner, so linting costs no macOS concurrency"). Loop roda o SwiftFormat que já vem na imagem macOS.
- **Release.** O padrão é um workflow separado, disparado por tag ou `workflow_dispatch`. Ele importa um certificado .p12 de secrets, roda `xcodebuild archive`/`exportArchive`, envia ao `xcrun notarytool submit --wait`, roda `stapler staple` e publica no GitHub Releases. O AltTab gera ainda o appcast do Sparkle com a chave EdDSA em secret.
- **Relato de testes.** Sparkle e Nuke sobem logs e `.xcresult` como artifact só quando há falha. O Sparkle inclui `~/Library/Logs/DiagnosticReports`. Hammerspoon usa `slidoapp/xcresulttool` com `checks: write` e Codecov. DuckDuckGo gera JUnit com `xcbeautify --report junit`.

### 1.3 Ideias que valem copiar

- **Checagem de arquivo gerado.** O Sparkle regenera arquivos e falha se `git status --porcelain` acusar diferença, com `::error::` explicando o comando a rodar. O AltTab tem `ensure_generated_files_are_up_to_date.sh`. É exatamente o caso do `review.js` do Pullglance.
- **CI igual ao local.** O Nuke põe toda a lógica num script (`.scripts/ci.sh`), e o workflow só chama esse script. Assim `make ci` local roda o mesmo que o CI.
- **Retrocompatibilidade barata.** O Nuke re-executa os testes macOS com o Xcode mais antigo suportado, dentro do mesmo job, para caber no limite de 5 jobs macOS simultâneos.
- **Separar build de teste.** Sparkle e DuckDuckGo usam `build-for-testing` e depois `test-without-building`. O equivalente no SwiftPM é `swift build --build-tests` seguido de `swift test --skip-build`.
- **Dry run de release.** O Stats aceita `dry_run` no `workflow_dispatch`, que assina e empacota sem notarizar nem publicar.

---

## 2. Imagens de runner macOS e versões de Xcode/Swift

Fonte principal: [README do actions/runner-images](https://github.com/actions/runner-images#available-images) e os READMEs de cada imagem.

| Imagem (arm64, padrão) | Rótulos | OS | Xcodes instalados | Padrão | Versão da imagem |
|---|---|---|---|---|---|
| [macOS 15 arm64](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md) | `macos-15` | 15.7.9 | 16.0–16.4, 26.0.1, 26.1.1, 26.2, 26.3 | 16.4 | 20260907 |
| [macOS 26 arm64](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md) | `macos-latest`, `macos-26` | 26.6.2 | 26.0.1, 26.1.1, 26.2, 26.3, 26.4.1, 26.5, 26.6 | 26.6 (desde [2026-07-21](https://github.com/actions/runner-images/issues/14344)) | 20260907 |
| [Xcode 27 arm64](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md) (**preview**) | `xcode-27` | 27.0.1 | 27.0, 27.1, 27.2 beta | 27.0 | 20261006 |
| macOS 14 | `macos-14` | | | | **deprecada**; brownouts em outubro, [fim em 2026-11-02](https://github.com/actions/runner-images/issues/13518) |

Também existem variantes Intel (`macos-15-intel`, `macos-26-intel`) e as "larger" (`-large`, `-xlarge`), que são sempre pagas.

Fatos relevantes:

- **`macos-latest` aponta para macOS 26 arm64.** Isso consta no README e na [doc de runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners). A migração do `-latest` é gradual, ao longo de 1 a 2 meses.
- **`xcode-27` é um rótulo novo, nomeado pelo Xcode.** Foi [anunciado em 2026-07-16](https://github.com/actions/runner-images/issues/14404) como preview. Desde 2026-09-16 roda sobre macOS 27. Rectangle, IINA, Sparkle e Loop já o usam.
- **Política de Xcode.** Cada versão de macOS suporta uma major de Xcode e todas as minors dela. Uma patch nova substitui a anterior. Betas e RCs só entram na imagem mais nova ([README, seção de políticas](https://github.com/actions/runner-images#software-and-image-support)).
- **Ferramentas pré-instaladas** nas imagens macOS 15, 26 e Xcode 27 incluem SwiftFormat 0.63, xcbeautify 3.2.1, GitHub CLI e Node.js. O Node é 22.23 no macOS 15 e 24.20 no macOS 26.

### Mapeamento Xcode → Swift

Fonte: [Apple, Xcode support](https://developer.apple.com/support/xcode/).

| Xcode | Swift | macOS mínimo para rodar o Xcode |
|---|---|---|
| 26.0 / 26.0.1 | 6.2 | Sequoia 15.6 |
| 26.1 / 26.1.1 | 6.2.1 | Sequoia 15.6 |
| 26.2 / 26.3 | **6.2.3** | Sequoia 15.6 |
| 26.4.1 / 26.5 / 26.6 | 6.3 | Tahoe 26.2 |
| 27.0 / 27.1 / 27.2 beta | 6.4 | Tahoe 26.6 |

Consequências para o Pullglance:

- **Swift 6.2 existe nas imagens `macos-15` e `macos-26`.** As duas trazem Xcode 26.0.1 a 26.3, mas nenhuma usa um deles como padrão. O padrão é 16.4 (Swift 6.1) no macOS 15 e 26.6 (Swift 6.3) no macOS 26. Por isso é obrigatório selecionar o Xcode explicitamente.
- **O ambiente local** do mantenedor tem Xcode 26.2 com Swift 6.2.3. Esse é o mesmo compilador do Xcode 26.3.
- **`swift-tools-version` diverge do requisito.** O `Package.swift` declara `swift-tools-version: 6.0`, embora o projeto exija Swift 6.2. Se for isso mesmo, subir para `6.2` faria um toolchain antigo falhar já na resolução do pacote, com mensagem clara.

---

## 3. Guia oficial de segurança e boas práticas

### 3.1 Checklist de segurança (GitHub)

Fonte principal: [Secure use reference](https://docs.github.com/en/actions/reference/security/secure-use).

1. **Token com privilégio mínimo.** Defina o `GITHUB_TOKEN` como leitura e aumente por job só onde precisar ([secure use](https://docs.github.com/en/actions/reference/security/secure-use), [permissions na sintaxe](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#permissions)). Ao declarar qualquer permissão, todas as não declaradas viram `none`. A forma `permissions: {}` zera tudo.
   - **Padrão atual.** Repositórios novos de conta pessoal nascem com token somente leitura desde [2023-02-02](https://github.blog/changelog/2023-02-02-github-actions-updating-the-default-github_token-permissions-to-read-only/). O repositório `andersonba/pullglance` hoje retorna `default_workflow_permissions: read` e `can_approve_pull_request_reviews: false`, lidos via API.
2. **Pinning de actions.**
   - A doc recomenda fixar cada action em SHA completo de commit e verificar que o SHA vem do repositório original, não de um fork.
   - Tags são aceitáveis só se você confia no autor.
   - O GitHub agora oferece **lockfile de dependências** em `.github/workflows/actions.lock`, gerado pela extensão `gh actions-lock`. A doc diz que ele "supersedes SHA pinning" e cobre dependências transitivas. Está em **public preview** ([doc](https://docs.github.com/en/actions/concepts/security/workflow-dependency-lockfiles)).
   - Existe a configuração "Require actions to be pinned to a full-length commit SHA" ([settings](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository)). No repositório ela está hoje como `sha_pinning_required: false`.
3. **Script injection.** Nunca interpole `${{ github.event.pull_request.title }}` e afins direto em `run:`. Passe o valor por uma variável de ambiente intermediária (`env: TITLE: ...` e depois `"$TITLE"`).
4. **`pull_request` vs `pull_request_target`.** Fonte: [eventos](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#pull_request).
   - Em `pull_request` vindo de fork, "secrets are not passed to the runner", com exceção do `GITHUB_TOKEN`. O token é somente leitura. PRs do Dependabot recebem o mesmo tratamento.
   - `pull_request_target` roda no contexto da branch padrão, com acesso de escrita e secrets. A doc diz: "Avoid using this event if you need to build or run code from the pull request." Os riscos citados são cache poisoning e vazamento de secrets.
5. **Aprovação para forks.** Em repo público, por padrão "all first-time contributors require approval to run workflows". Há uma opção mais rígida, "Require approval for all external contributors" ([settings](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository)).
6. **Outros itens da doc.**
   - Use `CODEOWNERS` em `.github/workflows`.
   - Prefira OIDC a segredos longos de nuvem.
   - Use `::add-mask::` para valores derivados de secrets.
   - **Não use runners self-hosted em repositório público.**
   - Use OpenSSF Scorecards e Dependabot para actions. Ressalva da doc: o Dependabot "will not create alerts for actions pinned to SHA values". As *version updates* continuam funcionando.
7. **Cache.** Fonte: [dependency caching](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching).
   - O limite padrão é 10 GB por repositório.
   - Entradas sem acesso há 7 dias são removidas.
   - Um PR lê o cache da branch base, mas grava só no escopo do merge ref. Então um PR não consegue envenenar o cache da `main`.
8. **Checks obrigatórios e filtros.** Se um workflow é pulado por `paths`/`branches`, os checks dele ficam **Pending** e bloqueiam o merge. Um job pulado por `if:` reporta sucesso ([troubleshooting required checks](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/defining-the-mergeability-of-pull-requests/troubleshooting-required-status-checks#handling-skipped-but-required-checks)).
9. **`concurrency`.** A doc mostra o padrão `group: ${{ github.head_ref || github.run_id }}` com `cancel-in-progress: true` ([sintaxe](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#concurrency)).

### 3.2 Swift no CI (GitHub e swift.org)

- **Guia oficial do GitHub para Swift** ([build and test Swift](https://docs.github.com/en/actions/tutorials/build-and-test-code/swift)).
  - O guia usa `swift-actions/setup-swift`, fixado em SHA, mais `swift build` e `swift test`.
  - Ele afirma que "the Ubuntu and macOS runners include the dependencies for building Swift packages".
  - O exemplo é genérico (Swift 5.x) e não trata de Xcode.
- **swiftlang (Apple).** A [reusable workflow oficial](https://github.com/swiftlang/github-workflows/blob/main/.github/workflows/swift_package_test.yml) faz no macOS só `DEVELOPER_DIR=/Applications/Xcode_<versão>.app/Contents/Developer` e `xcrun swift test`. Não usa setup-swift.
- **`swift test` no SwiftPM 6.2** (lido do `swift test --help` local):
  - `--xunit-output <arquivo>` gera XML.
  - `--attachments-path <dir>` grava attachments do Swift Testing. O diretório precisa existir.
  - `--parallel` vale para paralelismo de XCTest. O Swift Testing já roda em paralelo por padrão.
- **Nome do XML do Swift Testing.** Quando o XCTest também está habilitado, os resultados do Swift Testing vão para um arquivo separado, `<nome>-swift-testing.xml` ([SwiftPM #8000](https://github.com/swiftlang/swift-package-manager/issues/8000)). Há relatos de problemas de compatibilidade do XML com alguns consumidores JUnit ([#8755](https://github.com/swiftlang/swift-package-manager/issues/8755)). Não verifiquei o nome exato no Swift 6.2.3; convém confirmar no primeiro run.

### 3.3 Testes com GUI (NSHostingView) em runner hospedado

Três suítes do Pullglance renderizam SwiftUI com `NSHostingView` + `cacheDisplay`: `PopoverSnapshotTests`, `PopoverLayoutTests` e `RowRefreshRenderTests`.

- **Há sessão gráfica logada.** As imagens macOS configuram login automático na GUI: [`configure-autologin.sh`](https://github.com/actions/runner-images/blob/main/images/macos/scripts/build/configure-autologin.sh) grava `autoLoginUser` e `autoLoginUserScreenLocked=false`. Os templates Packer de macOS 15, 26 e Xcode 27 incluem esse script.
- **Permissões TCC pré-concedidas.** As imagens já liberam Accessibility e AppleEvents para o agente do runner, `bash` e `osascript` ([`configure-tccdb-macos.sh`](https://github.com/actions/runner-images/blob/main/images/macos/scripts/build/configure-tccdb-macos.sh)).
- **Evidência prática.** O Sparkle roda um esquema inteiro de **UI tests** em `macos-26` e `xcode-27` hospedados.
- **Doc de runners.** Ela não menciona GUI. Diz apenas que macOS roda com `sudo` sem senha.
- **Conclusão factual.** Desenhar uma view num bitmap com `cacheDisplay` não exige permissão de captura de tela, e a sessão está logada. Os testes devem funcionar. **Risco:** testes que comparam pixels podem divergir entre a versão de macOS do CI (26.6) e a da máquina local, por fontes e renderização. Os testes atuais checam layout e alinhamento a pixel inteiro, não comparação com imagem de referência. Ainda assim, vale observar.

---

## 4. Custos e limites para repositório público

| Item | Valor | Fonte |
|---|---|---|
| Runners padrão em repo público | gratuitos e ilimitados | [billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions), [runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) |
| Larger runners (`-large`, `-xlarge`) | sempre pagos, mesmo em repo público | [billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions) |
| Hardware do macOS padrão arm64 | 3 vCPU M1, 7 GB RAM, 14 GB SSD | [runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) |
| Hardware do Ubuntu padrão em repo público | 4 vCPU, 16 GB RAM | idem |
| `ubuntu-slim` | 1 vCPU, 5 GB, container, timeout de 15 min | idem |
| Concorrência no plano Free | 20 jobs no total, **5 jobs macOS** | [limits](https://docs.github.com/en/actions/reference/limits) |
| Duração máxima de job | 6 h | idem |
| Cache | 10 GB por repositório | [caching](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching) |

**Atenção: o repositório ainda é privado.** A API retorna `visibility: private`. Em repo privado no plano Free há 2.000 minutos por mês e 500 MB de artifacts. O minuto macOS custa US$ 0,062, contra US$ 0,006 do Linux de 2 cores, cerca de 10 vezes mais ([pricing](https://docs.github.com/en/billing/reference/actions-runner-pricing)). As páginas atuais não descrevem um multiplicador sobre os minutos incluídos. Elas listam só o preço por minuto, e a cobrança arredonda cada job para o minuto inteiro.

---

## 5. Ferramentas

| Ferramenta | Estado (2026-10-14) | Para quê |
|---|---|---|
| [zizmor](https://github.com/zizmorcore/zizmor) | ativo; v1.30.1 (2026-09-09); action oficial [`zizmorcore/zizmor-action`](https://github.com/zizmorcore/zizmor-action) v0.6.4 | Linter de segurança de workflows: `template-injection`, `unpinned-uses`, `excessive-permissions`, `artipacked` (credencial persistida pelo checkout), `cache-poisoning` etc. Sobe SARIF para code scanning, gratuito em repo público, com `security-events: write`. Também pode emitir anotações (`--format=github`) só com `contents: read` ([integração](https://docs.zizmor.sh/integrations/)). |
| [actionlint](https://github.com/rhysd/actionlint) | ativo; v1.7.12 (2026-03-30) | Valida sintaxe e expressões de workflows e roda shellcheck nos `run:`. O DuckDuckGo usa via `docker://rhysd/actionlint`. |
| Dependabot para actions | nativo | `package-ecosystem: github-actions`, `directory: /`. Suporta `groups` e `cooldown` (padrão de 3 dias; para actions só `default-days`) ([options](https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference)). Atualiza actions fixadas em SHA por *version updates*, mas não gera alertas para elas. |
| [swift-actions/setup-swift](https://github.com/swift-actions/setup-swift) | não arquivado; último release v2.4.0 (2025-11-19), último push 2026-02-28 | Baixa toolchains do swift.org. É o que a doc do GitHub usa. No macOS, app SwiftUI precisa do SDK do Xcode de qualquer jeito, e nenhum dos projetos estudados usa a action. |
| [maxim-lobanov/setup-xcode](https://github.com/maxim-lobanov/setup-xcode) | ativo; v1.7.0 (2026-03-18) | Seleciona Xcode por versão. É citada pelo próprio runner-images. |
| [xcbeautify](https://github.com/cpisciotta/xcbeautify) | ativo; 3.2.1, pré-instalado nas imagens | Formata saída de `xcodebuild` e gera JUnit. Para `swift test`, o ganho é menor. |
| `swift test --xunit-output` + reporter | nativo | Reporters comuns: [`mikepenz/action-junit-report`](https://github.com/mikepenz/action-junit-report) (v6.6.1) e [`dorny/test-reporter`](https://github.com/dorny/test-reporter) (v3.0.0). Os dois criam check runs ou anotações e pedem `checks: write`. Em PR de fork o token é só leitura, então essa parte falha ou precisa de um workflow `workflow_run` separado. |

---

## 6. Recomendação para o Pullglance

Esta seção é **opinião**, baseada nos fatos acima.

### 6.1 Desenho

- **Um workflow, `ci.yml`, com dois jobs paralelos.**
  - `swift` roda em macOS: build, testes e empacotamento do .app.
  - `web` roda em Ubuntu: typecheck, vitest, build do esbuild e checagem de que o `review.js` commitado está atualizado.
- **Runner do Swift: `macos-26`, fixado, não `macos-latest`.** O `-latest` muda sem aviso dentro de 1 a 2 meses. O `macos-15` tem o mesmo Xcode 26.2, mas o macOS 26 fica mais perto do sistema em que o app é usado. Isso importa para os testes de renderização.
- **Xcode por `DEVELOPER_DIR`, fixado em 26.2.**
  - É o mesmo Xcode e o mesmo Swift 6.2.3 da máquina local. Dispensa `sudo` e action de terceiro, como fazem swiftlang, Nuke e Sparkle.
  - Ao atualizar o Xcode local, atualize esta linha junto.
  - O 26.3 dá o mesmo compilador, se preferir a patch mais nova.
- **Runner do Web: `ubuntu-24.04`, fixado.** Os 4 vCPU deixam a etapa rápida, e ela não ocupa vaga de macOS. O `build.mjs` importa TypeScript direto, o que exige Node 22.18+ ou 24. Por isso o job fixa Node 24, a mesma major usada localmente (24.1).
- **Checagem de frescor.** O job web roda o próprio `Scripts/build-review-js.sh`, o mesmo do dia a dia. Depois falha se `git status --porcelain -- Sources/Pullglance/Resources` acusar mudança, no estilo do Sparkle. Isso cobre o `review.js` e o `review-presets.json`.
  - **Risco a confirmar no primeiro run:** o esbuild precisa gerar bytes idênticos em Linux e macOS. Isso é esperado com a mesma versão travada no `package-lock.json`. Se falhar, a solução mais simples é rodar o job `web` em `macos-26`.
- **Triggers.** `push` em `main`, `pull_request` sem filtro de branch e `workflow_dispatch`.
  - Não use filtro de `paths` no gatilho. Um check obrigatório pulado fica Pending para sempre. O custo extra é zero em repo público.
- **Permissões.** `contents: read` no topo do workflow e nada além disso. Nenhum job precisa escrever.
- **Concurrency.** O grupo é o workflow mais o número do PR, ou o ref. `cancel-in-progress` vale só para PR, para que cada push na `main` termine e deixe histórico verde ou vermelho por commit.
- **Cache.**
  - **Nenhum cache de SwiftPM.** O `Package.swift` não tem dependências externas, então não há o que resolver. Cachear `.build` traz risco de artefato velho por pouco ganho. Cache de DerivedData, como no TCA, só compensa em projetos grandes.
  - **No job web, só o cache de npm do `setup-node`.** Ele usa o `Web/package-lock.json` como chave.
- **Pinning.**
  - Todas as actions vão fixadas em SHA com a tag em comentário. Os SHAs abaixo foram resolvidos via API em 2026-10-14.
  - O checkout usa `persist-credentials: false`, que evita o achado `artipacked` do zizmor.
  - Use Dependabot para mantê-las atualizadas.
  - Quando o lockfile `actions.lock` sair de preview, vale migrar.
- **Timeouts.** São 30 min para o Swift e 10 min para o Web. O padrão é 360 min, e um teste travado queimaria a vaga de macOS.
- **Diagnóstico de falhas.**
  - O XML do xUnit e os attachments do Swift Testing (`--attachments-path`) sobem como artifact só em caso de falha.
  - Os testes de snapshot podem gravar a imagem renderizada como attachment, e assim a imagem aparece no artifact.
  - Sem reporter de terceiros por enquanto. A saída do Swift Testing no log é legível, e reporters exigem `checks: write`, que não funciona em PR de fork.
- **Empacotamento.**
  - Rodar `Scripts/make-app.sh` valida o build release e o bundle. O build release otimizado pode expor erros que o debug não mostra.
  - Em push na `main`, o .app vai como artifact zipado com `ditto`, porque o `upload-artifact` não preserva permissões nem bundles.
- **Fora do escopo agora.**
  - **Lint:** o projeto não tem config de SwiftLint ou SwiftFormat. O SwiftFormat já vem na imagem macOS, se quiser adicionar depois.
  - **Warnings como erro:** `-Xswiftc -warnings-as-errors` pode virar um passo depois de confirmar que o build está limpo.
  - **Canário com Swift 6.3:** um job extra com Xcode 26.6 e `continue-on-error: true` avisaria cedo sobre quebras de compilador.
  - **Release com notarização:** pede conta Apple Developer. Seria um workflow separado, `release.yml`, disparado por tag, com `environment` protegido e secrets, no modelo do Stats ou do Loop.

### 6.2 `.github/workflows/ci.yml` proposto

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

jobs:
  swift:
    name: Swift (macOS)
    runs-on: macos-26
    timeout-minutes: 30
    env:
      # Xcode 26.2 = Swift 6.2.3, same as local. Keep in sync with the Xcode you develop with.
      DEVELOPER_DIR: /Applications/Xcode_26.2.app/Contents/Developer
    steps:
      - name: Checkout
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false

      - name: Toolchain
        run: |
          sw_vers
          xcodebuild -version
          swift --version

      - name: Build
        run: swift build --build-tests

      - name: Test
        run: |
          mkdir -p .build/ci/results .build/ci/attachments
          swift test --skip-build \
            --xunit-output .build/ci/results/junit.xml \
            --attachments-path .build/ci/attachments

      - name: Package Pullglance.app
        run: |
          Scripts/make-app.sh
          ditto -c -k --keepParent build/Pullglance.app build/Pullglance.zip

      - name: Upload test results
        if: failure()
        uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2
        with:
          name: swift-test-results
          path: |
            .build/ci/
            ~/Library/Logs/DiagnosticReports/
          if-no-files-found: ignore
          retention-days: 7

      - name: Upload app
        if: github.event_name == 'push'
        uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2
        with:
          name: Pullglance-${{ github.sha }}
          path: build/Pullglance.zip
          if-no-files-found: error
          retention-days: 14

  web:
    name: Web (review.js)
    runs-on: ubuntu-24.04
    timeout-minutes: 10
    steps:
      - name: Checkout
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false

      - name: Set up Node
        uses: actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1 # v7.1.0
        with:
          node-version: 24
          cache: npm
          cache-dependency-path: Web/package-lock.json

      - name: Install
        working-directory: Web
        run: npm ci --no-audit --no-fund

      - name: Typecheck, test and build
        run: Scripts/build-review-js.sh

      - name: Check that the committed bundle is up to date
        run: |
          changes="$(git status --porcelain -- Sources/Pullglance/Resources)"
          if [ -n "$changes" ]; then
            echo "::error::Sources/Pullglance/Resources is out of date with Web/. Run Scripts/build-review-js.sh and commit the result."
            echo "$changes"
            git diff --stat -- Sources/Pullglance/Resources
            exit 1
          fi
```

Notas sobre o YAML:

- **Validação.** Este YAML e o do zizmor abaixo passaram no actionlint 1.7.12 e no zizmor 1.30.1 em modo offline, rodados localmente num diretório temporário, sem achados. Eles ainda não rodaram no GitHub.
- **`npm ci` antes do script.** O `build-review-js.sh` só roda `npm install` quando falta `node_modules`. Com o `npm ci` antes, o CI instala exatamente o lockfile.
- **Saída do script.** O `ls -la` no fim do script não atrapalha.
- **Branch protection.** Para exigir o CI no merge, marque como obrigatórios os checks "Swift (macOS)" e "Web (review.js)". Os nomes de exibição dos jobs são os nomes dos checks.
- **Aprovação de forks.** Ao tornar o repo público, considere "Require approval for all external contributors". O padrão só exige aprovação na primeira contribuição.

### 6.3 Arquivos complementares sugeridos

`.github/dependabot.yml`:

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
    cooldown:
      default-days: 7
    groups:
      actions:
        patterns: ["*"]

  - package-ecosystem: npm
    directory: /Web
    schedule:
      interval: weekly
    cooldown:
      default-days: 7
    groups:
      web-dev:
        dependency-type: development
        update-types: [minor, patch]
```

Atualizações de npm em `Web/` mudam o `review.js` gerado. Um PR do Dependabot vai falhar na checagem de frescor até alguém rodar o script e commitar. Isso é o comportamento desejado, mas significa que esses PRs não são "merge com um clique".

`.github/workflows/zizmor.yml`, segundo a [integração oficial](https://docs.zizmor.sh/integrations/), com SARIF em code scanning, gratuito em repo público:

```yaml
name: zizmor

on:
  push:
    branches: [main]
  pull_request:

permissions: {}

jobs:
  zizmor:
    name: zizmor
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    permissions:
      security-events: write
    steps:
      - name: Checkout
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false

      - name: Run zizmor
        uses: zizmorcore/zizmor-action@cc914d7f3750a2d13d75c7f184a1060aa0e9d482 # v0.6.4
```

No modo SARIF o job sai sempre com código 0. Os achados aparecem em Security → Code scanning, e para bloquear merge é preciso uma regra de code scanning. Enquanto o repo for privado sem Advanced Security, use o modo de anotações (`--format=github`), que só precisa de `contents: read`.
