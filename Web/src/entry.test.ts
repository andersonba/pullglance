import { install } from './entry'
import { mountComparePage, mountFilesPage, digestOf } from './test-fixtures'
import { DEFAULT_SETTINGS } from '@/features/tests/settings'
import { storage } from '#imports'

type Event = { name: string; payload: unknown }

/** The element GitHub scrolls for a file: the classic `.file-header` on compare, the header wrapper in the PR Files UI. */
const compareHeader = (path: string) => document.querySelector(`.file-header[data-anchor="diff-${digestOf(path)}"]`) as any
const filesHeader = (path: string) => document.querySelector(`h3 a[href="#diff-${digestOf(path)}"]`)!.closest('[data-diff-header-wrapper="true"]') as any

/** happy-dom has no layout: give each header a fixed viewport top and record scrolls. */
function placeHeaders(headerOf: (path: string) => any, tops: Record<string, number>, calls: string[]) {
  for (const path of Object.keys(tops)) {
    const node = headerOf(path)
    node.scrollIntoView = () => calls.push(path)
    node.getBoundingClientRect = () => ({ top: tops[path] }) as DOMRect
  }
}

const listingsOf = (events: Event[]) => events.filter((e) => e.name === 'listing').map((e) => e.payload)
const wait = (ms: number) => new Promise((r) => setTimeout(r, ms))

describe('review script API', () => {
  beforeEach(() => { storage._resetForTests(); document.body.innerHTML = '' })

  it('reports the context and counts files on a compare page', async () => {
    mountComparePage({ files: [{ path: 'a.test.ts' }, { path: 'b.ts' }] })
    const events: Event[] = []
    const api = install({ post: (e) => events.push(e) })
    expect(api.context().kind).toBe('compare')
    const c = await api.counts(null)
    expect(c.total).toBe(2)
    expect(c.matching).toBe(1)                  // a.test.ts by the js-unit preset
    expect(c.perRule['js-unit']).toBe(1)
    expect(events.some((e) => e.name === 'context')).toBe(true)
  })

  it('marks by rule ids, then undoes', async () => {
    mountComparePage({ files: [{ path: 'a.test.ts' }, { path: 'b.ts' }] })
    const api = install({ post: () => {} })
    const r = await api.mark(['js-unit'])
    expect(r.marked).toBe(1)
    expect(r.canUndo).toBe(true)
    expect(document.getElementById(`diff-${digestOf('a.test.ts')}`)!.classList.contains('open')).toBe(false)
    const u = await api.undo()
    expect(u.marked).toBe(1)
    await expect(api.undo()).rejects.toThrow('nothing to undo')
  })

  it('scrolls to the next and previous unviewed file on a compare page, and reports when there is none', async () => {
    mountComparePage({ files: [{ path: 'a.ts' }, { path: 'b.ts' }] })
    const api = install({ post: () => {} })
    const calls: string[] = []
    const tops: Record<string, number> = { 'a.ts': 200, 'b.ts': 900 }
    placeHeaders(compareHeader, tops, calls)
    expect(await api.scrollToUnviewed('next')).toBe(true)
    expect(calls).toEqual(['a.ts'])
    expect(await api.scrollToUnviewed('previous')).toBe(false)   // nothing above the viewport
    tops['a.ts'] = -900; tops['b.ts'] = -200                       // both scrolled past
    expect(await api.scrollToUnviewed('next')).toBe(false)
    expect(await api.scrollToUnviewed('previous')).toBe(true)
    expect(calls).toEqual(['a.ts', 'b.ts'])
  })

  it('scrolls to the first unviewed header in the PR Files UI, which has no #diff-<id> element', async () => {
    mountFilesPage({ files: [{ path: 'a.ts', viewed: true }, { path: 'b.ts' }, { path: 'c.ts' }] })
    expect(document.getElementById(`diff-${digestOf('b.ts')}`)).toBeNull()
    const api = install({ post: () => {} })
    const calls: string[] = []
    placeHeaders(filesHeader, { 'a.ts': 100, 'b.ts': 500, 'c.ts': 900 }, calls)
    expect(await api.scrollToUnviewed('next')).toBe(true)
    expect(calls).toEqual(['b.ts'])                // a.ts is viewed
  })

  it('does not touch the page before the first setSettings, then restores remembered compare marks', async () => {
    await storage.setItem('local:ghra:compare:/acme/web/compare/main...feat/x', { viewed: [digestOf('a.test.ts')], updatedAt: Date.now() })
    mountComparePage({ files: [{ path: 'a.test.ts' }, { path: 'b.ts' }] })
    const events: Event[] = []
    const api = install({ post: (e) => events.push(e) })
    const file = document.getElementById(`diff-${digestOf('a.test.ts')}`)!
    await wait(300)                                  // past every debounce
    expect(file.classList.contains('open')).toBe(true)
    expect(document.querySelector('button[data-ghra-viewed]')).toBeNull()
    expect(listingsOf(events)).toEqual([])
    expect(events.map((e) => e.name)).toEqual(['context'])
    api.setSettings({ ...DEFAULT_SETTINGS })
    await vi.waitFor(() => expect(file.classList.contains('open')).toBe(false))
    await vi.waitFor(() => expect(listingsOf(events)).toEqual([{ total: 2, viewed: 1, partial: false }]))
  })

  it('posts the listing after setSettings and again when the file list changes', async () => {
    mountComparePage({ files: [{ path: 'a.ts' }, { path: 'b.ts' }] })
    const events: Event[] = []
    const api = install({ post: (e) => events.push(e) })
    api.setSettings({ ...DEFAULT_SETTINGS })
    await vi.waitFor(() => expect(listingsOf(events)).toEqual([{ total: 2, viewed: 0, partial: false }]))
    await api.mark(null)                         // nothing matches by default: no change, no new event
    document.querySelector<HTMLButtonElement>(`#diff-${digestOf('a.ts')} button[data-ghra-viewed]`)!.click()   // the user marks a file
    await vi.waitFor(() => expect(listingsOf(events).at(-1)).toEqual({ total: 2, viewed: 1, partial: false }))
    expect(listingsOf(events)).toHaveLength(2)
  })

  it('posts the same listing again after a context change', async () => {
    mountComparePage({ files: [{ path: 'a.ts' }, { path: 'b.ts' }] })
    const events: Event[] = []
    const api = install({ post: (e) => events.push(e) })
    api.setSettings({ ...DEFAULT_SETTINGS })
    await vi.waitFor(() => expect(listingsOf(events)).toHaveLength(1))
    mountComparePage({ files: [{ path: 'a.ts' }, { path: 'b.ts' }], range: 'main...feat/y' })   // another compare, same counts
    await vi.waitFor(() => expect(api.context().basePath).toBe('/acme/web/compare/main...feat/y'))
    await vi.waitFor(() => expect(listingsOf(events)).toEqual([{ total: 2, viewed: 0, partial: false }, { total: 2, viewed: 0, partial: false }]))
    expect(events.filter((e) => e.name === 'context').length).toBeGreaterThanOrEqual(2)
  })

  it('posts an empty listing once when the file list goes away', async () => {
    mountComparePage({ files: [{ path: 'a.ts' }] })
    const events: Event[] = []
    const api = install({ post: (e) => events.push(e) })
    api.setSettings({ ...DEFAULT_SETTINGS })
    await vi.waitFor(() => expect(listingsOf(events)).toHaveLength(1))
    ;(window as any).happyDOM.setURL('https://github.com/acme/web')
    document.body.innerHTML = '<main><p>repository home</p></main>'
    await vi.waitFor(() => expect(listingsOf(events).at(-1)).toEqual({ total: 0, viewed: 0, partial: false }))
    document.body.append(document.createElement('div'))   // more mutations: still no file list, no repeat
    await wait(300)
    expect(listingsOf(events)).toHaveLength(2)
  })
})
