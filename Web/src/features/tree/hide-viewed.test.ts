import { createTreeSync, HIDE_ATTR, STYLE_ID, VIEWED_ATTR } from './hide-viewed'
import { fileTreePrimer } from '@/hosts/github/page/strategies/file-tree/primer-tree-view'
import { fileTreeClassic } from '@/hosts/github/page/strategies/file-tree/classic-file-tree'
import { digestOf, mountFilesPage } from '@@/tests/fixtures/github/build'
import { mountComparePage } from '@@/tests/fixtures/github/compare'

const PATHS = ['apps/web/a.ts', 'apps/web/b.ts', 'apps/api/c.ts', 'README.md']
const listing = (viewed: string[]) => PATHS.map((path) => ({ id: digestOf(path), viewed: viewed.includes(path) }))
const treeItem = (path: string) => document.getElementById(path) ?? document.getElementById(`file-tree-item-diff-${digestOf(path)}`)!
const marked = (path: string) => treeItem(path).hasAttribute(VIEWED_ATTR)
const hiddenByCss = (el: Element) => getComputedStyle(el).display === 'none'

describe('tree sync: viewed files leave the sidebar', () => {
  it('marks viewed files and only the directories whose files are all viewed', () => {
    mountFilesPage({ files: PATHS.map((path) => ({ path })), tree: true })
    const sync = createTreeSync(document, () => fileTreePrimer.create(document))
    sync.setHidden(true)
    sync.apply(listing(['apps/web/a.ts', 'apps/web/b.ts']))
    expect(marked('apps/web/a.ts')).toBe(true)
    expect(marked('apps/web/b.ts')).toBe(true)
    expect(marked('apps/api/c.ts')).toBe(false)
    expect(marked('apps/web')).toBe(true)      // both of its files viewed
    expect(marked('apps')).toBe(false)         // apps/api/c.ts is not
    expect(document.querySelector('ul[role="tree"]')!.getAttribute(HIDE_ATTR)).toBe('true')
    expect(document.getElementById(STYLE_ID)).not.toBeNull()
  })

  it('hides through CSS only while hiding is on; the items stay in the DOM', () => {
    mountFilesPage({ files: PATHS.map((path) => ({ path })), tree: true })
    const sync = createTreeSync(document, () => fileTreePrimer.create(document))
    sync.setHidden(true)
    sync.apply(listing(['apps/web/a.ts']))
    expect(hiddenByCss(treeItem('apps/web/a.ts'))).toBe(true)
    expect(hiddenByCss(treeItem('apps/web/b.ts'))).toBe(false)
    // Off: the flag the CSS keys off leaves the root; the marks stay, so turning hiding back on needs no new
    // listing. (happy-dom keeps answering the old selector match for a nested item after an ancestor's
    // attribute is removed, so the switch is checked by the attribute, which is all the CSS reads.)
    const root = document.querySelector('ul[role="tree"]')!
    sync.setHidden(false)
    expect(root.hasAttribute(HIDE_ATTR)).toBe(false)
    expect(document.contains(treeItem('apps/web/a.ts'))).toBe(true)
    expect(marked('apps/web/a.ts')).toBe(true)
    sync.setHidden(true)
    expect(root.getAttribute(HIDE_ATTR)).toBe('true')
    expect(hiddenByCss(treeItem('apps/web/a.ts'))).toBe(true)
  })

  it('unmarks a file that was unviewed again, and its directory with it', () => {
    mountFilesPage({ files: PATHS.map((path) => ({ path })), tree: true })
    const sync = createTreeSync(document, () => fileTreePrimer.create(document))
    sync.setHidden(true)
    sync.apply(listing(['apps/web/a.ts', 'apps/web/b.ts']))
    expect(marked('apps/web')).toBe(true)
    sync.apply(listing(['apps/web/a.ts']))
    expect(marked('apps/web/b.ts')).toBe(false)
    expect(marked('apps/web')).toBe(false)
  })

  it('shows everything again once every file is viewed: nothing is left to find', () => {
    mountFilesPage({ files: PATHS.map((path) => ({ path })), tree: true })
    const sync = createTreeSync(document, () => fileTreePrimer.create(document))
    sync.setHidden(true)
    sync.apply(listing(PATHS))
    for (const path of PATHS) expect(marked(path)).toBe(false)
    expect(marked('apps')).toBe(false)
  })

  it('leaves a tree item alone when the listing does not know its file', () => {
    mountFilesPage({ files: PATHS.map((path) => ({ path })), tree: true })
    const sync = createTreeSync(document, () => fileTreePrimer.create(document))
    sync.setHidden(true)
    sync.apply(listing(['apps/web/a.ts']))
    sync.apply(listing(['apps/web/a.ts']).filter((f) => f.id !== digestOf('apps/web/a.ts')))   // a partial listing without a.ts
    expect(marked('apps/web/a.ts')).toBe(true)
  })

  it('does the same on the classic tree', () => {
    mountComparePage({ files: PATHS.map((path) => ({ path })), tree: true })
    const sync = createTreeSync(document, () => fileTreeClassic.create(document))
    sync.setHidden(true)
    sync.apply(listing(['apps/api/c.ts']))
    expect(marked('apps/api/c.ts')).toBe(true)
    expect(hiddenByCss(treeItem('apps/api/c.ts'))).toBe(true)
    expect(marked('apps/web/a.ts')).toBe(false)
    const apiDir = treeItem('apps/api/c.ts').closest('li[data-tree-entry-type="directory"]')!
    expect(apiDir.hasAttribute(VIEWED_ATTR)).toBe(true)
  })

  it('does nothing without a tree and recovers when one appears', () => {
    mountFilesPage({ files: PATHS.map((path) => ({ path })) })
    const sync = createTreeSync(document, () => (fileTreePrimer.probe(document) ? fileTreePrimer.create(document) : null))
    sync.setHidden(true)
    expect(() => sync.apply(listing(['apps/web/a.ts']))).not.toThrow()
    mountFilesPage({ files: PATHS.map((path) => ({ path })), tree: true })
    sync.apply(listing(['apps/web/a.ts']))
    expect(marked('apps/web/a.ts')).toBe(true)
    expect(document.querySelector('ul[role="tree"]')!.getAttribute(HIDE_ATTR)).toBe('true')
  })

  it('dispose takes the marks, the flag and the style away', () => {
    mountFilesPage({ files: PATHS.map((path) => ({ path })), tree: true })
    const sync = createTreeSync(document, () => fileTreePrimer.create(document))
    sync.setHidden(true)
    sync.apply(listing(['apps/web/a.ts']))
    sync.dispose()
    expect(marked('apps/web/a.ts')).toBe(false)
    expect(document.querySelector(`[${HIDE_ATTR}]`)).toBeNull()
    expect(document.getElementById(STYLE_ID)).toBeNull()
  })
})
