import type { FileTreeItem, FileTreeSource, Strategy } from '../../concepts'
import { digestOfLink } from './digest'

/**
 * The classic Files UI (read live on 2026-10-17): `<file-tree>` with `li[role=treeitem][data-tree-entry-type]`.
 * A file is `li#file-tree-item-diff-<digest>` linking to `#diff-<digest>`; GitHub also keeps an empty
 * `data-file-user-viewed` on it while viewed, which this strategy does not need: the listing is the truth.
 */
const ROOT = 'file-tree ul[role="tree"]'
const ITEM = 'li[role="treeitem"][data-tree-entry-type]'

export const fileTreeClassic: Strategy<FileTreeSource> = {
  id: 'file-tree/classic-file-tree',
  priority: 20,
  probe: (doc) => doc.querySelector(`${ROOT} ${ITEM}`) !== null,
  create: (doc) => ({
    root: () => doc.querySelector(ROOT),
    items: () => {
      const root = doc.querySelector(ROOT)
      if (!root) return []
      const items: FileTreeItem[] = []
      for (const el of Array.from(root.querySelectorAll(ITEM))) {
        if (el.getAttribute('data-tree-entry-type') === 'directory') { items.push({ kind: 'directory', id: '', el }); continue }
        const id = el.id.startsWith('file-tree-item-diff-') ? el.id.slice('file-tree-item-diff-'.length) : digestOfLink(el)
        if (id) items.push({ kind: 'file', id, el })
      }
      return items
    },
  }),
}
