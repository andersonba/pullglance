import type { Strategy, ViewedControl, ViewedControlLocator } from '../../concepts'

/**
 * UI clássica não tem Viewed. O equivalente é colapsar o arquivo pelo chevron do cabeçalho:
 * "visto" = colapsado (`aria-expanded="false"`).
 */
const TOGGLE = 'button.js-details-target[aria-expanded]'

export const viewedControlClassicCollapse: Strategy<ViewedControlLocator> = {
  id: 'viewed-control/classic-collapse',
  priority: 20,
  probe: (doc) => doc.querySelector(`.file-header ${TOGGLE}`) !== null,
  create: () => ({
    inHeader: (header): ViewedControl | null => {
      const el = header.querySelector<HTMLButtonElement>(TOGGLE)
      if (!el) return null
      return { el, isViewed: () => el.getAttribute('aria-expanded') === 'false', toggle: () => el.click() }
    },
  }),
}
