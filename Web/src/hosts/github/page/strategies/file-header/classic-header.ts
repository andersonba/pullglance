import type { FileHeader, FileHeaderLocator, Strategy } from '../../concepts'

/** UI clássica (compare, PR antigo): `.file-header[data-path][data-anchor="diff-<digest>"]`. */
const HEADER = '.file-header[data-path][data-anchor^="diff-"]'

function toHeader(el: Element): FileHeader | null {
  const id = (el.getAttribute('data-anchor') ?? '').slice('diff-'.length)
  const path = el.getAttribute('data-path') ?? ''
  if (!id || !path) return null
  return { id, path, el, labelSlot: el.querySelector('.file-info') ?? el }
}

export const fileHeaderClassic: Strategy<FileHeaderLocator> = {
  id: 'file-header/classic-header',
  priority: 20,
  probe: (doc) => doc.querySelector(HEADER) !== null,
  create: (doc) => ({
    all: () => Array.from(doc.querySelectorAll(HEADER)).map(toHeader).filter((h): h is FileHeader => h !== null),
    byId: (id) => {
      const escapedId = typeof CSS !== 'undefined' ? CSS.escape(id) : id.replace(/[^a-f0-9]/gi, '')
      const el = doc.querySelector(`.file-header[data-path][data-anchor="diff-${escapedId}"]`)
      return el ? toHeader(el) : null
    },
  }),
}
