import type { FileHeader, FileHeaderLocator, Strategy } from '../../concepts'

const LINK = 'h3 a[href^="#diff-"]'
const WRAPPER = '[data-diff-header-wrapper="true"], [class*="Diff-module__diffHeaderWrapper"]'

function toHeader(link: Element): FileHeader | null {
  const href = link.getAttribute('href') ?? ''
  const id = href.slice('#diff-'.length)
  const el = link.closest(WRAPPER) ?? link.closest('h3')?.parentElement?.parentElement
  const path = (link.querySelector('code')?.textContent ?? link.textContent ?? '').replace(/‎/g, '').trim()
  if (!id || !el || !path) return null
  return { id, path, el, labelSlot: link.closest('h3') ?? undefined }
}

export const fileHeaderAriaLink: Strategy<FileHeaderLocator> = {
  id: 'file-header/aria-link',
  priority: 30,
  probe: (doc) => doc.querySelector(LINK) !== null,
  create: (doc) => ({
    all: () => Array.from(doc.querySelectorAll(LINK)).map(toHeader).filter((h): h is FileHeader => h !== null),
    byId: (id) => {
      const escapedId = typeof CSS !== 'undefined' ? CSS.escape(id) : id.replace(/[^a-f0-9]/gi, '')
      const link = doc.querySelector(`h3 a[href="#diff-${escapedId}"]`)
      return link ? toHeader(link) : null
    },
  }),
}
