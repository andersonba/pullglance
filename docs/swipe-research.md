# Swipe para revelar ações nas linhas do popover — pesquisa e recomendação

Ambiente: macOS 27.0 (26A428), Xcode 26.2 (SDK MacOSX26.2), Swift 6.2.3, pacote SwiftPM puro, `MenuBarExtra(.window)`, popover de 380 pt.
Protótipos em `Prototypes/Swipe/` (pacote SwiftPM independente). Integração proposta já aplicada no worktree (não commitada): `Sources/Pullglance/UI/SwipeActionsRow.swift` (novo), `PopoverView.swift`, `PRRow.swift`, `App/PullglanceApp.swift`, `Resources/*/Localizable.strings`.

## Resumo executivo

A recomendação é **não usar `List`/`swipeActions` nem `NSTableView`**, e sim transformar cada linha num `ScrollView(.horizontal)` do SwiftUI cujo conteúdo é `[linha | tiles de ação]`: o AppKit roteia o gesto de dois dedos pelo eixo dominante (vertical vai para a lista, horizontal desliza a linha com inércia e elástico nativos do `NSScrollView`), um `ScrollTargetBehavior` faz o snap aberto/fechado, e a estrutura `ScrollView { VStack }` atual — com a medição de altura via `onGeometryChange` e o visual sem separadores — permanece intocada. Foi a única abordagem que consegui **provar de ponta a ponta** com eventos de trackpad sintéticos e capturas em PNG, inclusive dentro do `PopoverView` real com fixtures: revela os três tiles (ícone + texto), faz snap em 192 pt, o scroll vertical sobre outra linha rola a lista e fecha a linha aberta, roda de mouse legada (vertical e horizontal) não deixa a linha meio aberta, "abrir A e deslizar B" termina só com B aberta, e os 144 testes do pacote continuam passando. Dois achados relevantes no caminho: (1) a `List` do SwiftUI neste macOS 27 **esconde os separadores** quando `.listRowSeparator(.hidden)` é aplicado **em cada linha** (não na `List`), mas mantém ~9 pt de recuo extra mesmo com `listRowInsets(EdgeInsets())`, e por baixo o `swipeActions` dela é exatamente o row-action do `NSTableView` (botões AppKit só com título/imagem, sem tiles custom); (2) com barras de rolagem legadas ("Sempre" ou mouse USB conectado) o SwiftUI reserva ~17 pt sob cada `ScrollView` horizontal — resolvido forçando scrollers overlay no domínio de defaults do app (`AppleShowScrollBars = WhenScrolling`, verificado no protótipo). O que **não** verifiquei: a sensação com trackpad/Magic Mouse reais (momentum, gestos diagonais), o comportamento dentro do painel não ativável do `MenuBarExtra` e VoiceOver — isso precisa de um teste manual de alguns minutos antes de mergear.

## Como testei (e os limites)

- `screencapture` está sem permissão de gravação de tela nesta máquina ("could not create image from display"). Usei `NSView.cacheDisplay(in:to:)` para renderizar a janela em PNG de dentro do processo (funciona para AppKit e SwiftUI; capturas em `/tmp/swipe-proto/*.png`).
- Gestos de trackpad sintéticos: `CGEvent(scrollWheelEvent2Source:units:.pixel…)` com `scrollWheelEventScrollPhase` (valores CG: began=1, changed=2, ended=4, mayBegin=128), `scrollWheelEventIsContinuous=1`, deltas precisos e o campo 137 (`isDirectionInvertedFromDevice`, como um trackpad com scroll natural), enfileirados com `NSApp.postEvent` e roteados para a janela por uma subclasse de `NSApplication` (eventos vindos de `CGEvent` chegam sem `window`). Cliques via `NSEvent.mouseEvent` enfileirados (down e up juntos — um intervalo entre eles faz o tracking loop do AppKit "engolir" a continuação da Task).
- Limites do harness: `onTapGesture` **não** dispara com o clique sintético em nenhuma abordagem (`Button` dispara), então o toque na linha não foi verificado para nenhuma delas; o swipe nativo do AppKit (`NSTableView`/`List`) engata (`rowActionsVisible == true`, célula deslocada) mas o loop de tracking dele só consome 4 pt do gesto sintético, então **nunca vi os botões nativos renderizados**; não há trackpad real envolvido.

## Tabela comparativa

| Abordagem | Gesto trackpad | Visual (separadores/recuos) | Altura mensurável | Complexidade | Riscos no macOS 27 | Veredito |
|---|---|---|---|---|---|---|
| **A. `List` + `.swipeActions`** | Nativo (é o row-action do `NSTableView` por baixo: a row view contém `NSTableViewActionButtonsGroupView`). Engatou no teste; revelação não vista. | Separadores **somem** com `.listRowSeparator(.hidden)` **em cada linha** + `.listStyle(.plain)` (captura `list-v1-0`). Sobra ~9 pt de recuo à esquerda mesmo com `listRowInsets(EdgeInsets())` (`intercellSpacing` = 17 na `SwiftUIOutlineListView`; zerá-lo por introspecção aproxima, captura `list-v2-0`). Botões só com título+imagem no estilo AppKit, sem tiles custom. | Não nativa: precisaria medir a `NSTableView` por introspecção ou somar linhas. | Média (introspecção frágil). | Depende de classes privadas (`SwiftUIOutlineListView`, `ListTableRowView`). | Não recomendada |
| **B. `NSTableView` + `rowActionsForRow` + células `NSHostingView`** | Nativo (Mail). Engatou no teste; revelação não vista. Fecha ao rolar (nativo). | Idêntico ao atual com `NSTableRowView` que não desenha separador/seleção (`style = .plain`, `intercellSpacing = 0`); ver `table-0-initial`. Note que no macOS 27 o separador vem de um subview `_NSTableRowSeparatorDrawingView`, mas sobrescrever `drawSeparator(in:)` bastou. | Problemática: com `usesAutomaticRowHeights` a altura total só é correta para linhas já medidas (571 → 547 após rolar). Corrigível medindo cada item fora da tela com largura fixa e usando `heightOfRow`. | Alta (data source, reciclagem, menus, cliques). | Cliques em células `NSHostingView` foram para a `NSTableView` (o `onTapGesture`/botões SwiftUI dentro da célula não receberam o `mouseDown`); exige `hitTest`/`validateProposedFirstResponder` sob medida. Botões de ação só título/imagem. | Viável, mas custo alto e visual dos botões não customizável |
| **C. `NSView` próprio sobrescrevendo `scrollWheel` por linha** (overlay que só captura eventos de scroll via `NSApp.currentEvent` no `hitTest`) | Funciona com fases do trackpad (latch no `.began` horizontal-dominante; vertical vai ao `super`; momentum engolido). Inércia não é nativa (snap animado). | Idêntico ao atual (`custom-1`). | Sim (`ScrollView { VStack }` mantido). | Média-alta (~130 linhas de máquina de estados). | Depende de `NSApp.currentEvent` no `hitTest`; gestos cancelados/Magic Mouse precisam de cuidado; é exatamente o tipo de código que "funciona às vezes". | Reserva, se D falhar no hardware real |
| **D. `ScrollView(.horizontal)` aninhado por linha (SwiftUI puro)** | Nativo via `NSScrollView` (inércia, elástico, roteamento por eixo dominante). Snap por `ScrollTargetBehavior` (chamado no macOS: `updateTarget x=121 → 192`). | Idêntico ao atual (`nested-0`, `app-0`). Requer scrollers overlay (ver achado 2). | Sim: `PopoverLayoutTests` continua passando; `fittingSize` 512 no protótipo. | Baixa (~120 linhas, 1 arquivo novo). | Comportamento de scroll aninhado em gesto diagonal e momentum reais não verificados; `AppleShowScrollBars` no domínio do app é um ajuste global do app. | **Recomendada** |
| Bibliotecas | — | — | — | — | — | `aheze/SwipeActions`: iOS-only (PR de macOS #14 aberto desde 2023). `c-villain/SwipeActions`: declara macOS 10.15+ mas é `DragGesture` (arrasto com mouse; não lê scroll de trackpad). `SwiftUIX`/`SwiftUIIntrospect`: só introspecção, não resolvem o gesto. `swipeActionsContainer()` (iOS 27) não existe no SDK macOS 26.2. Nenhuma adotada. |

Capturas (em `/tmp/swipe-proto/`): `list-v0-0-initial` (List crua, com separadores), `list-v1-0-initial` (separadores escondidos), `nested-1-after-swipe-left`, `nested-2-after-vertical-scroll`, `nested-8-open-A-then-swipe-B`, `nested-always-0-initial` (barras "Sempre" sem correção: +17 pt por linha), `app-0-initial`/`app-1-after-swipe-left`/`app-2-after-vertical-scroll` (PopoverView real). Para regenerar: `cd Prototypes/Swipe && ./run-all.sh "list:1 table nested custom"`; variantes: `EXTRA_ARGS="-AppleShowScrollBars Always" ./run.sh nested`, `APP_DOMAIN_SCROLLBARS=Always APP_DOMAIN_SCROLLBARS_LATE=WhenScrolling ./run.sh nested`.

## Achados que mudam premissas

1. **Separadores da `List` no macOS 27.** Na minha reprodução eles somem com `.listRowSeparator(.hidden)` aplicado ao conteúdo de cada linha (não funciona aplicado à `List`) junto com `.listStyle(.plain)`. Possíveis causas da experiência anterior: modificador na `List` em vez da linha, ou os `Divider()` do app virando linhas próprias da `List`. Mesmo assim, a `List` não serve: recuo extra, botões nativos sem customização e altura não mensurável sem introspecção.
2. **Scrollers legados inflam `ScrollView` horizontal.** Com `NSScroller.preferredScrollerStyle == .legacy` (ajuste "Sempre" ou mouse USB em "Automático"), o SwiftUI dá ao `ScrollView(.horizontal)` 80 pt de frame para 63 pt de conteúdo, mesmo com `hasHorizontalScroller = false` já aplicado por introspecção (o `OverlayScrollerStyle` não ajuda; fixar `.frame(height:)` só desloca o conteúdo 8 pt para cima). A raiz é o estilo preferido do app. Verificado no protótipo: `AppleShowScrollBars` lido do **domínio do app** decide o estilo (`Always` → legado/80 pt, `WhenScrolling` → overlay/63 pt), inclusive quando escrito depois de `NSApplication.shared` existir (timing do `App.init()`), e a chave sai do plist ao final. Pela ordem de busca do `NSUserDefaults` (argumentos → app → global), o valor do app prevalece sobre o global; **não testei contra um global "Sempre" real** para não alterar a preferência da máquina — teste manual sugerido abaixo.
3. **`swipeActions` da `List` no macOS = `NSTableViewRowAction`.** A hierarquia da linha mostra `ListTableRowView > [_NSTableRowSeparatorDrawingView, ListTableCellView, NSTableViewActionButtonsGroupView]`. Ou seja, A e B têm a mesma aparência e os mesmos limites de customização.
4. **Harness e tracking loops.** `trackSwipeEvent`/tracking de mouse do AppKit rodam run loops aninhados que não deixam uma `Task` do main actor continuar; por isso eventos sintéticos têm que estar todos na fila antes (`SWIPE_BURST`), e mesmo assim o swipe nativo só andou 4 pt. Isso é limitação do harness, não evidência contra A/B.

## Recomendação única: abordagem D

Justificativa: é a única que atende aos quatro requisitos duros com evidência (gesto e inércia nativos do `NSScrollView`; visual intocado; altura medida como hoje; sem máquina de estados própria de eventos), com o menor volume de código, sem dependências, sem classes privadas, e com integração que não altera `PRRow` nem a estrutura do `PopoverView`. Mantém `PRRowMenu` (fatorado do menu de contexto) para o tile "⋯". Fica **provisória** até um teste manual com trackpad real (ver lista de não verificados), e C é o plano B já prototipado.

Decisões de design incorporadas da revisão adversarial (Codex, 3 lentes):
- A posse de `openRow` só é reivindicada em `.interacting` (gesto do usuário), nunca por geometria — evita que a linha fechando "roube" a posse da que está abrindo (reproduzido em `nested-8`: só B termina aberta).
- `handle(_:for:)` zera `openRow` para qualquer ação (tile, "⋯" ou menu de contexto), fechando a linha de forma uniforme.
- O snap ignora o sinal da velocidade: `target.rect` já é a posição projetada após a desaceleração.
- O snap de segurança em `.idle` ficou (roda de mouse legada deixa a linha em 30 pt sem passar pelo `ScrollTargetBehavior`), mas com debounce de 120 ms para não brigar tick a tick (jitter observado no log).
- Tiles só para as quick actions reais (`quickActions(for:)`: merge/comment/open) + "⋯"; sem `ID` genérico; strings novas apenas "Comment", "Open", "More" (en e pt-BR; `everyEnglishKeyHasPortuguese` passa).

### Código (já aplicado no worktree)

`Sources/Pullglance/UI/SwipeActionsRow.swift` (novo):

```swift
import AppKit
import SwiftUI

/// Swipe-to-reveal actions for a pull request row, Mail style, without a `List`.
///
/// The row is the leading "page" of a horizontal `ScrollView`; the action tiles follow it. AppKit routes a
/// two-finger gesture by its dominant axis, so vertical scrolling keeps going to the enclosing list while a
/// horizontal swipe slides the row with native inertia and rubber banding. `SwipeSnapBehavior` snaps the
/// row fully open or fully closed when the gesture ends. Only one row stays open: the parent owns `openRow`,
/// a row claims it while the user is dragging it, and any row whose id is not `openRow` closes itself.
struct SwipeActionsRow<Content: View, MenuContent: View>: View {
    let id: PullRequest.ID
    let actions: [PRAction]
    @Binding var openRow: PullRequest.ID?
    var isRunning = false
    let onAction: (PRAction) -> Void
    @ViewBuilder let menu: () -> MenuContent
    @ViewBuilder let content: () -> Content

    @State private var position = ScrollPosition(edge: .leading)
    @State private var offsetX: CGFloat = 0
    @State private var settle: Task<Void, Never>? = nil

    private var openWidth: CGFloat { CGFloat(actions.count + 1) * swipeTileWidth }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                content()
                    .containerRelativeFrame(.horizontal)
                HStack(spacing: 0) {
                    ForEach(actions, id: \.self) { action in
                        Button {
                            close()
                            onAction(action)
                        } label: {
                            SwipeTile(action: action)
                        }
                        .buttonStyle(.plain)
                        .disabled(isRunning && (action == .merge || action == .comment))
                    }
                    Menu {
                        menu()
                    } label: {
                        SwipeTile(action: nil)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                }
                .accessibilityHidden(offsetX <= 0)
            }
        }
        // With legacy scrollers SwiftUI would reserve the horizontal bar's height under every row;
        // PullglanceApp forces overlay scrollers app-wide (AppleShowScrollBars) so this stays the row's height.
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .scrollTargetBehavior(SwipeSnapBehavior(openWidth: openWidth))
        .scrollPosition($position)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, x in offsetX = x }
        .onScrollPhaseChange { _, phase in
            settle?.cancel()
            switch phase {
            case .interacting:
                // Only a drag by the user claims the row; a closing animation must not take it back.
                openRow = id
            case .idle:
                // Safety net for input that settles without consulting the target behavior (a legacy
                // wheel, for one). Debounced so a run of wheel ticks is judged once, not fought tick by tick.
                settle = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(120))
                    guard !Task.isCancelled else { return }
                    let target: CGFloat = offsetX > openWidth * 0.5 ? openWidth : 0
                    if abs(offsetX - target) > 0.5 {
                        withAnimation(.snappy(duration: 0.2)) { position.scrollTo(x: target) }
                    }
                    if target == 0, openRow == id { openRow = nil }
                }
            default:
                break
            }
        }
        .onChange(of: openRow) { _, new in
            if new != id, offsetX > 0 { close() }
        }
        .onChange(of: actions) { _, _ in close() }
    }

    private func close() {
        withAnimation(.snappy(duration: 0.2)) { position.scrollTo(edge: .leading) }
        if openRow == id { openRow = nil }
    }
}

let swipeTileWidth: CGFloat = 64

/// Snap to fully open or fully closed. `target.rect` is where the scroll would come to rest after the
/// deceleration, so the midpoint rule already honors a fling without depending on the velocity's sign.
struct SwipeSnapBehavior: ScrollTargetBehavior {
    let openWidth: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        target.rect.origin.x = target.rect.origin.x > openWidth * 0.5 ? openWidth : 0
    }
}

/// One colored tile: symbol over a short label. `nil` is the "more" tile that opens the full menu.
/// Only the quick actions (`quickActions(for:)`) get a tile of their own.
struct SwipeTile: View {
    let action: PRAction?

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
            title.font(.system(size: 10, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(.white)
        .frame(width: swipeTileWidth)
        .frame(maxHeight: .infinity)
        .background(tint)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var title: Text {
        switch action {
        case .merge: Text("Merge", bundle: .app)
        case .comment: Text("Comment", bundle: .app)
        case .open: Text("Open", bundle: .app)
        default: Text("More", bundle: .app)
        }
    }

    private var symbol: String {
        switch action {
        case .merge: "arrow.triangle.merge"
        case .comment: "text.bubble"
        case .open: "arrow.up.forward.square"
        default: "ellipsis"
        }
    }

    private var tint: Color {
        switch action {
        case .merge: Color(red: 0.51, green: 0.31, blue: 0.87)
        case .comment: .blue
        case .open: .teal
        default: Color(white: 0.45)
        }
    }
}
```

`PopoverView.swift` (trechos alterados):

```swift
/// The row whose swipe actions are showing, if any. One at a time, like Mail.
@State private var openRow: PullRequest.ID? = nil

// ... no body, após .onDisappear { ...; openRow = nil }:
.onChange(of: tab) { _, _ in openRow = nil }

// ... no ScrollView da lista:
.scrollIndicators(.never)
// Scrolling the list puts a revealed row away.
.onScrollPhaseChange { _, phase in
    if phase == .interacting || phase == .decelerating { openRow = nil }
}
.background(OverlayScrollerStyle())

private func handle(_ action: PRAction, for pr: PullRequest) {
    // Any action, from a tile, the "more" tile or the context menu, puts a revealed row away.
    openRow = nil
    switch action { /* inalterado */ }
}

private func rowView(_ pr: PullRequest, section: Section, showAuthor: Bool, teamLabel: String?, dormant: Bool) -> some View {
    let actionSection = dormant ? store.originSection(of: pr) : section
    let actionState = store.actionState(for: pr)
    let running: Bool = { if case .running = actionState { return true }; return false }()
    return SwipeActionsRow(
        id: pr.id,
        actions: quickActions(for: actionSection),
        openRow: $openRow,
        isRunning: running,
        onAction: { handle($0, for: pr) },
        menu: { PRRowMenu(section: actionSection, isDormant: dormant, actionState: actionState, onAction: { handle($0, for: pr) }) }
    ) {
        PRRow(pr: pr, section: actionSection, showAuthor: showAuthor, teamLabel: teamLabel, isDormant: dormant,
              originSection: dormant ? store.originSection(of: pr) : nil, actionState: actionState,
              onAction: { handle($0, for: pr) })
    }
}
```

`PRRow.swift`: o `private var menu` virou `struct PRRowMenu: View { section, isDormant, actionState, onAction }` com o mesmo corpo; `.contextMenu { PRRowMenu(section: section, isDormant: isDormant, actionState: actionState, onAction: onAction) }`.

`App/PullglanceApp.swift` (`init()`, antes de `setActivationPolicy`):

```swift
// Thin overlay scrollers app-wide, whatever "Show scroll bars" says and even with a mouse plugged in.
// With legacy scrollers SwiftUI reserves the bar's height under every swipeable row (its horizontal
// ScrollView), which would stretch the list. AppKit reads this key from the app's own defaults
// domain, which precedes the global one.
UserDefaults.standard.set("WhenScrolling", forKey: "AppleShowScrollBars")
```

`Localizable.strings` (en/pt-BR): `"Comment"` = Comentar, `"Open"` = Abrir, `"More"` = Mais.

Observação: `OverlayScrollerStyle` continua no `ScrollView` externo; com o ajuste do app ele fica redundante e pode ser removido numa limpeza futura.

## Revisão adversarial (Codex `exec`, lentes Skeptic/Architect/Minimalist)

Verdict: **CONTESTED → tratado**. Nenhum `brain/principles.md` existe neste ambiente; os princípios usados foram os nomeados nas lentes da skill.

| Achado | Lente | Decisão |
|---|---|---|
| Linha fechando reivindica `openRow` via geometria e fecha a recém-aberta (high) | as três | **Aceito e corrigido** (posse só em `.interacting`; cenário reproduzido em `nested-8`). |
| Ações do menu "⋯" não fecham a linha; política de ações duplicada (low) | Architect | **Aceito**: `handle()` zera `openRow`. A duplicação do `disabled` merge/comment com `PRRowMenu` ficou (duas linhas; centralizar não paga agora). |
| Sinal de `velocity.dx` não verificado | Skeptic | **Aceito**: removido; usa a posição projetada. |
| Snap duplo sem necessidade demonstrada (low) | Minimalist/Architect | **Rejeitado em parte**: a roda de mouse legada deixa a linha em ~30 pt sem passar pelo `ScrollTargetBehavior` (log do protótipo), então o fallback tem caso concreto; ganhou debounce. |
| Tiles/`isDormant`/strings inalcançáveis; `ID` genérico (low) | Minimalist | **Aceito**: removidos. |
| Interação central não verificada em trackpad real, painel do `MenuBarExtra`, VoiceOver (medium/high) | Skeptic/Architect | **Aceito como limitação**: recomendação é provisória; lista abaixo. |
| Dependência do probe assíncrono por linha com barras "Sempre" (medium) | Architect | **Aceito e investigado**: o probe de fato não resolvia; raiz corrigida com `AppleShowScrollBars` no domínio do app (verificado no protótipo), probe por linha removido. |
| `NSTableView`/`List` não foram "refutadas" (medium) | Architect/Skeptic | **Aceito na forma**: a tabela comparativa registra que A e B são viáveis com mais trabalho, e que a evidência contra elas é assimétrica (harness). A escolha por D é por custo/controle visual e por ser a única provada de ponta a ponta, não por impossibilidade das outras. |

## O que NÃO foi verificado visualmente/no hardware

1. Trackpad e Magic Mouse reais: sensação da inércia, gesto diagonal (se a lista rola ou a linha desliza), fling curto, reversão no meio do gesto, momentum interrompido por nova tocada.
2. Comportamento dentro do painel não ativável do `MenuBarExtra(.window)` (o teste usou uma `NSWindow` normal com `PopoverView` + fixtures). Inclui o `Menu` do tile "⋯" abrindo e fechando nesse painel.
3. Toque na linha (`onTapGesture` abre o PR) com a linha fechada e com ela aberta — o harness não dispara `onTapGesture` em nenhuma abordagem.
4. Botões nativos de `NSTableView`/`List` (aparência ícone+texto, animação) — nunca renderizados pelo harness.
5. `AppleShowScrollBars` do domínio do app prevalecendo sobre um valor **global** "Sempre" ou sobre um mouse USB conectado — verificado só a precedência app vs. app (early/late) e a leitura pelo AppKit. Teste manual (1 min): System Settings → Aparência → Mostrar barras de rolagem: Sempre; abrir o popover; as linhas não podem ganhar ~17 pt de altura; reverter.
6. VoiceOver: os tiles ficam `accessibilityHidden` enquanto a linha está fechada; a rota acessível é o menu de contexto (já existente). Não testado com VoiceOver.
7. Arrasto com mouse (bônus): não implementado — um `ScrollView` do AppKit não desliza com arrasto do mouse; se quiser, adicionar um `DragGesture` que ajusta `position.scrollTo(x:)`.

## Roteiro de teste manual sugerido (antes de mergear)

1. Trackpad: deslizar à esquerda numa linha (lento e com fling); deve parar aberta ou fechada, nunca no meio; deslizar à direita fecha; rolar a lista fecha; abrir A e deslizar B fecha A; clicar num tile executa e fecha; "⋯" abre o menu completo.
2. Gestos diagonais a partir de uma linha: predominantemente verticais devem rolar a lista.
3. Clique simples na linha (aberta e fechada) abre o PR; botão do CI dot e avatar continuam clicáveis.
4. Mouse USB conectado e ajuste "Mostrar barras de rolagem: Sempre": altura das linhas inalterada; shift+roda sobre uma linha não deixa a linha meio aberta.
5. Trocar de aba e fechar o popover com uma linha aberta: tudo volta fechado.
6. VoiceOver: navegar pelas linhas e acionar o menu de contexto.
