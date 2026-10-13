import { markMatching, undo as undoAction, loadAll } from '@/core/actions'
import { matchFiles } from '@/core/matcher'
import type { Receipt, Rule } from '@/core/model'
import { OperationLock } from '@/core/lock'
import { DEFAULT_SETTINGS, normalize, rulesFromSettings, type Settings } from '@/features/tests/settings'
import { createGitHubAdapter, type GitHubAdapter } from '@/hosts/github/adapter'

export interface Context { kind: 'pull' | 'compare' | 'other'; basePath: string; key: string | null }
export interface Counts { total: number; viewed: number; matching: number; partial: boolean; perRule: Record<string, number> }
export interface MarkResult { marked: number; failed: number; skipped: number; unknown: number; canUndo: boolean }
export interface Deps { post(event: { name: string; payload: unknown }): void; adapter?: GitHubAdapter }

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
      return { marked: receipt.marked.length, failed: receipt.failed.length, skipped: receipt.skipped.length, unknown: receipt.unknown.length, canUndo: lastReceipt !== null }
    })
  }

  async function undo(): Promise<{ marked: number; failed: number }> {
    if (!lastReceipt) throw new Error('nothing to undo')
    return lock.run(async (signal) => {
      const r = await undoAction(adapter, lastReceipt!, { signal })
      lastReceipt = null
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
      return { marked, failed }
    })
  }

  async function scrollToUnviewed(direction: 'next' | 'previous'): Promise<boolean> {
    const listing = await adapter.listFiles()
    // The header comes from the adapter: the PR Files UI has no #diff-<id> element, only `h3 a[href="#diff-<id>"]`.
    const nodes = listing.files.filter((f) => !f.viewed).map((f) => adapter.resolver.headerById(f.id)?.el).filter((n): n is Element => n != null)
    const top = (n: Element) => n.getBoundingClientRect().top
    const target = direction === 'next' ? nodes.find((n) => top(n) > 80) : [...nodes].reverse().find((n) => top(n) < -8)
    if (!target) return false
    target.scrollIntoView({ block: 'start', behavior: 'smooth' })
    return true
  }

  // Nothing reads the file list (which restores and writes compare memory) before the app's settings arrive:
  // the listing watcher starts on the first setSettings.
  let listingWatch: ListingWatch | null = null

  adapter.onContextChange((ctx) => {
    if (ctx === null || ctx.key !== lastReceipt?.context.key) lastReceipt = null
    lock.cancel()
    deps.post({ name: 'context', payload: context() })
    listingWatch?.reset()
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
      listingWatch ??= watchListing(adapter, (payload) => deps.post({ name: 'listing', payload }))
    },
    counts, mark, undo, unmarkAll, scrollToUnviewed,
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
function watchListing(adapter: GitHubAdapter, post: (listing: typeof EMPTY_LISTING) => void): ListingWatch {
  let last = ''          // dedupe key of the last post; reset() clears it
  let showing = false    // the app is showing a non-empty listing from this page
  let timer: ReturnType<typeof setTimeout> | null = null
  const emit = (payload: typeof EMPTY_LISTING) => {
    const key = JSON.stringify(payload)
    if (key === last) return
    last = key
    showing = payload.total > 0
    post(payload)
  }
  const check = async () => {
    const listing = await adapter.listFiles().catch(() => null)
    if (!listing) { if (showing) emit(EMPTY_LISTING); return }
    emit({ total: listing.files.length, viewed: listing.files.filter((f) => f.viewed).length, partial: listing.completeness === 'partial' })
  }
  const schedule = () => { if (timer) clearTimeout(timer); timer = setTimeout(() => { timer = null; void check() }, LISTING_DEBOUNCE_MS) }
  // Viewed state lives in classes and ARIA attributes (classic collapse, aria-pressed buttons), not only in child lists.
  new MutationObserver(schedule).observe(document.documentElement, {
    childList: true, subtree: true, attributes: true, attributeFilter: ['class', 'aria-pressed', 'aria-expanded'],
  })
  void check()
  return { reset: () => { last = ''; schedule() } }
}

// Installed by the app's WKUserScript in the isolated world; tests call install() directly.
if (typeof window !== 'undefined' && (window as any).webkit?.messageHandlers?.reviewEvent) {
  const post = (e: { name: string; payload: unknown }) => (window as any).webkit.messageHandlers.reviewEvent.postMessage(e)
  ;(window as any).__pullglanceReview = install({ post })
  window.addEventListener('pagehide', () => { void (window as any).__pullglanceReview.flush() })
}
