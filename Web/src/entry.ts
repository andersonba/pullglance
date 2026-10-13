import { markMatching, undo as undoAction, loadAll } from '@/core/actions'
import { matchFiles } from '@/core/matcher'
import type { FileListing, Receipt, Rule } from '@/core/model'
import { OperationLock } from '@/core/lock'
import { DEFAULT_SETTINGS, normalize, rulesFromSettings, type Settings } from '@/features/tests/settings'
import { createGitHubAdapter, type GitHubAdapter } from '@/hosts/github/adapter'

export interface Context { kind: 'pull' | 'compare' | 'other'; basePath: string; key: string | null }
export interface Counts { total: number; viewed: number; matching: number; partial: boolean; perRule: Record<string, number> }
export interface MarkResult { marked: number; failed: number; skipped: number; unknown: number; canUndo: boolean }
export interface Deps { post(event: { name: string; payload: unknown }): void; adapter?: GitHubAdapter }
/** The file the reader is on: the last header that crossed the cursor line, else the first on the page. */
export interface FileCursor { id: string; path: string; index: number; total: number; viewed: boolean }

/** What a step decided, for the app's verbose log. */
export interface StepReport { moved: boolean; from: number | null; to: number | null; total: number; via?: 'element' | 'hash' }

const CURSOR_PROBE = 4           // px below the visible top: the file whose box covers this point is the current one
const CURSOR_NEAR = 72           // a file starting this close below the visible top counts too (gaps between diffs)
const CURSOR_THROTTLE_MS = 150
const ANCHOR_MS = 1500           // after a jump: how long layout shifts above the file are compensated (WebKit has no scroll anchoring)
const LISTING_MIN_INTERVAL_MS = 1000

export function install(deps: Deps) {
  const adapter = deps.adapter ?? createGitHubAdapter()
  let settings: Settings = DEFAULT_SETTINGS
  let rules: Rule[] = rulesFromSettings(settings)
  let lastReceipt: Receipt | null = null
  const lock = new OperationLock()

  const context = (): Context => {
    const kind = adapter.pageKind() === 'pull' ? 'pull' : adapter.pageKind() === 'compare' ? 'compare' : 'other'
    const ctx = adapter.currentContext()
    return { kind, basePath: ctx?.basePath ?? location.pathname, key: ctx?.key ?? null }
  }

  const selectRules = (ruleIds: string[] | null): Rule[] =>
    ruleIds === null ? rules : rules.map((r) => ({ ...r, enabled: ruleIds.includes(r.id) }))

  async function counts(ruleIds: string[] | null): Promise<Counts> {
    const listing = await adapter.listFiles()
    const unviewed = listing.files.filter((f) => !f.viewed)
    const perRule: Record<string, number> = {}
    for (const r of rules) perRule[r.id] = matchFiles(unviewed, [{ ...r, enabled: true }]).length
    return {
      total: listing.files.length,
      viewed: listing.files.length - unviewed.length,
      matching: matchFiles(unviewed, selectRules(ruleIds)).length,
      partial: listing.completeness === 'partial',
      perRule,
    }
  }

  async function mark(ruleIds: string[] | null): Promise<MarkResult> {
    return lock.run(async (signal) => {
      if (settings.loadBeforeMark && (await adapter.listFiles()).completeness === 'partial') await loadAll(adapter, undefined, signal)
      const receipt = await markMatching(adapter, selectRules(ruleIds), { signal, verify: settings.verify && adapter.pageKind() === 'pull' })
      lastReceipt = receipt.marked.length > 0 || receipt.unknown.length > 0 ? receipt : null
      invalidateListing()
      return { marked: receipt.marked.length, failed: receipt.failed.length, skipped: receipt.skipped.length, unknown: receipt.unknown.length, canUndo: lastReceipt !== null }
    })
  }

  async function undo(): Promise<{ marked: number; failed: number }> {
    if (!lastReceipt) throw new Error('nothing to undo')
    return lock.run(async (signal) => {
      const r = await undoAction(adapter, lastReceipt!, { signal })
      lastReceipt = null
      invalidateListing()
      return { marked: r.marked.length, failed: r.failed.length }
    })
  }

  async function unmarkAll(): Promise<{ marked: number; failed: number }> {
    return lock.run(async (signal) => {
      const listing = await adapter.listFiles()
      let marked = 0, failed = 0
      for (const f of listing.files.filter((x) => x.viewed)) {
        try { await adapter.setViewed(f, false, signal); marked++ } catch { failed++ }
      }
      lastReceipt = null
      invalidateListing()
      return { marked, failed }
    })
  }

  // ---- the files on the page ----
  // The listing is the adapter's (page order, ids, viewed flags) and is refreshed by the listing watcher, not
  // on every scroll: reading it is the expensive part. Geometry comes from the diff containers (`#diff-<id>`,
  // present in both UIs; the new UI's header is sticky and useless for positions).
  let cachedListing: FileListing | null = null
  // An empty listing is never cached: it is what a page that has not rendered its files yet looks like.
  const files = async (): Promise<FileListing> => {
    if (cachedListing) return cachedListing
    const listing = await adapter.listFiles()
    if (listing.files.length > 0) cachedListing = listing
    return listing
  }
  const invalidateListing = () => { cachedListing = null }
  const elementOf = (id: string): Element | null => document.getElementById(`diff-${id}`) ?? adapter.resolver.headerById(id)?.el ?? null

  /**
   * Where the page's content actually begins: below whatever fixed or sticky chrome covers the top of the
   * viewport (GitHub's pull request header bar, ~125 px on the new UI). Measured at the diff column.
   */
  const visibleTop = (sampleId?: string): number => {
    const column = sampleId ? elementOf(sampleId)?.getBoundingClientRect() : null
    const x = column ? Math.min(Math.max(column.left + column.width / 2, 1), window.innerWidth - 1) : window.innerWidth / 2
    let top = 0
    const stack: Element[] = typeof document.elementsFromPoint === 'function' ? document.elementsFromPoint(x, 1) : []
    for (const el of stack) {
      const position = getComputedStyle(el).position
      if (position !== 'fixed' && position !== 'sticky') continue
      const r = el.getBoundingClientRect()
      if (r.top <= 1 && r.bottom > top && r.height < window.innerHeight / 2) top = r.bottom
    }
    return top
  }

  /**
   * Where the reader is: the file whose box covers the top edge; else one starting just below it (the gap
   * between two diffs); else the last one above. -1 when the page is above every file.
   */
  async function cursorIndex(listing: FileListing): Promise<number> {
    const line = visibleTop(listing.files[0]?.id) + CURSOR_PROBE
    const placed = listing.files.flatMap((f, index) => {
      const r = elementOf(f.id)?.getBoundingClientRect()
      return r ? [{ index, top: r.top, bottom: r.bottom }] : []
    })
    const covering = placed.find((x) => x.top <= line && x.bottom > line)
    const near = placed.find((x) => x.top > line && x.top <= line + CURSOR_NEAR)
    const above = placed.filter((x) => x.top <= line)
    return (covering ?? near ?? above[above.length - 1])?.index ?? -1
  }

  /** Why there is no cursor, for the app's log: the list failed to read, is empty, or has no element on the page yet. */
  let noCursorReason = ''
  async function currentFile(): Promise<FileCursor | null> {
    let listing: FileListing | null = null
    try { listing = await files() } catch (e) { noCursorReason = `read failed: ${(e as Error)?.name ?? 'error'}`; return null }
    if (listing.files.length === 0) { noCursorReason = 'empty listing'; return null }
    const index = await cursorIndex(listing)
    if (index < 0 && !listing.files.some((f) => elementOf(f.id))) { noCursorReason = `no element for ${listing.files.length} files`; return null }
    const f = listing.files[Math.max(index, 0)]!
    return { id: f.id, path: f.path, index: Math.max(index, 0), total: listing.files.length, viewed: f.viewed }
  }

  let settingsReady = false
  let lastCursorKey = ''
  const postCursor = async () => {
    if (!settingsReady) return
    const cursor = await currentFile()
    const key = cursor ? `${cursor.id}|${cursor.index}|${cursor.total}|${cursor.viewed}` : `none:${noCursorReason}`
    if (key === lastCursorKey) return
    lastCursorKey = key
    deps.post({ name: 'current', payload: cursor ?? { none: noCursorReason } })
  }
  let scrollTimer: ReturnType<typeof setTimeout> | null = null
  // Capture phase: scroll events do not bubble, and GitHub may scroll an inner pane rather than the window.
  document.addEventListener('scroll', () => {
    if (scrollTimer) return
    scrollTimer = setTimeout(() => { scrollTimer = null; void postCursor() }, CURSOR_THROTTLE_MS)
  }, { passive: true, capture: true })

  // Scroll anchoring by hand. Diffs render lazily; when one above the file we jumped to gets its real height,
  // the page shifts under the reader. Chrome compensates natively, WebKit does not. For a short while after a
  // jump: if the page did not scroll between two frames but the file moved, move the page by the same amount.
  let stopAnchor: (() => void) | null = null
  const anchor = (el: Element) => {
    stopAnchor?.()
    const until = performance.now() + ANCHOR_MS
    let lastY = window.scrollY
    let lastTop = el.getBoundingClientRect().top
    let frame = 0
    const tick = () => {
      const y = window.scrollY
      const top = el.getBoundingClientRect().top
      if (y === lastY && Math.abs(top - lastTop) > 0.5) window.scrollBy(0, top - lastTop)
      lastY = window.scrollY
      lastTop = el.getBoundingClientRect().top
      if (performance.now() < until) frame = requestAnimationFrame(tick)
      else stopAnchor = null
    }
    frame = requestAnimationFrame(tick)
    stopAnchor = () => { cancelAnimationFrame(frame); stopAnchor = null }
  }

  /** Puts a file at the top. Instant: a smooth scroll dies on the first lazy render in WebKit. */
  const jumpTo = (id: string): 'element' | 'hash' => {
    const el = elementOf(id)
    if (el) {
      el.scrollIntoView({ block: 'start' })
      // Then under the page's fixed header, where the content really starts (scroll-margin-top may or may not be set).
      const off = el.getBoundingClientRect().top - visibleTop(id)
      if (Math.abs(off) > 0.5) window.scrollBy({ top: off, behavior: 'instant' as ScrollBehavior })
      anchor(el)
    } else {
      if (location.hash === `#diff-${id}`) location.hash = ''
      location.hash = `#diff-${id}`
    }
    lastCursorKey = ''
    setTimeout(() => { void postCursor() }, 250)
    return el ? 'element' : 'hash'
  }

  /** Next (+1) or previous (-1) file in page order, viewed or not. */
  async function stepFile(delta: number): Promise<StepReport> {
    const listing = await files()
    const from = await cursorIndex(listing)
    const to = from + delta
    const target = listing.files[to]
    if (!target) return { moved: false, from, to: null, total: listing.files.length }
    return { moved: true, from, to, total: listing.files.length, via: jumpTo(target.id) }
  }

  /** Next or previous file not yet viewed, from where the reader is. */
  async function scrollToUnviewed(direction: 'next' | 'previous'): Promise<boolean> {
    const listing = await files()
    const from = await cursorIndex(listing)
    const target = direction === 'next'
      ? listing.files.find((f, i) => i > from && !f.viewed)
      : [...listing.files].reverse().find((f) => listing.files.indexOf(f) < from && !f.viewed)
    if (!target) return false
    jumpTo(target.id)
    return true
  }

  /** Marks or unmarks the file under the cursor without moving. */
  async function setCurrentViewed(viewed: boolean): Promise<boolean> {
    return lock.run(async (signal) => {
      const cursor = await currentFile()
      if (!cursor || cursor.viewed === viewed) return false
      const file = (await files()).files.find((f) => f.id === cursor.id)
      if (!file) return false
      await adapter.setViewed(file, viewed, signal)
      invalidateListing()
      lastCursorKey = ''
      void postCursor()
      return true
    })
  }

  /** Marks the current file as viewed (when it is not) and moves to the next unviewed one. */
  async function markCurrentAndNext(): Promise<{ marked: boolean; moved: boolean }> {
    return lock.run(async (signal) => {
      const cursor = await currentFile()
      let marked = false
      if (cursor && !cursor.viewed) {
        const file = (await files()).files.find((f) => f.id === cursor.id)
        if (file) { await adapter.setViewed(file, true, signal); marked = true; invalidateListing() }
      }
      const moved = await scrollToUnviewed('next')
      return { marked, moved }
    })
  }
  // Nothing reads the file list (which restores and writes compare memory) before the app's settings arrive:
  // the listing watcher starts on the first setSettings.
  let listingWatch: ListingWatch | null = null

  adapter.onContextChange((ctx) => {
    if (ctx === null || ctx.key !== lastReceipt?.context.key) lastReceipt = null
    lock.cancel()
    deps.post({ name: 'context', payload: context() })
    invalidateListing()
    lastCursorKey = ''
    listingWatch?.reset()
    for (const ms of [600, 1500, 3000]) setTimeout(() => { invalidateListing(); void postCursor() }, ms)
  })
  deps.post({ name: 'context', payload: context() })

  // The app's review shortcuts (⇧⌘V, ⌘↑/⌘↓) must leave the keys to a field the caret is in.
  let editing = false
  const updateEditing = () => {
    const el = document.activeElement as HTMLElement | null
    const active = el != null && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.isContentEditable === true)
    if (active === editing) return
    editing = active
    deps.post({ name: 'editing', payload: { active } })
  }
  document.addEventListener('focusin', updateEditing)
  // On focusout the next element is not active yet; read it after the focus move settles.
  document.addEventListener('focusout', () => { queueMicrotask(updateEditing) })

  const api = {
    context,
    setSettings: (s: Partial<Settings>) => {
      settings = normalize(s)
      rules = rulesFromSettings(settings)
      adapter.configure({ rememberCompare: settings.rememberCompare })
      settingsReady = true
      listingWatch ??= watchListing(adapter, (listing) => { cachedListing = listing; void postCursor() }, (payload) => deps.post({ name: 'listing', payload }))
      // The file list may render after the first read (a navigation inside GitHub): look again a few times.
      for (const ms of [600, 1500, 3000]) setTimeout(() => { invalidateListing(); void postCursor() }, ms)
    },
    counts, mark, undo, unmarkAll, scrollToUnviewed,
    currentFile, stepFile, markCurrentAndNext, setCurrentViewed,
    flush: () => adapter.flushMemory(),
  }
  return api
}

const LISTING_DEBOUNCE_MS = 200
const EMPTY_LISTING = { total: 0, viewed: 0, partial: false }

interface ListingWatch { reset(): void }

/**
 * Posts `{ total, viewed, partial }` now and again whenever it changes (debounced DOM observation).
 * `reset()` forgets the last value (a new context posts even with the same numbers). When the file list
 * goes away after a success, the empty listing is posted once.
 */
function watchListing(adapter: GitHubAdapter, onListing: (listing: FileListing) => void, post: (listing: typeof EMPTY_LISTING) => void): ListingWatch {
  let last = ''          // dedupe key of the last post; reset() clears it
  let showing = false    // the app is showing a non-empty listing from this page
  let timer: ReturnType<typeof setTimeout> | null = null
  let lastRun = 0        // reading the list is the expensive part: at most once a second while the page mutates
  const emit = (payload: typeof EMPTY_LISTING) => {
    const key = JSON.stringify(payload)
    if (key === last) return
    last = key
    showing = payload.total > 0
    post(payload)
  }
  const check = async () => {
    lastRun = Date.now()
    const listing = await adapter.listFiles().catch(() => null)
    if (!listing) { if (showing) emit(EMPTY_LISTING); return }
    onListing(listing)
    emit({ total: listing.files.length, viewed: listing.files.filter((f) => f.viewed).length, partial: listing.completeness === 'partial' })
  }
  const schedule = () => {
    if (timer) clearTimeout(timer)
    const wait = Math.max(LISTING_DEBOUNCE_MS, lastRun + LISTING_MIN_INTERVAL_MS - Date.now())
    timer = setTimeout(() => { timer = null; void check() }, wait)
  }
  // Viewed state lives in classes and ARIA attributes (classic collapse, aria-pressed buttons), not only in child lists.
  new MutationObserver(schedule).observe(document.documentElement, {
    childList: true, subtree: true, attributes: true, attributeFilter: ['class', 'aria-pressed', 'aria-expanded'],
  })
  void check()
  return { reset: () => { last = ''; lastRun = 0; schedule() } }
}

// Installed by the app's WKUserScript in the isolated world; tests call install() directly.
if (typeof window !== 'undefined' && (window as any).webkit?.messageHandlers?.reviewEvent) {
  const post = (e: { name: string; payload: unknown }) => (window as any).webkit.messageHandlers.reviewEvent.postMessage(e)
  ;(window as any).__pullglanceReview = install({ post })
  window.addEventListener('pagehide', () => { void (window as any).__pullglanceReview.flush() })
}
