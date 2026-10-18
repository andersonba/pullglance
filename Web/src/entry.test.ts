import { install as installScript } from './entry'
import { mountComparePage, mountFilesPage, digestOf } from './test-fixtures'
import { DEFAULT_SETTINGS } from '@/features/tests/settings'
import { storage } from '#imports'
import { HIDE_ATTR, VIEWED_ATTR } from '@/features/tree/hide-viewed'

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

// Every install is disposed after its test: the document is shared, and a watcher left behind would read
// (and, on a compare page, mark up) the page of the next test, at a moment that depends on machine speed.
const installed: Array<{ dispose(): void }> = []
const install: typeof installScript = (deps) => { const api = installScript(deps); installed.push(api); return api }
afterEach(() => { for (const api of installed.splice(0)) api.dispose() })

/**
 * A page that scrolls: each file's `#diff-<id>` box sits at a page offset, the window has a scrollY, and
 * scrollIntoView / scrollBy move it. `boxes` overrides a file's box (offset from its page top, height).
 */
function layoutPage(paths: string[], initialHeights: number[], boxes: Record<number, { from?: number; height: number }> = {}, viewport = 0) {
  const heights = [...initialHeights]
  let tops: number[] = []
  let maxScroll = 0
  const recompute = () => {
    tops = []
    let y = 0
    for (const h of heights) { tops.push(y); y += h + 8 }
    maxScroll = Math.max(0, y - 8 - viewport)   // the window cannot scroll past the end of the document
  }
  recompute()
  const clamp = (v: number) => Math.min(Math.max(v, 0), maxScroll)
  let scrollY = 0
  Object.defineProperty(window, 'scrollY', { configurable: true, get: () => scrollY })
  const scrollBy = (a: number | ScrollToOptions, b?: number) => { scrollY = clamp(scrollY + (typeof a === 'number' ? (b ?? 0) : (a.top ?? 0))) }
  ;(window as any).scrollBy = scrollBy
  const patch = () => paths.forEach((path, i) => {
    const el = document.getElementById(`diff-${digestOf(path)}`) as any
    if (!el) return
    const box = boxes[i]
    el.getBoundingClientRect = () => {
      const top = tops[i]! + (box?.from ?? 0) - scrollY
      return { top, bottom: top + (box?.height ?? heights[i]!), left: 300, width: 900, height: box?.height ?? heights[i]! } as DOMRect
    }
    el.scrollIntoView = () => { scrollY = clamp(tops[i]!) }
  })
  patch()
  return {
    scrollTo: (index: number) => { scrollY = clamp(tops[index]!) }, scrollY: () => scrollY, topOf: (i: number) => tops[i]!,
    get maxScroll() { return maxScroll }, setScroll: (v: number) => { scrollY = clamp(v) },
    /** A file changed height (collapsed after a mark): later files move up. */
    setHeight: (i: number, h: number) => { heights[i] = h; recompute() },
    /** GitHub re-rendered: the file nodes are new objects, patch them again. */
    repatch: patch,
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
/// The same page with the 5th file (viewed) left open: a viewed file that is being read keeps the cursor, so
/// these geometry tests see the geometry alone (a collapsed viewed file at the top yields to the next unviewed).
const REPORTED_HEIGHTS_5TH_OPEN = REPORTED_HEIGHTS.map((h, i) => i === 4 ? EXPANDED : h)

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
    const page = layoutPage(REPORTED_PR.map((f) => f.path), REPORTED_HEIGHTS_5TH_OPEN, STALE)
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

  it('highlights the file the cursor is on, and moves the highlight when stepping', async () => {
    mountFilesPage({ files: REPORTED_PR, containers: true })
    const api = install({ post: () => {} })
    const page = layoutPage(REPORTED_PR.map((f) => f.path), REPORTED_HEIGHTS, STALE)
    page.scrollTo(3)
    const box = (i: number) => document.getElementById(`diff-${digestOf(REPORTED_PR[i]!.path)}`)!
    await api.currentFile()
    expect(box(3).classList.contains('pullglance-current')).toBe(true)
    await api.stepFile(1)
    await api.currentFile()
    expect(box(3).classList.contains('pullglance-current')).toBe(false)
    expect(box(4).classList.contains('pullglance-current')).toBe(true)
    expect(document.getElementById('pullglance-style')).not.toBeNull()
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

  /// What the new Files UI does: the mark is confirmed, then the file collapses a moment later and React
  /// swaps the nodes. The jump must land on the next unviewed file, not on the one just marked.
  it('still lands on the next unviewed file when the marked one collapses late and its node is replaced', async () => {
    mountFilesPage({ files: REPORTED_PR, containers: true })
    const api = install({ post: () => {} })
    const page = layoutPage(REPORTED_PR.map((f) => f.path), REPORTED_HEIGHTS, STALE)
    page.scrollTo(5)
    expect(await api.currentFile()).toMatchObject({ index: 5, viewed: false })
    const marked = document.getElementById(`diff-${digestOf('src/app/telemetry/trail.ts')}`)!
    const target = document.getElementById(`diff-${digestOf('src/app/utils/redact.ts')}`)!
    // After the click confirms: 60 ms later the marked file shrinks and the target node is swapped.
    marked.addEventListener('click', () => {
      setTimeout(() => {
        page.setHeight(5, COLLAPSED)
        target.replaceWith(target.cloneNode(true))
        page.repatch()
      }, 60)
    }, { capture: true })
    expect(await api.markCurrentAndNext()).toEqual({ marked: true, moved: true })
    await wait(400)
    expect(page.scrollY()).toBe(page.topOf(8))
    expect(await api.currentFile()).toMatchObject({ path: 'src/app/utils/redact.ts', index: 8, viewed: false })
  })

  /// Also what the new Files UI does: after the click it moves focus to the marked file's header, and the
  /// browser scrolls that header into view, right under the page's bar. The reader asked for the next file.
  it('keeps the next unviewed file at the top when GitHub scrolls the marked one back into view', async () => {
    mountFilesPage({ files: REPORTED_PR, containers: true })
    const api = install({ post: () => {} })
    const page = layoutPage(REPORTED_PR.map((f) => f.path), REPORTED_HEIGHTS, STALE)
    page.scrollTo(5)
    const marked = document.getElementById(`diff-${digestOf('src/app/telemetry/trail.ts')}`)!
    marked.addEventListener('click', () => {
      setTimeout(() => { page.setHeight(5, COLLAPSED); page.setScroll(page.topOf(5)) }, 60)   // focus → scrollIntoView(marked)
    }, { capture: true })
    expect(await api.markCurrentAndNext()).toEqual({ marked: true, moved: true })
    await wait(400)
    expect(page.scrollY()).toBe(page.topOf(8))
    expect(await api.currentFile()).toMatchObject({ path: 'src/app/utils/redact.ts', index: 8, viewed: false })
  })

  it('takes the later file when a box of an earlier one sits at the same top edge (a header stuck at the top)', async () => {
    mountFilesPage({ files: REPORTED_PR, containers: true })
    const api = install({ post: () => {} })
    const page = layoutPage(REPORTED_PR.map((f) => f.path), REPORTED_HEIGHTS_5TH_OPEN, { 3: { from: REPORTED_HEIGHTS[3]! + 8, height: COLLAPSED } })
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
  const paths = END_PR.map((f) => f.path)
  const setup = (events: Event[] = []) => {
    mountFilesPage({ files: END_PR, containers: true })
    const api = install({ post: (e) => events.push(e) })
    api.setSettings({})
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
    page.setScroll(page.topOf(4))                        // the user scrolls up to the 5th file, a collapsed viewed one
    window.dispatchEvent(new Event('scroll'))
    await wait(250)
    // Not the jump's 9th: the edge rules again, and it yields the collapsed 5th to the 7th, the first unviewed in view.
    expect((events.filter((e) => e.name === 'current').at(-1)!.payload as any)).toMatchObject({ index: 6 })
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

  /// Opening a review request: land on the first file that still needs eyes, wherever the reader is.
  it('firstUnviewed goes to the first unviewed file from the top, even while reading a later one', async () => {
    mountFilesPage({ files: [{ path: 'a.ts', viewed: true }, { path: 'b.ts' }, { path: 'c.ts' }], containers: true })
    const api = install({ post: () => {} })
    const page = layoutPage(['a.ts', 'b.ts', 'c.ts'], [COLLAPSED, EXPANDED, EXPANDED])
    page.scrollTo(2)                                    // reading c
    expect(await api.firstUnviewed()).toBe(true)
    expect(page.scrollY()).toBe(page.topOf(1))          // b, not c: the first from the top
    expect(await api.currentFile()).toMatchObject({ path: 'b.ts', index: 1, viewed: false })
    await wait(300)                                     // the jump's deferred cursor read must not land in the next test
  })

  it('firstUnviewed reports false when everything is viewed', async () => {
    mountFilesPage({ files: [{ path: 'a.ts', viewed: true }], containers: true })
    const api = install({ post: () => {} })
    layoutPage(['a.ts'], [COLLAPSED])
    expect(await api.firstUnviewed()).toBe(false)
  })

  /// Files with open review threads come from the app (GraphQL); the page only has to walk them in order.
  it('stepAmong walks the given files in page order, forward and back, wrapping around', async () => {
    mountFilesPage({ files: [{ path: 'a.ts' }, { path: 'b.ts' }, { path: 'c.ts' }, { path: 'd.ts' }], containers: true })
    const api = install({ post: () => {} })
    const page = layoutPage(['a.ts', 'b.ts', 'c.ts', 'd.ts'], [EXPANDED, EXPANDED, EXPANDED, EXPANDED])
    page.scrollTo(0)
    expect(await api.stepAmong(['b.ts', 'd.ts'], 1)).toEqual({ moved: true, collapsed: false })
    expect(await api.currentFile()).toMatchObject({ path: 'b.ts' })
    expect(await api.stepAmong(['b.ts', 'd.ts'], 1)).toEqual({ moved: true, collapsed: false })
    expect(await api.currentFile()).toMatchObject({ path: 'd.ts' })
    expect(await api.stepAmong(['b.ts', 'd.ts'], 1)).toEqual({ moved: true, collapsed: false })      // past the last: around to the first
    expect(await api.currentFile()).toMatchObject({ path: 'b.ts' })
    expect(await api.stepAmong(['b.ts', 'd.ts'], -1)).toEqual({ moved: true, collapsed: false })     // before the first: around to the last
    expect(await api.currentFile()).toMatchObject({ path: 'd.ts' })
    expect(await api.stepAmong(['nope.ts'], 1)).toEqual({ moved: false, collapsed: false })
    await wait(300)
  })

  /// A thread inside a file already viewed: the file is collapsed. The page says so and is left as it is;
  /// the app tells the reader, who decides whether to open it.
  it('stepAmong reports a collapsed file and leaves it folded and viewed', async () => {
    mountFilesPage({ files: [{ path: 'a.ts' }, { path: 'b.ts', viewed: true }], containers: true })
    const api = install({ post: () => {} })
    const page = layoutPage(['a.ts', 'b.ts'], [EXPANDED, COLLAPSED])
    const box = document.getElementById(`diff-${digestOf('b.ts')}`)!
    page.scrollTo(0)
    expect(await api.stepAmong(['b.ts'], 1)).toEqual({ moved: true, collapsed: true })
    expect(box.querySelector('.diff-file-header.collapsed')).not.toBeNull()                // still folded
    expect(box.querySelector('button[aria-pressed]')!.getAttribute('aria-pressed')).toBe('true')   // still viewed
    await wait(300)
  })

  it('dispose() ends the script: nothing is posted, and a page mounted afterwards is not touched', async () => {
    mountComparePage({ files: [{ path: 'a.ts' }] })
    const events: Event[] = []
    const api = install({ post: (e) => events.push(e) })
    api.setSettings({ ...DEFAULT_SETTINGS })
    await vi.waitFor(() => expect(listingsOf(events)).toHaveLength(1))
    api.dispose()
    const posted = events.length
    document.body.innerHTML = ''
    mountComparePage({ files: [{ path: 'b.ts' }, { path: 'c.ts' }] })
    await wait(1300)                                 // past the listing watcher's minimum interval and the 600 ms re-read
    expect(document.querySelector('button[data-ghra-viewed]')).toBeNull()
    expect(events.length).toBe(posted)
  })
})

describe('file tree: viewed files leave the sidebar', () => {
  it('marks the tree from the listing and follows the setting', async () => {
    mountFilesPage({ files: [{ path: 'src/a.ts', viewed: true }, { path: 'src/b.ts' }], tree: true })
    const api = install({ post: () => {} })
    api.setSettings({})
    await api.counts(null)
    const root = document.querySelector('ul[role="tree"]')!
    expect(root.getAttribute(HIDE_ATTR)).toBe('true')
    expect(document.getElementById('src/a.ts')!.hasAttribute(VIEWED_ATTR)).toBe(true)
    expect(document.getElementById('src/b.ts')!.hasAttribute(VIEWED_ATTR)).toBe(false)
    expect(document.getElementById('src')!.hasAttribute(VIEWED_ATTR)).toBe(false)
    api.setSettings({ treeHidesViewed: false })
    expect(root.hasAttribute(HIDE_ATTR)).toBe(false)
    api.setSettings({ treeHidesViewed: true })
    expect(root.getAttribute(HIDE_ATTR)).toBe('true')
  })

  it('follows a file marked on the page, and dispose takes the marks away', async () => {
    mountFilesPage({ files: [{ path: 'src/a.ts' }, { path: 'src/b.ts' }], tree: true })
    const api = install({ post: () => {} })
    api.setSettings({})
    await api.counts(null)
    expect(document.getElementById('src/a.ts')!.hasAttribute(VIEWED_ATTR)).toBe(false)
    filesHeader('src/a.ts').querySelector('button[aria-label="Not Viewed"]').click()   // the user marks a file on the page
    await vi.waitFor(() => expect(document.getElementById('src/a.ts')!.hasAttribute(VIEWED_ATTR)).toBe(true))   // the listing watcher re-reads
    api.dispose()
    expect(document.querySelector(`[${VIEWED_ATTR}], [${HIDE_ATTR}]`)).toBeNull()
  })
})

describe('cursor prefers the work left: a viewed file at the top edge yields to an unviewed one in view', () => {
  beforeEach(() => { storage._resetForTests(); document.body.innerHTML = '' })
  const MIXED = [{ path: 'src/a.ts', viewed: true }, { path: 'src/b.ts' }, { path: 'src/c.ts', viewed: true }, { path: 'src/d.ts' }]
  const paths = MIXED.map((f) => f.path)

  it('skips a collapsed viewed file when an unviewed one is visible below it', async () => {
    mountFilesPage({ files: MIXED, containers: true })
    const api = install({ post: () => {} })
    api.setSettings({})
    const page = layoutPage(paths, [48, 600, 48, 600], {}, 300)   // tops: 0, 56, 664, 720
    expect(await api.currentFile()).toMatchObject({ path: 'src/b.ts', index: 1 })
    page.setScroll(664)                                         // c's thin header at the top, d right under it
    expect(await api.currentFile()).toMatchObject({ path: 'src/d.ts', index: 3 })
  })

  it('yields from the page top too, where no file has reached the edge yet', async () => {
    mountFilesPage({ files: MIXED, containers: true })
    const api = install({ post: () => {} })
    api.setSettings({})
    // The pull request's header is on screen: the first file box starts 380px down, as on GitHub.
    layoutPage(paths, [48, 600, 48, 600], { 0: { from: 380, height: 48 }, 1: { from: 380, height: 600 }, 2: { from: 380, height: 48 }, 3: { from: 380, height: 600 } }, 943)
    expect(await api.currentFile()).toMatchObject({ path: 'src/b.ts', index: 1 })
  })

  it('yields even when the file was jumped to, once it is marked on the page and collapses', async () => {
    mountFilesPage({ files: [{ path: 'src/a.ts' }, { path: 'src/b.ts' }, { path: 'src/c.ts' }], containers: true })
    const api = install({ post: () => {} })
    api.setSettings({})
    const page = layoutPage(['src/a.ts', 'src/b.ts', 'src/c.ts'], [600, 600, 600], {}, 700)
    await api.firstUnviewed()                                   // the landing jump: the cursor is held on a by intent
    expect(await api.currentFile()).toMatchObject({ path: 'src/a.ts', index: 0 })
    filesHeader('src/a.ts').querySelector('button[aria-label="Not Viewed"]').click()   // GitHub's own button, not ours
    page.setHeight(0, 48)                                       // and the file collapses; nothing scrolled
    await vi.waitFor(async () => expect(await api.currentFile()).toMatchObject({ path: 'src/b.ts', index: 1 }))
  })

  it('stays on a viewed file when no unviewed one is in view, and when every file is viewed', async () => {
    mountFilesPage({ files: [{ path: 'src/a.ts', viewed: true }, { path: 'src/b.ts' }], containers: true })
    let api = install({ post: () => {} })
    api.setSettings({})
    layoutPage(['src/a.ts', 'src/b.ts'], [900, 600], {}, 400)    // a fills the viewport; b starts at 908
    expect(await api.currentFile()).toMatchObject({ path: 'src/a.ts', index: 0 })
    api.dispose()
    mountFilesPage({ files: [{ path: 'src/a.ts', viewed: true }, { path: 'src/b.ts', viewed: true }], containers: true })
    api = install({ post: () => {} })
    api.setSettings({})
    layoutPage(['src/a.ts', 'src/b.ts'], [48, 48], {}, 700)
    expect(await api.currentFile()).toMatchObject({ path: 'src/a.ts', index: 0 })
  })
})

describe('nothing writes to the page before it is ready', () => {
  beforeEach(() => { storage._resetForTests(); document.body.innerHTML = '' })
  const hydrateLater = (ms: number) => setTimeout(() => { document.querySelector('react-app')!.classList.add('loaded') }, ms)

  it('mark waits for the hydration, then marks', async () => {
    mountFilesPage({ files: [{ path: 'src/a.test.ts' }, { path: 'src/b.ts' }], hydrated: false })   // the server's page, app not mounted
    const api = install({ post: () => {} })
    api.setSettings({})
    hydrateLater(80)
    const result = await api.mark(null)
    expect(result).toMatchObject({ marked: 1, failed: 0 })
    expect(result.waitedForPage).toBeGreaterThanOrEqual(50)
  })

  it('a step waits too, and gives up waiting after the limit rather than hanging', async () => {
    mountFilesPage({ files: [{ path: 'src/a.ts' }, { path: 'src/b.ts' }], containers: true, hydrated: false })
    const api = install({ post: () => {}, readyTimeoutMs: 120 })
    api.setSettings({})
    layoutPage(['src/a.ts', 'src/b.ts'], [600, 600], {}, 700)
    const started = Date.now()
    const report = await api.stepFile(1)          // never hydrated: proceeds after the limit
    expect(Date.now() - started).toBeGreaterThanOrEqual(100)
    expect(report.moved).toBe(true)
  })
})
