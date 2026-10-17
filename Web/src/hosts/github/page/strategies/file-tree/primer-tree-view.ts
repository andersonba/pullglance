import type { FileTreeItem, FileTreeSource, Strategy } from '../../concepts'
import { digestOfLink } from './digest'

/**
 * The new Files UI (Primer TreeView, read live on 2026-10-17): `#pr-file-tree > ul[role=tree]`. Every node is
 * a `li[role=treeitem]` with its full path as `id`; a directory holds a `ul[role=group]`, a file does not
 * and links to `#diff-<digest>`. The tree carries no viewed state and is not rebuilt when a file is marked.
 */
const ROOT = '#pr-file-tree ul[role="tree"], ul[role="tree"][aria-label="File Tree"]'
const ITEM = 'li[role="treeitem"]'

export const fileTreePrimer: Strategy<FileTreeSource> = {
  id: 'file-tree/primer-tree-view',
  priority: 30,
  probe: (doc) => doc.querySelector(`${ROOT} ${ITEM}`) !== null,
  create: (doc) => ({
    root: () => doc.querySelector(ROOT),
    items: () => {
      const root = doc.querySelector(ROOT)
      if (!root) return []
      const items: FileTreeItem[] = []
      for (const el of Array.from(root.querySelectorAll(ITEM))) {
        if (el.querySelector('[role="group"]')) { items.push({ kind: 'directory', id: '', el }); continue }
        const id = digestOfLink(el)
        if (id) items.push({ kind: 'file', id, el })
      }
      return items
    },
  }),
}
