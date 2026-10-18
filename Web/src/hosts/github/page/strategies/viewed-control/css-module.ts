import type { Strategy, ViewedControl, ViewedControlLocator } from '../../concepts'
import { reactOwns } from './react'

const BUTTON = 'button[class*="MarkAsViewedButton-module__"]'
const VIEWED_CLASS_PREFIX = 'MarkAsViewedButton-module__viewed__'

export const viewedControlCssModule: Strategy<ViewedControlLocator> = {
  id: 'viewed-control/css-module',
  priority: 10,
  probe: (doc) => doc.querySelector(BUTTON) !== null,
  create: (doc) => ({
    inHeader: (header): ViewedControl | null => {
      const el = header.querySelector<HTMLButtonElement>(BUTTON)
      if (!el) return null
      return {
        el,
        isViewed: () => Array.from(el.classList).some((c) => c.startsWith(VIEWED_CLASS_PREFIX)),
        toggle: () => el.click(),
        isReady: () => reactOwns(doc, el),
      }
    },
  }),
}
