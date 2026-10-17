import type { FileTreeSource } from '@/hosts/github/page/concepts'

/**
 * Viewed files leave the file tree sidebar, so what is left is what is left to review. The tree is
 * GitHub's; this only puts attributes on its items and one rule in a style element, so the page's own
 * markup is untouched and the items stay in the DOM, where GitHub's filter and keyboard still find them.
 *
 * `VIEWED_ATTR` goes on a file item whose file the listing says is viewed, and on a directory whose files
 * are all viewed; `HIDE_ATTR` on the tree root is the switch the CSS keys off, so turning hiding on and off
 * costs one attribute. Once every file is viewed the marks come off: nothing is left to find, and an empty
 * sidebar reads as broken. A file the listing does not mention (a partial listing) keeps its mark.
 */
export const STYLE_ID = 'ghra-tree-style'
export const VIEWED_ATTR = 'data-ghra-viewed'
export const HIDE_ATTR = 'data-ghra-hide-viewed'
const CSS = `[${HIDE_ATTR}="true"] [role="treeitem"][${VIEWED_ATTR}] { display: none !important; }`

export interface TreeSync {
  /** Puts the marks on the tree for this listing: call it whenever the listing or the tree changes. */
  apply(files: ReadonlyArray<{ id: string; viewed: boolean }>): void
  /** Whether marked items are hidden; the marks themselves stay, so switching back needs no listing. */
  setHidden(on: boolean): void
  /** Takes everything off the page. */
  dispose(): void
}

export function createTreeSync(doc: Document, source: () => FileTreeSource | null): TreeSync {
  let hidden = false

  const ensureStyle = () => {
    if (doc.getElementById(STYLE_ID)) return
    const style = doc.createElement('style')
    style.id = STYLE_ID
    style.textContent = CSS
    ;(doc.head ?? doc.documentElement).appendChild(style)
  }
  const flagRoot = (root: Element | null) => {
    if (!root) return
    if (hidden) root.setAttribute(HIDE_ATTR, 'true'); else root.removeAttribute(HIDE_ATTR)
  }

  return {
    setHidden(on) {
      hidden = on
      if (on) ensureStyle()
      flagRoot(source()?.root() ?? null)
    },
    apply(files) {
      const tree = source()
      const root = tree?.root() ?? null
      if (!tree || !root) return
      ensureStyle()
      flagRoot(root)
      const items = tree.items()
      const viewed = new Map(files.map((f) => [f.id, f.viewed] as const))
      const allViewed = files.length > 0 && files.every((f) => f.viewed)
      const directories = new Set(items.filter((i) => i.kind === 'directory').map((i) => i.el))
      const tally = new Map<Element, { files: number; viewed: number }>()
      for (const item of items) {
        if (item.kind !== 'file') continue
        const known = viewed.get(item.id)
        const mark = allViewed ? false : (known ?? item.el.hasAttribute(VIEWED_ATTR))
        if (mark) item.el.setAttribute(VIEWED_ATTR, ''); else item.el.removeAttribute(VIEWED_ATTR)
        // A directory is viewed when every file beneath it is: tallied up the ancestors, not by containment
        // checks across the whole tree.
        for (let p = item.el.parentElement; p && p !== root; p = p.parentElement) {
          if (!directories.has(p)) continue
          const t = tally.get(p) ?? { files: 0, viewed: 0 }
          t.files++
          if (mark) t.viewed++
          tally.set(p, t)
        }
      }
      for (const dir of directories) {
        const t = tally.get(dir)
        if (t && t.files > 0 && t.viewed === t.files) dir.setAttribute(VIEWED_ATTR, ''); else dir.removeAttribute(VIEWED_ATTR)
      }
    },
    dispose() {
      hidden = false
      doc.getElementById(STYLE_ID)?.remove()
      for (const el of Array.from(doc.querySelectorAll(`[${VIEWED_ATTR}], [${HIDE_ATTR}]`))) {
        el.removeAttribute(VIEWED_ATTR)
        el.removeAttribute(HIDE_ATTR)
      }
    },
  }
}
