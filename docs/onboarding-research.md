# Onboarding em apps de menu bar em Swift: o que existe e o que copiar

Levantamento de 2026-10-15, verificado via `gh api` (árvore do repositório, conteúdo dos arquivos, stars, último push) ou pela página do repositório. Tamanhos são bytes de arquivos `.swift` dentro da pasta de onboarding.

## Exemplos verificados

| App | Repo | Stars | Último push | Onde vive | Arquivos / bytes | O que faz |
|---|---|---|---|---|---|---|
| Ice | https://github.com/jordanbaird/Ice | 29,8k | 2026-10-06 | `Ice/Permissions/` | 4 / 13,6k | Janela de permissões, sem tour |
| Stats | https://github.com/exelban/stats | 42,6k | 2026-10-14 | `Stats/Views/Setup.swift` | 1 / 26,5k | Wizard AppKit de 5 páginas |
| AltTab | https://github.com/lwouis/alt-tab-macos | 16,4k | 2026-10-13 | `src/secondary-windows/permission-window/` | 7 / 72k | Janela de permissões + popover no ícone |
| MeetingBar | https://github.com/leits/MeetingBar | 5,4k | 2026-10-13 | `MeetingBar/Onboarding/` | 5 / 24,7k | Wizard SwiftUI de 6 passos |
| TRex | https://github.com/amebalabs/TRex | 1,9k | 2026-09-29 | `TRex/App/UI/Onboarding/` | 26 / 47,5k | Welcome + setup + tutorial |
| DockDoor | https://github.com/ejbills/DockDoor | 6,4k | 2026-10-11 | `DockDoor/Views/Intro/` | 6 / 15,8k | Overlay cinemático + 3 abas |
| boring.notch | https://github.com/TheBoredTeam/boring.notch | 11,0k | 2026-10-15 | `boringNotch/components/Onboarding/` | 6 / 20,4k | Welcome + 4 permissões + fim |
| BatFi | https://github.com/rurza/BatFi | 591 | 2026-10-05 | `BatFiKit/Sources/Onboarding/` | 12 / 23,8k | Módulo SPM próprio, 3 telas |
| Cork | https://github.com/buresdv/Cork | 4,7k | 2026-10-14 | `Cork/Views/Onboarding/` | 7 / 15,6k | Uma tela com slider de "nível" |
| Rectangle | https://github.com/rxhanson/Rectangle | 30,1k | 2026-10-14 | `Rectangle/WelcomeWindow/` | 1 / 4,5k | Uma escolha (atalhos) |
| Keyboard Cowboy | https://github.com/zenangst/KeyboardCowboy | 2,3k | 2026-09-12 | `App/Sources/UI/Views/Onboarding/` | 2 / 9k | Splash animado + texto de permissão |
| MonitorControl | https://github.com/MonitorControl/MonitorControl | 34,5k | 2026-10-14 | `View Controllers/Onboarding/` | 1 / 1,3k | Storyboard: login item + botão de permissão |

Detalhes que importam:

- **Ice** não tem welcome. Tem um objeto `Permission` (título, bullets, `isRequired`, URL do painel, closures `check`/`request`) e a view faz `ForEach` sobre a lista. Um `Timer` de 1 s reavalia cada permissão e o botão vira "Continue in Limited Mode" quando só as obrigatórias estão ok. Nenhum estado "visto" persistido: a janela aparece sempre que falta permissão.
- **Stats** é AppKit puro: `SetupContainer` com array `pages = [welcome, preset, startAtLogin, update, end]` e botões Previous/Next. Janela 700x440.
- **AltTab** é o mais elaborado e o mais caro. `PermissionFlow` é um enum puro, testável sem AppKit, que decide qual passo está ativo. Ilustrações desenhadas em código para seguir cor de destaque e aparência. Sem botão de fechar, de propósito. Depois da permissão, um popover ancorado no ícone da menu bar espera o usuário usar o atalho e só então mostra "That's it". Persiste `onboardingShortcutUsed`.
- **MeetingBar** é o modelo mais próximo do Pullglance: `enum OnboardingStep`, router observável, barra de progresso de cápsulas, `OnboardingFooter` compartilhado (Back, hint, spinner, botão primário), telas com SF Symbols grandes. Persiste `onboardingCompleted`. Janela borderless com fundo arredondado desenhado pela view.
- **TRex** tem a animação mais amigável só com SwiftUI: opacidade + offset escalonados por delay, emojis como mascote, cards de features vindos de `Feature.all`. A permissão faz polling a cada 1 s e para quando concedida. Custo: 26 arquivos.
- **DockDoor** abre um `NSPanel` de tela cheia com gradiente e som, depois uma janela 600x320 com 3 abas. `PermissionsChecker` com `Timer` de 1 s. Permissão opcional negada desliga a feature correspondente.
- **boring.notch** reaproveita uma única `PermissionRequestView` quatro vezes, com "Not Now" em cada. Tem `WhatsNewView.swift`, mas é um stub.
- **BatFi** isola o onboarding num target SPM com `PageView`, vídeos, confete e som. Persiste `onboardingIsDone`.
- **Cork**: uma tela com slider "básico → avançado" que escreve dezenas de defaults. Não verifica o Homebrew no onboarding.
- **Rectangle**: uma janela modal com dois botões. Persiste `wasWelcomeDisplayed`.
- **Keyboard Cowboy**: splash com blobs em `Canvas` animados e uma tela de permissão em texto.
- **MonitorControl**: um view controller de storyboard com toggle de login item e botão de permissão.

**Sem onboarding real**: Maccy, Loop, Latest, Hidden Bar, Mochi Diffusion, SwiftBar, NotchDrop. CodeEdit tem uma "Welcome window" de projetos recentes (https://github.com/CodeEditApp/WelcomeWindow), que é um launcher, não um tour.

## Pacotes Swift

| Pacote | Stars | Último commit | macOS | Serve para menu bar? | Risco |
|---|---|---|---|---|---|
| https://github.com/SvenTiigi/WhatsNewKit | 4,4k | 2024-04-30 | 11+ | Sim, data-driven, store em UserDefaults | Alto: sem commit há 2,5 anos |
| https://github.com/danielsaidi/OnboardingKit | 1,3k | 2026-08-06 | 15+ | Sim; depende de `PageView` | Médio: um mantenedor, majors frequentes |
| https://github.com/exyte/ConcentricOnboarding | 1,6k | 2026-07-08 | só iOS | Não | n/a |
| https://github.com/demianturner/DTOnboarding | 29 | 2025-10-02 | 10.14+ | AppKit page controller | Alto: minúsculo |
| https://github.com/arpitagarwal1301/PermissionPilot | 5 | 2026-09-29 | 12+ | Só permissões TCC | Alto: muito novo |
| https://github.com/simibac/ConfettiSwiftUI | 2,5k | 2026-01-05 | 11+ | Só confete | Baixo, mas é uma dep a mais |

Nenhum pacote cobre "verificar uma CLI externa e guiar a correção". Isso é código próprio em todos os apps.

## Padrões recorrentes

- **Janela dedicada domina**: 10 dos 12. Inline só no segundo tempo do AltTab.
- **Checklist com status ao vivo** para permissões: `Timer` de 1 s, parado ao conceder.
- **Animações**: nenhum usa Lottie. Opacidade/offset com delay, `Canvas` em loop, `CAEmitterLayer`, confete, ilustrações em código, som.
- **Mascote**: só os emojis do TRex. Os demais usam o ícone do app.
- **What's new** quase nunca compartilha código com o onboarding.
- **Pular**: permissão opcional tem "Not Now"; obrigatória só oferece Quit.
- **Estado "visto"**: sempre um valor em UserDefaults.

## Recomendação adotada

Janela dedicada, data-driven, sem dependências (ver `docs/superpowers/specs/2026-10-15-onboarding-design.md`). Inline no popover foi descartado: o popover fecha quando a pessoa clica no Terminal para rodar `gh auth login`. OnboardingKit só valeria se paginação por gesto virasse requisito.
