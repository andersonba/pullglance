import { install } from './entry'
import { mountComparePage, mountFilesPage, digestOf } from './test-fixtures'
import { DEFAULT_SETTINGS } from '@/features/tests/settings'
import { storage } from '#imports'

type Event = { name: string; payload: unknown }

/** The element that stands for a file: the `#diff-<id>` container on compare; in the PR Files UI fixture (no container) the header wrapper. */
const compareHeader = (path: string) => document.getElementById(`diff-${digestOf(path)}`) as any
const filesHeader = (path: string) => document.querySelector(`h3 a[href="#diff-${digestOf(path)}"]`)!.closest('[data-diff-header-wrapper="true"]') as any

/** happy-dom has no layout: give each header a fixed viewport top and record scrolls. */
function placeHeaders(headerOf: (path: string) => any, tops: Record<string, number>, calls: string[]) {
  for (const path of Object.keys(tops)) {
    const node = headerOf(path)
    node.scrollIntoView = () => calls.push(path)
    node.getBoundingClientRect = () => ({ top: tops[path], bottom: tops[path]! + 400 }) as DOMRect
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

  it('tells the app whether it has settings yet, so a fresh document gets them again', async () => {
    mountComparePage({ files: [{ path: 'a.test.ts' }] })
    const events: Event[] = []
    const api = install({ post: (e) => events.push(e) })
    const first = events.find((e) => e.name === 'context')!.payload as { ready: boolean }
    expect(first.ready).toBe(false)
    api.setSettings({})
    expect((api.context() as { ready?: boolean }).ready).toBe(true)
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
    tops['a.ts'] = -900; tops['b.ts'] = -200                       // reading b (its box covers the top edge)
    expect(await api.scrollToUnviewed('next')).toBe(false)
    expect(await api.scrollToUnviewed('previous')).toBe(true)      // the unviewed file before b: a
    expect(calls).toEqual(['a.ts', 'a.ts'])
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

  it('tracks the file the reader is on, steps between files and marks the current one before moving on', async () => {
    mountComparePage({ files: [{ path: 'a.ts' }, { path: 'b.ts' }, { path: 'c.ts' }] })
    const events: Event[] = []
    const api = install({ post: (e) => events.push(e) })
    api.setSettings({})
    const calls: string[] = []
    const tops: Record<string, number> = { 'a.ts': -400, 'b.ts': 60, 'c.ts': 700 }   // b's header just under the bar
    placeHeaders(compareHeader, tops, calls)
    const cursor = await api.currentFile()
    expect(cursor).toMatchObject({ path: 'b.ts', index: 1, total: 3, viewed: false })
    expect((await api.stepFile(1)).moved).toBe(true)     // the file after the current one: c
    expect((await api.stepFile(-1)).moved).toBe(true)    // the last header above the viewport: a (b is at the top already)
    expect(calls).toEqual(['c.ts', 'a.ts'])
    expect(await api.setCurrentViewed(true)).toBe(true)
    expect((await api.currentFile())?.viewed).toBe(true)
    expect(await api.setCurrentViewed(true)).toBe(false)   // already viewed: nothing to do
    expect(await api.setCurrentViewed(false)).toBe(true)
    expect((await api.currentFile())?.viewed).toBe(false)
    const r = await api.markCurrentAndNext()
    expect(r.marked).toBe(true)                                                          // b.ts marked (collapsed)
    expect(document.getElementById(`diff-${digestOf('b.ts')}`)!.classList.contains('open')).toBe(false)
    expect(calls.at(-1)).toBe('c.ts')                                                    // then the next unviewed
    expect(r.moved).toBe(true)
    // The cursor is posted on scroll, throttled, and only when it changes.
    tops['b.ts'] = -400; tops['c.ts'] = 40
    window.dispatchEvent(new Event('scroll'))
    await wait(250)
    const current = events.filter((e) => e.name === 'current').map((e) => e.payload as any)
    expect(current.at(-1)).toMatchObject({ path: 'c.ts', index: 2 })
  })

  it('reaches a file the page has not rendered through the URL hash', async () => {
    mountFilesPage({ files: [{ path: 'a.ts' }, { path: 'b.ts', rendered: false }] })
    const api = install({ post: () => {} })
    api.setSettings({})
    placeHeaders(filesHeader, { 'a.ts': 0 }, [])
    location.hash = `#diff-${digestOf('b.ts')}`                     // even when it already points there
    const r = await api.stepFile(1)
    expect(r).toMatchObject({ moved: true, from: 0, to: 1, via: 'hash' })
    expect(location.hash).toBe(`#diff-${digestOf('b.ts')}`)
  })

  it('reports when the caret enters and leaves a page field, once per change', async () => {
    mountComparePage({ files: [{ path: 'a.ts' }] })
    const events: Event[] = []
    install({ post: (e) => events.push(e) })
    const editingOf = () => events.filter((e) => e.name === 'editing').map((e) => e.payload)
    const textarea = document.createElement('textarea')
    const button = document.createElement('button')
    document.body.append(textarea, button)
    textarea.focus()
    await vi.waitFor(() => expect(editingOf()).toEqual([{ active: true }]))
    textarea.blur()
    await vi.waitFor(() => expect(editingOf()).toEqual([{ active: true }, { active: false }]))
    button.focus()                                  // not a field: no change, no event
    await wait(10)
    expect(editingOf()).toEqual([{ active: true }, { active: false }])
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
