import type { PageReadiness, Strategy } from '../../concepts'
import { appLoaded } from '../viewed-control/react'

/**
 * The new Files UI: server-rendered, then hydrated by React. Until the app has mounted, a click reaches the
 * server but the hydration redraws the button from the initial payload (seen live 2026-10-17). Ready when
 * every `<react-app>` on the page carries GitHub's own `loaded` class (see `viewed-control/react.ts`).
 */
export const pageReadyReactHydration: Strategy<PageReadiness> = {
  id: 'page-ready/react-hydration',
  priority: 30,
  probe: (doc) => doc.querySelector('react-app') !== null,
  create: (doc) => ({
    isReady: () => Array.from(doc.querySelectorAll('react-app')).every(appLoaded),
  }),
}
