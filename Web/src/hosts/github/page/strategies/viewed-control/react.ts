/**
 * The new Files UI is server-rendered and then hydrated by React. A click on a Viewed button before the app has
 * mounted reaches the server, but the hydration redraws the button from the initial payload and the page
 * shows the file unviewed (seen live on 2026-10-17: auto-mark 50 ms after load). GitHub's `<react-app>`
 * element gets the class `loaded` once its app has mounted; the server's HTML has no class on it. That is
 * the one signal readable from the app's isolated content world, where React's own `__reactProps` keys on
 * the nodes are invisible.
 */

/** The `<react-app>` an element belongs to, or null on a page without one (classic UI, compare). */
const appOf = (el: Element | Document) => ('closest' in el ? el.closest('react-app') : null) ?? (el.ownerDocument ?? (el as Document)).querySelector('react-app')

export const appLoaded = (app: Element | null) => app === null || app.classList.contains('loaded')

/** Whether React runs this page at all. */
export const reactRunsPage = (doc: Document) => doc.querySelector('react-app') !== null

/** Whether a control is safe to click: no React app on the page, or the app it belongs to has mounted. */
export const reactOwns = (_doc: Document, el: Element) => appLoaded(appOf(el))
