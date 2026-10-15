import type { Strategy, ViewedControl, ViewedControlLocator } from '../../concepts'

/**
 * UI clássica da aba de arquivos do PR: o GitHub põe em `.file-actions` um formulário com o checkbox
 * "Viewed" (`input.js-reviewed-checkbox`), que envia sozinho ao mudar (`data-autosubmit`). É o estado
 * real do servidor; sem esta estratégia, a do compare injetava um segundo botão e lia um estado inventado.
 */
const CHECKBOX = 'input.js-reviewed-checkbox'

export const viewedControlClassicCheckbox: Strategy<ViewedControlLocator> = {
  id: 'viewed-control/classic-checkbox',
  priority: 28,   // acima do botão injetado do compare (25), abaixo do Viewed da UI nova (aria, 30)
  probe: (doc) => doc.querySelector(`.file-header ${CHECKBOX}`) !== null,
  create: () => ({
    inHeader: (header): ViewedControl | null => {
      const el = header.querySelector<HTMLInputElement>(CHECKBOX)
      if (!el) return null
      return { el, isViewed: () => el.checked, toggle: () => el.click() }
    },
  }),
}
