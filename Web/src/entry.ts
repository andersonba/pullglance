import { markMatching, undo as undoAction, loadAll } from '@/core/actions'
import { matchFiles } from '@/core/matcher'
import type { FileListing, Receipt, Rule } from '@/core/model'
import { OperationLock } from '@/core/lock'
import { DEFAULT_SETTINGS, normalize, rulesFromSettings, type Settings } from '@/features/tests/settings'
import { createGitHubAdapter, type GitHubAdapter } from '@/hosts/github/adapter'

/** `ready` is whether this document's script has received the app's settings: a fresh document says no. */
export interface Context { kind: 'pull' | 'compare' | 'other'; basePath: string; key: string | null; ready: boolean }
export interface Counts { total: number; viewed: number; matching: number; partial: boolean; perRule: Record<string, number> }
export interface MarkResult { marked: number; failed: number; skipped: number; unknown: number; canUndo: boolean }
export interface Deps { post(event: { name: string; payload: unknown }): void; adapter?: GitHubAdapter }
/** The file the reader is on: the last header that crossed the cursor line, else the first on the page. */
export interface FileCursor { id: string; path: string; index: number; total: number; viewed: boolean }

/** What a step decided, for the app's verbose log. */
export interface StepReport { moved: boolean; from: number | null; to: number | null; total: number; via?: 'element' | 'hash'; top?: number; scrollY?: number }

const CURSOR_PROBE = 4           // px below the visible top: the file whose box covers this point is the current one
const CURSOR_NEAR = 72           // a file starting this close below the visible top counts too (gaps between diffs)
const CURSOR_THROTTLE_MS = 150
const ANCHOR_MS = 1500           // after a jump: how long layout shifts above the file are compensated (WebKit has no scroll anchoring)
const HOLD_MS = 600              // after a mark: GitHub moves focus to the marked header and the browser scrolls it into view; the reader asked for the next file
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
    return { kind, basePath: ctx?.basePath ?? location.pathname, key: ctx?.key ?? null, ready: settingsReady }
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
   *
   * Decided by position, not list order: when two boxes cover the edge, the one that starts lower (later on
   * a tie) is the file the reader is on. A box of an earlier file can reach past the top edge (seen on a
   * page of collapsed files): taking the first covering one in list order pinned the cursor to it.
   */
  async function cursorIndex(listing: FileListing): Promise<number> {
    const jumped = intendedIndex(listing)
    if (jumped !== null) return jumped
    const line = visibleTop(listing.files[0]?.id) + CURSOR_PROBE
    const placed = listing.files.flatMap((f, index) => {
      const r = elementOf(f.id)?.getBoundingClientRect()
      return r ? [{ index, top: r.top, bottom: r.bottom }] : []
    })
    type Placed = (typeof placed)[number]
    const lowest = (xs: Placed[]) => xs.reduce<Placed | undefined>((best, x) => !best || x.top >= best.top ? x : best, undefined)
    const covering = lowest(placed.filter((x) => x.top <= line && x.bottom > line))
    const near = placed.filter((x) => x.top > line && x.top <= line + CURSOR_NEAR).reduce<Placed | undefined>((best, x) => !best || x.top < best.top ? x : best, undefined)
    const above = lowest(placed.filter((x) => x.top <= line))
    return (covering ?? near ?? above)?.index ?? -1
  }

  // The file the last jump went to, while the page has not scrolled since. The last files of a pull request
  // can never reach the top edge (the page ends first), so the edge alone cannot say the reader is on them.
  // Programmatic scrolls (the jump, the anchoring) move `scrollY` along; any other scroll is the reader's.
  let intent: { id: string; scrollY: number } | null = null
  const INTENT_SLACK = 2   // px of scrollY drift still counted as "not scrolled"
  const intendedIndex = (listing: FileListing): number | null => {
    if (!intent) return null
    const index = listing.files.findIndex((f) => f.id === intent!.id)
    if (index < 0 || Math.abs(window.scrollY - intent.scrollY) > INTENT_SLACK) { intent = null; return null }
    return index
  }

  // The current file is marked on the page: an accent outline on its box. The pill shows only a position,
  // and on a page of collapsed files a step moves nothing else, so this is how the reader sees where they
  // are. One class, one injected rule; GitHub's own accent color when it has one.
  const HIGHLIGHT_CLASS = 'pullglance-current'
  let highlighted: Element | null = null
  const ensureHighlightStyle = () => {
    if (document.getElementById('pullglance-style')) return
    const style = document.createElement('style')
    style.id = 'pullglance-style'
    // An outline gets clipped by GitHub's overflow:hidden wrappers; a positioned pseudo-element inside the box
    // does not, and the accent bar on the sticky header stays in view while scrolling within the file.
    const accent = 'var(--borderColor-accent-emphasis,var(--fgColor-accent,#0969da))'
    style.textContent = [
      `.${HIGHLIGHT_CLASS}{position:relative}`,
      // Border plus an inset glow. Inset, because the new Files UI paints each file box with containment
      // (virtualized, data-estimated-height): anything drawn outside the box is clipped there, while the
      // classic page shows it. Above the sticky file header (z 5 on the new UI, 2 on the classic), which
      // fills a collapsed box and would otherwise cover the whole thing. Inside the box, both UIs look the same.
      `.${HIGHLIGHT_CLASS}::after{content:"";position:absolute;inset:0;border:2px solid ${accent};border-radius:6px;pointer-events:none;z-index:6;box-shadow:inset 0 0 0 1px var(--bgColor-accent-muted,rgba(9,105,218,.25)),inset 0 0 18px 2px var(--bgColor-accent-muted,rgba(9,105,218,.35))}`,
      `.${HIGHLIGHT_CLASS} [data-diff-header-wrapper="true"],.${HIGHLIGHT_CLASS} .file-header{box-shadow:inset 3px 0 0 ${accent}}`,
    ].join('\n')
    document.head.appendChild(style)
  }
  /** The box standing for a file: the `#diff-<id>` container, else the header's wrapper, else the header. */
  const boxOf = (id: string): Element | null => {
    const container = document.getElementById(`diff-${id}`)
    if (container) return container
    const header = adapter.resolver.headerById(id)?.el ?? null
    return header?.closest('[data-diff-header-wrapper="true"]')?.parentElement ?? header
  }
  const highlight = (id: string | null) => {
    const el = id ? boxOf(id) : null
    if (el === highlighted) return
    highlighted?.classList.remove(HIGHLIGHT_CLASS)
    highlighted = el
    if (el) { ensureHighlightStyle(); el.classList.add(HIGHLIGHT_CLASS) }
  }

  /** Why there is no cursor, for the app's log: the list failed to read, is empty, or has no element on the page yet. */
  let noCursorReason = ''
  async function currentFile(): Promise<FileCursor | null> {
    let listing: FileListing | null = null
    try { listing = await files() } catch (e) { noCursorReason = `read failed: ${(e as Error)?.name ?? 'error'}`; highlight(null); return null }
    if (listing.files.length === 0) { noCursorReason = 'empty listing'; highlight(null); return null }
    const index = await cursorIndex(listing)
    if (index < 0 && !listing.files.some((f) => elementOf(f.id))) { noCursorReason = `no element for ${listing.files.length} files`; highlight(null); return null }
    const f = listing.files[Math.max(index, 0)]!
    highlight(f.id)
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
  const anchor = (el: Element, anchoredId: string) => {
    stopAnchor?.()
    const until = performance.now() + ANCHOR_MS
    let lastY = window.scrollY
    let lastTop = el.getBoundingClientRect().top
    let frame = 0
    const tick = () => {
      const y = window.scrollY
      const top = el.getBoundingClientRect().top
      if (y === lastY && Math.abs(top - lastTop) > 0.5) {
        window.scrollBy(0, top - lastTop)
        if (intent?.id === anchoredId) intent.scrollY = window.scrollY   // our scroll, not the reader's
      }
      lastY = window.scrollY
      lastTop = el.getBoundingClientRect().top
      if (performance.now() < until) frame = requestAnimationFrame(tick)
      else stopAnchor = null
    }
    frame = requestAnimationFrame(tick)
    stopAnchor = () => { cancelAnimationFrame(frame); stopAnchor = null }
  }

  /**
   * Keeps a file at the top of the content for a while, whoever moves the page: layout shifts, or a scroll
   * of GitHub's own (after a mark it focuses the marked header, which scrolls it back into view). Unlike
   * `anchor`, this corrects every displacement, so it only runs right after a mark, when no reader scrolls.
   */
  const hold = (id: string) => {
    stopAnchor?.()
    const until = performance.now() + HOLD_MS
    let frame = 0
    const tick = () => {
      const el = elementOf(id)
      if (el) {
        const off = el.getBoundingClientRect().top - visibleTop(id)
        if (Math.abs(off) > 0.5) {
          window.scrollBy(0, off)
          intent = { id, scrollY: window.scrollY }
        }
      }
      if (performance.now() < until) frame = requestAnimationFrame(tick)
      else stopAnchor = null
    }
    frame = requestAnimationFrame(tick)
    stopAnchor = () => { cancelAnimationFrame(frame); stopAnchor = null }
  }

  /** Puts a file at the top. Instant: a smooth scroll dies on the first lazy render in WebKit. */
  const jumpTo = (id: string, keep: 'anchor' | 'hold' = 'anchor'): 'element' | 'hash' => {
    const el = elementOf(id)
    if (el) {
      el.scrollIntoView({ block: 'start' })
      // Then under the page's fixed header, where the content really starts (scroll-margin-top may or may not be set).
      const off = el.getBoundingClientRect().top - visibleTop(id)
      if (Math.abs(off) > 0.5) window.scrollBy({ top: off, behavior: 'instant' as ScrollBehavior })
      intent = { id, scrollY: window.scrollY }
      if (keep === 'hold') hold(id); else anchor(el, id)
    } else {
      intent = null
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
    const via = jumpTo(target.id)
    // Positions only, for the app's log (it already prints `top` and `scrollY`): where the target landed.
    const top = elementOf(target.id)?.getBoundingClientRect().top
    return { moved: true, from, to, total: listing.files.length, via, top: top === undefined ? undefined : Math.round(top), scrollY: Math.round(window.scrollY) }
  }

  /** Next or previous file not yet viewed, from where the reader is. */
  async function scrollToUnviewed(direction: 'next' | 'previous', fromIndex?: number, keep: 'anchor' | 'hold' = 'anchor'): Promise<boolean> {
    const listing = await files()
    const from = fromIndex ?? await cursorIndex(listing)
    const target = direction === 'next'
      ? listing.files.find((f, i) => i > from && !f.viewed)
      : [...listing.files].reverse().find((f) => listing.files.indexOf(f) < from && !f.viewed)
    if (!target) return false
    jumpTo(target.id, keep)
    return true
  }

  /**
   * Next (+1) or previous (-1) file among `paths`, in page order from the cursor, wrapping around at the
   * ends. The app passes the files that carry open review threads (from GraphQL), so this is the same on
   * every GitHub UI. `collapsed` tells the app the thread is folded away (a viewed file): the reader
   * decides whether to open it; the page is left as they arranged it.
   */
  async function stepAmong(paths: string[], delta: number): Promise<{ moved: boolean; collapsed: boolean }> {
    const listing = await files()
    const wanted = new Set(paths)
    const indices = listing.files.map((f, i) => i).filter((i) => wanted.has(listing.files[i]!.path))
    if (indices.length === 0) return { moved: false, collapsed: false }
    const from = await cursorIndex(listing)
    const target = delta > 0
      ? indices.find((i) => i > from) ?? indices[0]!
      : [...indices].reverse().find((i) => i < from) ?? indices[indices.length - 1]!
    const id = listing.files[target]!.id
    jumpTo(id)
    const box = boxOf(id)
    return { moved: true, collapsed: box !== null && isCollapsed(box) }
  }

  /** A folded diff: the new UI marks the header, the classic one the chevron. */
  const isCollapsed = (box: Element) => box.querySelector('.diff-file-header.collapsed') !== null || box.querySelector('button.js-details-target[aria-expanded="false"]') !== null

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
      // From the file just handled: marking collapses it, the page reflows, and GitHub scrolls the marked header
      // back into view when it moves focus there. Hold the target at the top through all of that.
      const moved = await scrollToUnviewed('next', cursor?.index, 'hold')
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
    intent = null
    stopAnchor?.()
    highlight(null)
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

  /**
   * A structural picture of the page for the app's capture: counts, selectors and positions, never a
   * path, a title or a URL. Enough to tell which GitHub UI this is and whether the file boxes were found.
   */
  async function inspect(): Promise<Record<string, unknown>> {
    const sel = (el: Element | null): string | null => el
      ? `${el.tagName.toLowerCase()}${el.id ? '#' + el.id.replace(/[0-9a-f]{20,}/g, '…') : ''}${Array.from(el.classList).slice(0, 3).map((c) => '.' + c.replace(/__[A-Za-z0-9]+$/, '')).join('')}`
      : null
    const chain = (el: Element | null, n = 6): string[] => { const out: string[] = []; while (el && n--) { out.push(sel(el)!); el = el.parentElement } return out }
    let listing: FileListing | null = null
    try { listing = await files() } catch { listing = null }
    const cursor = await currentFile()
    const first = listing?.files[0]
    // A structural outline of the current file's box and its ancestors: tags, ids (digests shortened),
    // classes (hash suffixes dropped), data-/role/aria-label attribute names, and the styles that decide
    // clipping and stacking. No text nodes, so nothing of the page's content.
    const outline = (root: Element | null, maxDepth: number, maxLines: number): string[] => {
      const lines: string[] = []
      const walk = (el: Element, depth: number) => {
        if (lines.length >= maxLines || depth > maxDepth) return
        const cs = getComputedStyle(el)
        const flags = [cs.position !== 'static' ? cs.position : '', cs.overflow !== 'visible' ? `overflow:${cs.overflow}` : '', cs.zIndex !== 'auto' ? `z:${cs.zIndex}` : '']
          .filter(Boolean).join(' ')
        const attrs = Array.from(el.attributes).filter((a) => /^(data-|role$|aria-label$)/.test(a.name)).slice(0, 4).map((a) => `[${a.name}]`).join('')
        lines.push(`${'  '.repeat(depth)}${sel(el)}${attrs}${flags ? '  {' + flags + '}' : ''}`)
        for (const child of Array.from(el.children)) walk(child, depth + 1)
      }
      if (root) walk(root, 0)
      return lines
    }
    const box = cursor ? boxOf(cursor.id) : null
    const ancestors = (el: Element | null): string[] => {
      const out: string[] = []
      for (let p = el?.parentElement ?? null; p && out.length < 12; p = p.parentElement) {
        const cs = getComputedStyle(p)
        out.push(`${sel(p)}  {${cs.position} overflow:${cs.overflow} z:${cs.zIndex}}`)
      }
      return out
    }
    return {
      currentBoxOutline: outline(box, 7, 80),
      currentBoxAncestors: ancestors(box),
      path: location.pathname.replace(/^\/[^/]+\/[^/]+/, '/owner/repo').replace(/\/pull\/\d+/, '/pull/N'),
      files: listing?.files.length ?? null,
      viewed: listing?.files.filter((f) => f.viewed).length ?? null,
      cursor: cursor ? { index: cursor.index, total: cursor.total, viewed: cursor.viewed } : noCursorReason,
      containers: document.querySelectorAll('[id^="diff-"]').length,
      headerWrappers: document.querySelectorAll('[data-diff-header-wrapper="true"]').length,
      highlighted: document.querySelector(`.${HIGHLIGHT_CLASS}`) !== null,
      firstBoxChain: chain(first ? boxOf(first.id) : null),
      bodyClasses: Array.from(document.body.classList).slice(0, 10),
      scrollY: Math.round(window.scrollY), innerHeight: window.innerHeight, documentHeight: document.documentElement.scrollHeight,
    }
  }

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
    counts, mark, undo, unmarkAll, scrollToUnviewed: (direction: 'next' | 'previous') => scrollToUnviewed(direction),
    /** The first unviewed file from the top of the page, wherever the reader is: where a review request starts. */
    firstUnviewed: () => scrollToUnviewed('next', -1),
    stepAmong,
    currentFile, stepFile, markCurrentAndNext, setCurrentViewed, inspect,
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
