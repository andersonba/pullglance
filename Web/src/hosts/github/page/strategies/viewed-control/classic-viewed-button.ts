import type { Strategy, ViewedControl, ViewedControlLocator } from '../../concepts'

/**
 * UI clássica (compare) não tem Viewed: injetamos um botão "Viewed" em cada cabeçalho, em light DOM, com as
 * classes do Primer que a própria página carrega, para ficar igual ao da aba de arquivos do PR.
 * O estado vive no atributo aria-pressed do botão; marcar colapsa o arquivo e desmarcar expande (via chevron).
 * Colapsar pelo chevron não marca. A persistência fica por conta da memória do compare (adapter).
 */
const ACTIONS = '.file-actions'
const BUTTON = 'button[data-ghra-viewed]'
const CHEVRON = 'button.js-details-target[aria-expanded]'

const ICON_EMPTY = '<svg aria-hidden="true" class="octicon" viewBox="0 0 16 16" width="16" height="16" fill="currentColor"><path d="M2.75 1h10.5c.966 0 1.75.784 1.75 1.75v10.5A1.75 1.75 0 0 1 13.25 15H2.75A1.75 1.75 0 0 1 1 13.25V2.75C1 1.784 1.784 1 2.75 1Zm10.5 1.5H2.75a.25.25 0 0 0-.25.25v10.5c0 .138.112.25.25.25h10.5a.25.25 0 0 0 .25-.25V2.75a.25.25 0 0 0-.25-.25Z"/></svg>'
const ICON_FILL = '<svg aria-hidden="true" class="octicon" viewBox="0 0 16 16" width="16" height="16" fill="currentColor"><path d="M2.75 1h10.5c.966 0 1.75.784 1.75 1.75v10.5A1.75 1.75 0 0 1 13.25 15H2.75A1.75 1.75 0 0 1 1 13.25V2.75C1 1.784 1.784 1 2.75 1Z"/><path fill="var(--bgColor-default, #fff)" d="M11.78 5.78a.75.75 0 0 0-1.06-1.06L7 8.44 5.28 6.72a.75.75 0 0 0-1.06 1.06l2.25 2.25a.75.75 0 0 0 1.06 0l4.25-4.25Z"/></svg>'
const STYLE_ON = 'background-color: var(--bgColor-accent-muted, #ddf4ff); border-color: var(--borderColor-accent-emphasis, #0969da); color: var(--fgColor-accent, #0969da);'
const STYLE_OFF = ''

function paint(btn: HTMLButtonElement, on: boolean) {
  btn.setAttribute('aria-pressed', String(on))
  btn.setAttribute('aria-label', on ? 'Viewed' : 'Not Viewed')
  btn.style.cssText = on ? STYLE_ON : STYLE_OFF
  const visual = btn.querySelector('.Button-leadingVisual')
  if (visual) visual.innerHTML = on ? ICON_FILL : ICON_EMPTY
}

function isOn(btn: Element) { return btn.getAttribute('aria-pressed') === 'true' }

function ensureButton(header: Element): HTMLButtonElement | null {
  const existing = header.querySelector<HTMLButtonElement>(BUTTON)
  if (existing) return existing
  const actions = header.querySelector(ACTIONS)
  if (!actions) return null
  const btn = header.ownerDocument.createElement('button')
  btn.type = 'button'
  btn.setAttribute('data-ghra-viewed', 'true')
  btn.className = 'Button Button--secondary Button--small mr-2 flex-shrink-0'
  btn.innerHTML = '<span class="Button-content"><span class="Button-visual Button-leadingVisual"></span><span class="Button-label">Viewed</span></span>'
  paint(btn, false)
  btn.addEventListener('click', () => {
    const on = !isOn(btn)
    paint(btn, on)
    // Como no PR: marcar colapsa, desmarcar expande. O chevron é do GitHub; só clicamos se o estado difere.
    const chevron = header.querySelector<HTMLButtonElement>(CHEVRON)
    if (chevron && (chevron.getAttribute('aria-expanded') === 'true') === on) chevron.click()
  })
  // .file-actions não é flex (o menu "…" é um bloco): dentro dele o botão quebra linha. O cabeçalho é um
  // flex row, então o botão entra como irmão imediatamente antes das ações, alinhado à esquerda do "…".
  actions.before(btn)
  return btn
}

export const viewedControlClassicButton: Strategy<ViewedControlLocator> = {
  id: 'viewed-control/classic-viewed-button',
  priority: 25,   // acima do chevron (classic-collapse), abaixo do Viewed nativo do PR (aria)
  // Só onde o GitHub não oferece Viewed (compare): na aba de arquivos do PR o checkbox nativo manda.
  probe: (doc) => doc.querySelector(`.file-header[data-path] ${ACTIONS}`) !== null && doc.querySelector('.file-header input.js-reviewed-checkbox') === null,
  create: () => ({
    inHeader: (header): ViewedControl | null => {
      const el = ensureButton(header)
      if (!el) return null
      return { el, isViewed: () => isOn(el), toggle: () => el.click() }
    },
  }),
}
