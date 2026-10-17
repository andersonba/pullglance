import { fileTreePrimer } from './file-tree/primer-tree-view'
import { fileTreeClassic } from './file-tree/classic-file-tree'
import { digestOf, mountFilesPage } from '@@/tests/fixtures/github/build'
import { mountComparePage } from '@@/tests/fixtures/github/compare'

const FILES = [{ path: 'apps/web/a.ts' }, { path: 'apps/web/b.ts', viewed: true }, { path: 'README.md' }]

describe('file-tree/primer-tree-view (new Files UI)', () => {
  it('probes the new tree only', () => {
    mountFilesPage({ files: FILES, tree: true })
    expect(fileTreePrimer.probe(document)).toBe(true)
    mountFilesPage({ files: FILES })
    expect(fileTreePrimer.probe(document)).toBe(false)
    mountComparePage({ files: FILES, tree: true })
    expect(fileTreePrimer.probe(document)).toBe(false)
  })

  it('lists files by digest and directories by the files beneath them', () => {
    mountFilesPage({ files: FILES, tree: true })
    const tree = fileTreePrimer.create(document)
    expect(tree.root()?.getAttribute('role')).toBe('tree')
    const items = tree.items()
    const files = items.filter((i) => i.kind === 'file')
    expect(files.map((f) => f.id).sort()).toEqual(FILES.map((f) => digestOf(f.path)).sort())
    const dirs = items.filter((i) => i.kind === 'directory')
    expect(dirs.length).toBe(2)   // apps, apps/web
    for (const d of dirs) expect(d.el.getAttribute('aria-expanded')).toBe('true')
    // every file item is a leaf: no group inside it
    for (const f of files) expect(f.el.querySelector('[role="group"]')).toBeNull()
  })

  it('returns nothing once the tree is gone', () => {
    mountFilesPage({ files: FILES, tree: true })
    const tree = fileTreePrimer.create(document)
    document.getElementById('pr-file-tree')!.remove()
    expect(tree.root()).toBeNull()
    expect(tree.items()).toEqual([])
  })
})

describe('file-tree/classic-file-tree (classic Files UI)', () => {
  it('probes the classic tree only', () => {
    mountComparePage({ files: FILES, tree: true })
    expect(fileTreeClassic.probe(document)).toBe(true)
    mountComparePage({ files: FILES })
    expect(fileTreeClassic.probe(document)).toBe(false)
    mountFilesPage({ files: FILES, tree: true })
    expect(fileTreeClassic.probe(document)).toBe(false)
  })

  it('lists files by the digest in their id and directories by data-tree-entry-type', () => {
    mountComparePage({ files: FILES, tree: true })
    const tree = fileTreeClassic.create(document)
    const items = tree.items()
    expect(items.filter((i) => i.kind === 'file').map((f) => f.id).sort()).toEqual(FILES.map((f) => digestOf(f.path)).sort())
    expect(items.filter((i) => i.kind === 'directory').length).toBe(2)
  })

  it('the new tree wins when both could match', () => {
    expect(fileTreePrimer.priority).toBeGreaterThan(fileTreeClassic.priority)
  })
})
