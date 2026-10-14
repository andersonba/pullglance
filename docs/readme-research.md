# Pesquisa: READMEs de apps macOS open source

Coletado em 2026-10-14 via `gh api repos/<repo>/readme` (README renderizado na branch padrão). Linhas = `wc -l`. "Imagens" conta `<img>`/`![` fora de badges shields.io (inclui ícone, avatares e logos). Estrelas no dia da coleta.

Convenção: **Fato** = observado na fonte. **Opinião** = minha leitura.

## (a) Apps estudados

| App (★) | Linhas | Primeira tela | Badges | Instalação | Features | Imagens | Seções extras |
|---|---|---|---|---|---|---|---|
| [Ice](https://github.com/jordanbaird/Ice) (29,8k) | 112 | Ícone + parágrafo de pitch + banner | 6 (download, platform, requirements, sponsor, website, license) + botão Buy Me a Coffee | zip do Release + `brew install --cask` | Checklist longo "Features/Roadmap" com `[x]`/`[ ]` | 8 (banner + galeria) | "Why macOS 14+", Gallery, License |
| [Maccy](https://github.com/p0deje/Maccy) (21,9k) | 170 | Aviso de sites falsos, logo, pitch de 2 linhas, requisito de macOS | 2 (downloads, build) | Release + brew | 5 bullets de uma palavra ("Lightweight and fast", "Keyboard-first"…) | 1 logo, **nenhum screenshot** | ToC, Usage, Advanced, FAQ (5), Translations, Motivation, License |
| [Rectangle](https://github.com/rxhanson/Rectangle) (30,1k) | 251 | Título + 1 linha ("window management app… based on Spectacle") + 1 screenshot | 0 | Site/Release + brew cask | Manual de uso longo | 1 | System Requirements (com links para versões antigas), Known Issues, Troubleshooting, Uninstall, Contributing, Credits |
| [Loop](https://github.com/MrKai77/Loop) (11,8k) | 613 | Ícone + tagline "Window management made elegant." + link de download + compatibilidade + GIF | 5 (for-the-badge: Discord, license, stars…) | zip direto + brew | Subseções longas por feature, exemplos shell/AppleScript | 2 (ícone + GIF demo) | Usage, FAQ, Contributing |
| [Stats](https://github.com/exelban/stats) (42,6k) | 167 | Ícone + 2 screenshots (menu bar e popups) + 1 linha "macOS system monitor in your menu bar" | 0 | dmg + brew + headless + uninstall + legacy | Lista | 3 | Requirements, FAQs (~10), "Open source, but not open contribution", idiomas, License |
| [AltTab](https://github.com/lwouis/alt-tab-macos) (16,4k) | **7** | Um único SVG-card linkando para alt-tab.app | 0 (SVG próprio) | Só no site | Só no site | 2 SVG | Nenhuma; tudo no site |
| [MonitorControl](https://github.com/MonitorControl/MonitorControl) (34,5k) | 142 | Ícone à esquerda + 2 linhas + botão "Download for macOS" + screenshot grande | 4 | Release + brew | Lista + screenshots de Settings | 7 | Compatibilidade, displays suportados, Build, Credits |
| [Hidden Bar](https://github.com/dwarvesf/hidden) (15,2k) | 86 | Ícone + 1 linha + 2 screenshots lado a lado (400px) | 5 | App Store + brew | Usage com GIF | 12 (inclui avatares de contribuidores) | Requirements, "You may also like", License |
| [Latest](https://github.com/mangerlahn/Latest) (4,8k) | 69 | Parágrafo em prosa + 1 screenshot | 1 (Weblate) | Download + brew cask + build | Prosa | 1 | Contribution (tradução, código), Donation |
| [Mos](https://github.com/Caldis/Mos) (21,6k) | 133 | Ícone + 1 linha + 4 badges flat-square + seletor de idioma | 4 | Manual + brew | "Por que Mos" + destaques curtos | 6 | Screenshots, Contribuição ("bem-vindo" / "não será mergeado"), Agradecimentos, License |
| [DockDoor](https://github.com/ejbills/DockDoor) (6,3k) | 175 | ToC + ícone + downloads + badges de stack (Swift, Xcode, Git, macOS) | 6 | dmg + brew | Subseções por feature | 13 | Privacy, Pro, "Works with", Contributing |
| [Clop](https://github.com/FuzzyIdeas/Clop) (1,8k) | 107 | Ícone + título mono + subtítulo + tagline "Copy large, paste small, send fast" + botão de download | 0 | dmg (botão) | Seções de marketing, uma por benefício | 2 | Free vs Pro, Technical details |
| [Gifski](https://github.com/sindresorhus/Gifski) (8,6k) | 167 | Ícone centralizado + 1 linha em negrito | 0 | App Store | Lista + tips | 7 | Screenshots, Building, FAQ, Press, Built with, Maintainers, Related, License |
| [Plash](https://github.com/sindresorhus/Plash) (4,0k) | **31** | Ícone + 1 linha em negrito | 0 | Link para o site | Nenhuma | 1 | "Where is the source code?" (deixou de ser open source) |
| [AeroSpace](https://github.com/nikitabobko/AeroSpace) (23,5k) | 180 | Título + badge de build + ícone à direita + 1 linha + links para vídeos e docs no site | 1 (CI) | brew | Lista curta "Key features" | 2 | Project status, Project values, macOS compatibility, Related projects |
| [Trailer](https://github.com/ptsochantaris/trailer) (1,2k), app de PRs na menu bar | 34 | Lista de links para binários/site | 0 | Site | Nenhuma | 0 | License |
| [CodexBar](https://github.com/steipete/CodexBar) (22,5k), menu bar | 329 | Título + tagline + 7 badges + imagem social + 1 parágrafo + screenshot do popover (520px) | 7 | brew tap + Release | "Why" com 4 bullets em negrito, depois lista de providers | 2 | Providers (longa), docs/ por provider |

KeyboardCleanTool (sindresorhus) não tem repositório público. CleanShot é fechado. Nenhum dos READMEs usa `<picture>`/`prefers-color-scheme` para screenshots light/dark (grep vazio).

## (b) Padrões e anti-padrões

### Padrões compartilhados pelos melhores (fato + leitura)

1. **Uma frase de pitch, imediatamente sob o nome.** Stats, Gifski, Plash, Loop, Hidden Bar, Mos e AeroSpace cabem em uma linha. Maccy e MonitorControl usam duas.
2. **Imagem real do app logo no topo.** Stats mostra dois prints na primeira tela. Rectangle, Hidden Bar, MonitorControl e CodexBar põem um screenshot antes de qualquer seção. Loop usa um GIF.
3. **Instalação em duas linhas.** Quase todos oferecem download do último Release mais `brew install --cask`. O link vai para `releases/latest`, não para uma versão fixa.
4. **Features curtas ou nenhuma.** Maccy resume o app em 5 bullets de três palavras. CodexBar usa 4 bullets com o benefício em negrito. Plash, AltTab e Trailer não listam features.
5. **Detalhe mora fora do README.** AltTab (7 linhas) e AeroSpace mandam para o site. CodexBar tem `docs/` por provider. GitHub diz que "longer documentation is best suited for wikis" ([About READMEs](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes)).
6. **Política de contribuição explícita e curta.** Stats ("Open source, but not open contribution") e Mos ("bem-vindo" / "não será mergeado") dizem o que aceitam. Isso evita PRs indesejados de projetos de um mantenedor só.
7. **Requisito de sistema num lugar só.** Ice e Hidden Bar usam um badge. Rectangle usa uma seção que linka a última versão para macOS antigos.
8. **Funil de leitura.** Do geral para o específico, com créditos e licença no fim. A Art of README chama isso de "cognitive funneling" e afirma que "the ideal README is as short as it can be without being any shorter" ([art-of-readme](https://github.com/hackergrrl/art-of-readme), espelho legível em [bradparks/art-of-readme](https://github.com/bradparks/art-of-readme)).

### Anti-padrões

1. **Catálogo de features ou roadmap no README.** O Ice mantém um checklist de roadmap e uma nota "currently in active development". O último Release dele é 0.11.12, de 2024-10-29, dois anos antes desta coleta. *Opinião:* um checklist assim envelhece sem ninguém perceber.
2. **Números embutidos em texto ou imagem.** O alt text da imagem social do CodexBar diz "103 providers". O SVG do AltTab diz "7.4M downloads — 15K GitHub stars". Cada número precisa ser refeito à mão.
3. **Muro de badges de vaidade.** O DockDoor tem badges de stack (Git, Xcode) que não informam nada ao usuário. O Loop usa badges for-the-badge grandes acima da dobra.
4. **Manual de uso dentro do README.** O Loop tem 613 linhas, com exemplos de shell/AppleScript. O Rectangle tem 251, com preferências ocultas e troubleshooting. *Opinião:* funciona para apps maduros com muitos usuários, mas custa manutenção.
5. **Listas que crescem com o tempo.** O Stats lista idiomas e tradutores, e o Hidden Bar mostra avatares de contribuidores. As duas listas só aumentam.

## (c) Como projetos "vibe coded" dizem isso

| Projeto | Frase | Cita modelo? | Observação |
|---|---|---|---|
| [XanderStrike/endless-wiki](https://github.com/XanderStrike/endless-wiki) (179★) | "_A vibe coded experiment in hallucination._" logo abaixo do título | Não | Uma linha, em itálico, com humor |
| [ahmetesad/micboost](https://github.com/ahmetesad/micboost) (2★), menu bar | Na descrição: "A simple, vibe-coded macOS menu bar app…". Seção "Vibe Coded": "built quickly with the help of AI… It's not a professional audio workstation, just a simple tool that works." | Não | Pede desculpas antecipadas |
| [xJacooobx/CloudLink](https://github.com/xJacooobx/CloudLink) (2★) | "entirely vibe coded (initially made using Fable 5) and not a representation of my own work." | Sim | Disclaimer defensivo |
| [mrexodia/github-backup-browser](https://github.com/mrexodia/github-backup-browser) (5★) | "**Note**: This project was 100% vibe coded." Linka a sessão do agente, o modelo, o tempo e os tokens | Sim, em detalhe | Transparência total |
| [nlothian/Vibe-Prolog](https://github.com/nlothian/Vibe-Prolog) (56★) | Conta a história ("accidently vibe coded a prolog interpreter on my phone") | Sim (Claude Code, Codex) | Narrativo, piadas |
| [sg2295/claude-status](https://github.com/sg2295/claude-status) (2★), menu bar | Na descrição: "A vibe-coded macOS menu bar app". O README não repete | Não | A descrição do repo carrega o rótulo |
| [steipete/CodexBar](https://github.com/steipete/CodexBar) (22,5k) | Nenhuma menção a IA na autoria | — | Projeto popular que não declara |

**Reação da comunidade (só observações):**
- Em [digital-grease/fauxx#8](https://github.com/digital-grease/fauxx/issues/8), alguém abriu "Clarify use of LLMs" ao achar um CLAUDE.md no histórico. O tom foi de desconfiança, e o autor removeu o arquivo do histórico. Um comentário resume a preocupação: o autor perde interesse e não mantém o código.
- Em [sam1am/anyapk#13](https://github.com/sam1am/anyapk/issues/13), o IzzyOnDroid diz: "We do not accept 'vibe coded' apps". A política foi citada ao ver "Claude" como contribuidor.
- A busca não achou issues hostis em repos que se declaram abertamente em uma linha, como endless-wiki e micboost. *Opinião:* nesses casos a crítica aparece quando o uso de IA é descoberto, não quando é declarado.
- Fora do GitHub, há comunidades que recusam código feito por IA. Exemplo: [Minecraft-Community-Edition/client](https://github.com/Minecraft-Community-Edition/client) diz "Fully vibe coded implementations are not okay."

*Opinião para o Pullglance:* "Vibe coded." como última frase do pitch está alinhado ao endless-wiki, que é o caso mais limpo. Não use seção de disclaimer nem nome de modelo. Também não peça desculpas ("not professional"). A declaração honesta e curta é a postura menos atacada nas amostras.

## (d) Estrutura recomendada para o Pullglance (≤ 60 linhas)

Em ordem:

1. **Ícone + nome centralizados.** Use o ícone gerado por Scripts/make-icon.swift, com 128px.
2. **Pitch de uma linha.** "Your pull requests and review requests at a glance, in the macOS menu bar. Vibe coded." Essa é a frase atual, sem mudanças.
3. **Badges, no máximo 3.** Use latest release, macOS 15+ e license. Os três são dinâmicos ou estáveis. Não ponha badge de CI na primeira tela.
4. **Hero screenshot.** Mostre o popover aberto, ancorado à menu bar real, com o número no ícone.
5. **Um parágrafo "Como funciona".** Explique em duas frases que o app usa o `gh` já logado, sem OAuth, servidor ou token próprio. É o diferencial e não envelhece.
6. **Por que, com 3 ou 4 bullets de benefício.** Por exemplo: ver o que depende de você, agir sem abrir o navegador, revisar numa janela própria, triagem pelo teclado. Descreva benefícios, nunca botões.
7. **Segunda imagem opcional.** Mostre a janela de review ou o menu de ações.
8. **Install.** Requisitos (macOS 15+, `gh auth login`) e um bloco de código. Use brew cask quando existir. Até lá, use o link para `releases/latest` e o build via `Scripts/make-app.sh --install`.
9. **Build from source.** Use 3 linhas de código (`swift run`, `swift test`).
10. **Privacy.** Uma frase sobre o que fica em disco: preferências, cache de avatares e log sem conteúdo.
11. **Contributing.** Uma ou duas frases no estilo Stats/Mos: issues bem-vindas e PRs grandes só depois de discutir.
12. **License.** "MIT."

Fica fora: a lista de seções, a lista de abas do Settings, os atalhos, os intervalos de refresh, as queries GraphQL e as regras de merge e de delete branch.

**Screenshots:**
- **Quantidade:** 1 hero obrigatório, mais 1 opcional. O Stats tem 2, e o Rectangle e o Hidden Bar têm 1 ou 2. *Opinião:* com mais de 2 imagens, o README precisa ser refeito a cada mudança de UI.
- **O que mostrar:** o popover com as seções preenchidas, pelo menos um PR em "Needs action" e um "Ready to merge", e o número na menu bar. Isso explica o app sem texto.
- **Dados fictícios são obrigatórios.** Scripts/snapshot.sh usa os dados reais do `gh`, segundo o comentário no próprio script. Os prints precisam vir de um modo ou fixture com repos, autores e títulos inventados.
- **Enquadramento:** mostre um recorte de tela que inclua a faixa da menu bar, de preferência a ponta direita com outros ícones do sistema, mais o popover e um pouco do wallpaper. Assim fica claro que é um app de menu bar. Não use moldura de janela falsa. Exporte em Retina 2x, mas exiba com `width` entre 480 e 520px, como o CodexBar faz com 520. Prefira PNG e evite GIF, porque o GIF do Loop é a imagem mais pesada da amostra.
- **Light/dark:** o GitHub suporta `<picture>` com `prefers-color-scheme` ([docs](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#specifying-the-theme-an-image-is-shown-to)). Nenhum app da amostra usa. *Opinião:* vale fazer só para o hero, porque o recurso dá o "visual novo" pedido. Mas isso dobra o custo de atualizar. Se for gerar à mão, fique com uma versão só, em dark ou light.
- **Local:** guarde em `docs/images/` no repo, com caminho relativo. Imagens anexadas via user-attachments, como Ice e Rectangle fazem, não são versionadas junto com o código.

## (e) Como evitar que envelheça

**O que NÃO pôr no README:**
- Listas de seções, abas de Settings, atalhos de teclado e itens de menu de contexto. Eles mudam a cada feature, e o atual README perde a validade justamente por isso.
- Números como intervalos de refresh, tamanhos de página das queries, contagem de stars ou downloads e versões fixas.
- Roadmap ou checklist. Use Issues ou Milestones.
- Detalhes de implementação, como as queries GraphQL e a lógica de delete branch em stacks.
- Lista de idiomas e de contribuidores.

**Onde isso deve morar:**
- **A própria UI.** O app já tem Settings e tooltips. *Opinião:* o README pode dizer "tudo está em Settings (⌘,)".
- **GitHub Releases.** As notas por versão substituem o "o que há de novo". Linke sempre `releases/latest`.
- **Um `docs/` curto.** Pode ter `docs/how-it-works.md` (queries, merge, dados em disco) e `docs/shortcuts.md` se o teclado for importante. O README linka em uma linha. Isso segue a recomendação do GitHub de mover docs longas para fora.
- **`CONTRIBUTING.md`.** Coloque ali build, testes, snapshot e política de PR. No README fica uma frase.

**Mecanismos:**
- Gere os screenshots por script a partir de fixtures fictícias. Assim a regravação vira um comando quando a UI mudar.
- Use só badges dinâmicos (release, license). Não use texto que exija edição manual.
- Teste mental: se uma frase do README muda quando uma feature muda, ela está no lugar errado.
