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

/** The reader scrolls: in the geometry-only tests the tops change by hand, and `scrollY` must move too (it ends a jump). */
const userScrolls = (y: number) => Object.defineProperty(window, 'scrollY', { configurable: true, get: () => y })

const listingsOf = (events: Event[]) => events.filter((e) => e.name === 'listing').map((e) => e.payload)
const wait = (ms: number) => new Promise((r) => setTimeout(r, ms))

/**
 * A page that scrolls: each file's `#diff-<id>` box sits at a page offset, the window has a scrollY, and
 * scrollIntoView / scrollBy move it. `boxes` overrides a file's box (offset from its page top, height).
 */
function layoutPage(paths: string[], heights: number[], boxes: Record<number, { from?: number; height: number }> = {}, viewport = 0) {
  const tops: number[] = []
  let y = 0
  for (const h of heights) { tops.push(y); y += h + 8 }
  const maxScroll = Math.max(0, y - 8 - viewport)   // the window cannot scroll past the end of the document
  const clamp = (v: number) => Math.min(Math.max(v, 0), maxScroll)
  let scrollY = 0
  Object.defineProperty(window, 'scrollY', { configurable: true, get: () => scrollY })
  const scrollBy = (a: number | ScrollToOptions, b?: number) => { scrollY = clamp(scrollY + (typeof a === 'number' ? (b ?? 0) : (a.top ?? 0))) }
  ;(window as any).scrollBy = scrollBy
  paths.forEach((path, i) => {
    const el = document.getElementById(`diff-${digestOf(path)}`) as any
    const box = boxes[i]
    el.getBoundingClientRect = () => {
      const top = tops[i]! + (box?.from ?? 0) - scrollY
      return { top, bottom: top + (box?.height ?? heights[i]!), left: 300, width: 900, height: box?.height ?? heights[i]! } as DOMRect
    }
    el.scrollIntoView = () => { scrollY = clamp(tops[i]!) }
  })
  return {
    scrollTo: (index: number) => { scrollY = clamp(tops[index]!) }, scrollY: () => scrollY, topOf: (i: number) => tops[i]!,
    maxScroll, setScroll: (v: number) => { scrollY = clamp(v) },
  }
}

/** A pull request shaped like the one in the bug report: most files viewed (collapsed), one large-diff placeholder. */
const REPORTED_PR = [
  { path: 'docs/guide.md', viewed: true },
  { path: 'src/app/agents/limits.ts', viewed: true },
  { path: 'src/app/models/trail.test.ts', viewed: true },
  { path: 'src/app/models/registry.test.ts', viewed: true },
  { path: 'src/app/models/registry.ts', viewed: true },
  { path: 'src/app/telemetry/trail.ts' },
  { path: 'src/app/routes/stream/__tests__/error.test.ts', viewed: true },
  { path: 'src/app/utils/redact.test.ts', viewed: true },
  { path: 'src/app/utils/redact.ts', largeDiff: true },
  { path: 'src/app/utils/logger.test.ts', viewed: true },
  { path: '.env.example' },
]
const COLLAPSED = 48, EXPANDED = 600, PLACEHOLDER = 160
const REPORTED_HEIGHTS = REPORTED_PR.map((f) => f.viewed ? COLLAPSED : f.largeDiff ? PLACEHOLDER : EXPANDED)

describe('cursor on a page of collapsed files with a large-diff placeholder', () => {
  beforeEach(() => { storage._resetForTests(); document.body.innerHTML = '' })

  it('renders the large-diff placeholder with a container and a header, and no diff table', () => {
    mountFilesPage({ files: REPORTED_PR, containers: true })
    const box = document.getElementById(`diff-${digestOf('src/app/utils/redact.ts')}`)!
    expect(box.querySelector('h3 a[href^="#diff-"]')).not.toBeNull()
    expect(box.querySelector('table')).toBeNull()
    expect(box.textContent).toContain('Large diffs are not rendered by default.')
  })

  // The app log of the report: steps to files 1..4 read back fine, then every "next" from the 4th file
  // jumped to the 5th and the cursor read the 4th again ("from 3 to 4" a dozen times). The only geometry
  // that gives that is a box of the 4th file still covering the top edge after the 5th was put there.
  // A box that starts above the file at the top and reaches below it (a stale height kept by a collapsed
  // file, a wrapper) must not win over the file that starts at the top edge.
  const STALE = { 3: { height: 1200 } }   // the 4th file's box reaches over the 5th, 6th and 7th

  it('takes the file starting at the top edge over an earlier box that reaches past it', async () => {
    mountFilesPage({ files: REPORTED_PR, containers: true })
    const api = install({ post: () => {} })
    const page = layoutPage(REPORTED_PR.map((f) => f.path), REPORTED_HEIGHTS, STALE)
    page.scrollTo(3)
    expect(await api.currentFile()).toMatchObject({ index: 3, total: 11, viewed: true })
    page.scrollTo(4)
    expect(await api.currentFile()).toMatchObject({ path: 'src/app/models/registry.ts', index: 4 })
    page.scrollTo(5)
    expect(await api.currentFile()).toMatchObject({ path: 'src/app/telemetry/trail.ts', index: 5, viewed: false })
  })

  it('steps from the 4th file to the 5th and on to the 6th', async () => {
    mountFilesPage({ files: REPORTED_PR, containers: true })
    const api = install({ post: () => {} })
    const page = layoutPage(REPORTED_PR.map((f) => f.path), REPORTED_HEIGHTS, STALE)
    page.scrollTo(3)
    expect(await api.stepFile(1)).toMatchObject({ moved: true, from: 3, to: 4, via: 'element' })
    expect(page.scrollY()).toBe(page.topOf(4))
    expect(await api.stepFile(1)).toMatchObject({ moved: true, from: 4, to: 5 })
    expect(await api.stepFile(-1)).toMatchObject({ moved: true, from: 5, to: 4 })
  })

  it('marks the unviewed file under the cursor and moves to the next unviewed, the large-diff one', async () => {
    mountFilesPage({ files: REPORTED_PR, containers: true })
    const api = install({ post: () => {} })
    const page = layoutPage(REPORTED_PR.map((f) => f.path), REPORTED_HEIGHTS, STALE)
    page.scrollTo(3)
    expect(await api.markCurrentAndNext()).toEqual({ marked: false, moved: true })   // the 4th is viewed: only moves
    expect(page.scrollY()).toBe(page.topOf(5))
    expect(await api.markCurrentAndNext()).toEqual({ marked: true, moved: true })    // the 6th: marked, then the 9th
    const button = (path: string) => document.querySelector(`#diff-${digestOf(path)} button[aria-pressed]`)!
    expect(button('src/app/telemetry/trail.ts').getAttribute('aria-pressed')).toBe('true')
    expect(page.scrollY()).toBe(page.topOf(8))
    expect(await api.currentFile()).toMatchObject({ path: 'src/app/utils/redact.ts', index: 8, viewed: false })
    expect(await api.markCurrentAndNext()).toEqual({ marked: true, moved: true })    // the placeholder's Viewed button works too
    expect(button('src/app/utils/redact.ts').getAttribute('aria-pressed')).toBe('true')
    expect(page.scrollY()).toBe(page.topOf(10))
  })

  it('takes the later file when a box of an earlier one sits at the same top edge (a header stuck at the top)', async () => {
    mountFilesPage({ files: REPORTED_PR, containers: true })
    const api = install({ post: () => {} })
    const page = layoutPage(REPORTED_PR.map((f) => f.path), REPORTED_HEIGHTS, { 3: { from: REPORTED_HEIGHTS[3]! + 8, height: COLLAPSED } })
    page.scrollTo(4)                                   // the 4th's box sits exactly where the 5th starts
    expect(await api.currentFile()).toMatchObject({ index: 4 })
  })
})

/** The end of a pull request, as measured by the user's probe: the last files can never reach the top edge. */
const END_PR = [
  ...['docs/a.md', 'src/b.ts', 'src/c.ts', 'src/d.ts', 'src/e.ts', 'src/f.ts'].map((path) => ({ path, viewed: true })),
  { path: 'src/g.ts' }, { path: 'src/h.ts' }, { path: 'src/i.ts' },
]
const END_HEIGHTS = [42, 42, 42, 42, 42, 42, 371, 42, 459]
const END_VIEWPORT = 833

describe('jump intent at the end of the page', () => {
  beforeEach(() => { storage._resetForTests(); document.body.innerHTML = '' })
  // install() has no teardown: let the 600 ms re-read that setSettings schedules land here, not in the next test.
  afterEach(async () => { await wait(700) })
  const paths = END_PR.map((f) => f.path)
  const setup = (events: Event[] = []) => {
    mountFilesPage({ files: END_PR, containers: true })
    const api = install({ post: (e) => events.push(e) })
    // No compare memory: install() has no teardown, and this watcher outlives the test (it would restore marks in later ones).
    api.setSettings({ rememberCompare: false })
    const page = layoutPage(paths, END_HEIGHTS, {}, END_VIEWPORT)
    page.setScroll(page.maxScroll)                       // scrolled to the end: the 7th file covers the top edge
    return { api, page }
  }

  it('steps to the last files even though the page cannot scroll them to the top', async () => {
    const { api, page } = setup()
    expect(await api.currentFile()).toMatchObject({ index: 6 })
    expect(await api.stepFile(1)).toMatchObject({ moved: true, from: 6, to: 7 })
    expect(page.scrollY()).toBe(page.maxScroll)          // nothing moved
    expect(await api.currentFile()).toMatchObject({ path: 'src/h.ts', index: 7 })
    expect(await api.stepFile(1)).toMatchObject({ moved: true, from: 7, to: 8 })
    expect(await api.currentFile()).toMatchObject({ path: 'src/i.ts', index: 8 })
    expect(await api.stepFile(1)).toMatchObject({ moved: false, from: 8 })
    expect(await api.stepFile(-1)).toMatchObject({ moved: true, from: 8, to: 7 })
  })

  it('marks the file it jumped to, not the one covering the top edge', async () => {
    const { api } = setup()
    await api.stepFile(1)                                // onto the 8th
    expect(await api.markCurrentAndNext()).toEqual({ marked: true, moved: true })
    const pressed = (path: string) => document.querySelector(`#diff-${digestOf(path)} button[aria-pressed]`)!.getAttribute('aria-pressed')
    expect(pressed('src/h.ts')).toBe('true')
    expect(pressed('src/g.ts')).toBe('false')
    expect(await api.currentFile()).toMatchObject({ path: 'src/i.ts', index: 8, viewed: false })
    expect(await api.markCurrentAndNext()).toEqual({ marked: true, moved: false })   // the last one, nothing after it
    expect(pressed('src/i.ts')).toBe('true')
  })

  it('goes back to the geometry when the user scrolls', async () => {
    const events: Event[] = []
    const { api, page } = setup(events)
    await api.stepFile(1)
    await api.stepFile(1)
    page.setScroll(page.topOf(4))                        // the user scrolls up to the 5th file
    window.dispatchEvent(new Event('scroll'))
    await wait(250)
    expect((events.filter((e) => e.name === 'current').at(-1)!.payload as any)).toMatchObject({ index: 4 })
    page.setScroll(page.maxScroll)                       // and back down: the edge rules again, not the old jump
    expect(await api.currentFile()).toMatchObject({ index: 6 })
  })

  it('forgets the jump on a navigation to another pull request', async () => {
    const events: Event[] = []
    const { api } = setup(events)
    await api.stepFile(1)
    await api.stepFile(1)
    mountFilesPage({ files: END_PR, containers: true, basePath: '/acme/web/pull/43' })   // same files, same scroll
    const page = layoutPage(paths, END_HEIGHTS, {}, END_VIEWPORT)
    page.setScroll(page.maxScroll)
    await vi.waitFor(() => expect(events.some((e) => e.name === 'context' && (e.payload as any).basePath === '/acme/web/pull/43')).toBe(true))
    expect(await api.currentFile()).toMatchObject({ index: 6 })
  })
})

describe('review script API', () => {
  beforeEach(() => { storage._resetForTests(); document.body.innerHTML = ''; userScrolls(0) })

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
    tops['a.ts'] = -900; tops['b.ts'] = -200; userScrolls(1100)    // reading b (its box covers the top edge)
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
    expect((await api.stepFile(-1)).moved).toBe(true)    // back from c, where the jump went (the page did not scroll): b
    expect(calls).toEqual(['c.ts', 'b.ts'])
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
    tops['b.ts'] = -400; tops['c.ts'] = 40; userScrolls(460)
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
