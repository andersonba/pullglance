import type { Strategy, ViewedControl, ViewedControlLocator } from '../../concepts'
import { reactOwns } from './react'

const BUTTON = 'button[aria-pressed][aria-label="Viewed"]:not([data-ghra-viewed]), button[aria-pressed][aria-label="Not Viewed"]:not([data-ghra-viewed])'

export const viewedControlAria: Strategy<ViewedControlLocator> = {
  id: 'viewed-control/aria',
  priority: 30,
  probe: (doc) => doc.querySelector(BUTTON) !== null,
  create: (doc) => ({
    inHeader: (header): ViewedControl | null => {
      const el = header.querySelector<HTMLButtonElement>(BUTTON)
      if (!el) return null
      return { el, isViewed: () => el.getAttribute('aria-pressed') === 'true', toggle: () => el.click(), isReady: () => reactOwns(doc, el) }
    },
  }),
}
