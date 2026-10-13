import type { Strategy, ToolbarSlotSource } from '../../concepts'

export const toolbarSlotFloating: Strategy<ToolbarSlotSource> = {
  id: 'toolbar-slot/floating',
  priority: 1,
  probe: (doc) => doc.body !== null,
  create: (doc) => ({
    find: () => {
      let el = doc.querySelector<HTMLElement>('[data-ghra-floating="true"]')
      if (!el) {
        el = doc.createElement('div')
        el.setAttribute('data-ghra-floating', 'true')
        el.style.cssText = 'position:fixed;right:16px;bottom:16px;z-index:2147483000'
        doc.body.append(el)
      }
      return el
    },
  }),
}
