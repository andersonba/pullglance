import { AbortedInFlight, type HostAdapter } from '@/core/host'
import type { ChangedFile, FileListing, PageContext, SetViewedOutcome } from '@/core/model'
import { fetchServerRoute, postFileReview, type FetchLike } from './api'
import type { StrategyRegistry } from './page/concepts'
import type { Diagnostics } from './page/diagnostics'
import { basePathOf, isFilesPagePath, pageKindOf, readContext, type PageKind } from './page/location'
import { hasFetchedRoute, routeFor, storeFetchedRoute } from './page/route-source'
import { PageResolver } from './page/resolver'
import { defaultRegistry } from './page/strategies'
import { ViewedOverlay } from './state'
import { CompareMemory } from './compare-memory'

const CONTEXT_DEBOUNCE_MS = 150
const TURBO_EVENTS = ['turbo:load', 'turbo:render'] as const

export interface GitHubAdapterDeps {
  doc?: Document; win?: Window; fetchImpl?: FetchLike; overlay?: ViewedOverlay
  registry?: StrategyRegistry; domTimeoutMs?: number; loadTimeoutMs?: number
  /** memória de "visto" por compare; null desliga */
  compareMemory?: CompareMemory | null
  /** tamanho do lote de restauração por quadro */
  restoreBatch?: number
}
export interface GitHubAdapterConfig { rememberCompare: boolean }
export interface ToolbarSlot { el: Element; placement: 'first' | 'last' | 'after'; hostFlag?: string }
export interface GitHubAdapter extends HostAdapter { resolver: PageResolver; isFilesPage(): boolean; pageKind(): PageKind | null; diagnostics(): Diagnostics; toolbarSlot(): ToolbarSlot | null; configure(c: Partial<GitHubAdapterConfig>): void; flushMemory(): Promise<void> }

export function createGitHubAdapter(deps: GitHubAdapterDeps = {}): GitHubAdapter {
  const doc = deps.doc ?? document
  const win = deps.win ?? window
  const fetchImpl: FetchLike = deps.fetchImpl ?? ((u, i) => win.fetch(u, i))
  const overlay = deps.overlay ?? new ViewedOverlay()
  const resolver = new PageResolver(doc, deps.registry ?? defaultRegistry())
  const domTimeoutMs = deps.domTimeoutMs ?? 3000
  const loadTimeoutMs = deps.loadTimeoutMs ?? 5000
  const memory = deps.compareMemory === undefined ? new CompareMemory() : deps.compareMemory
  const restoreBatch = deps.restoreBatch ?? 25
  const config: GitHubAdapterConfig = { rememberCompare: true }

  const currentContext = () => readContext(win.location, doc)
  const requireContext = (): PageContext => {
    const ctx = currentContext()
    if (!ctx) throw new Error('Not on a pull request files page')
    return ctx
  }

  // Avisa os observadores de contexto (onContextChange) que algo mudou fora do DOM, ex.: rota buscada chegou.
  const pokes = new Set<() => void>()
  const inFlight = new Set<string>()
  const failedUntil = new Map<string, number>()   // basePath -> timestamp até o qual não se tenta de novo
  const ROUTE_RETRY_MS = 60_000
  /** Navegação interna: o JSON embutido é de outra página. Busca a rota deste PR uma vez e reavalia o contexto. */
  function ensureRoute(): void {
    if (pageKindOf(win.location.pathname) !== 'pull') return   // compare não tem rota de PR nem página /files
    const basePath = basePathOf(win.location.pathname)
    if (!basePath || routeFor(doc, basePath) || inFlight.has(basePath)) return
    if ((failedUntil.get(basePath) ?? 0) > Date.now()) return   // falhou há pouco: não martelar o GitHub a cada leitura
    inFlight.add(basePath)
    fetchServerRoute(basePath, fetchImpl)
      .then((route) => {
        storeFetchedRoute(route)
        resolver.invalidateConcept('fileList')
        pokes.forEach((poke) => poke())
      })
      .catch(() => { failedUntil.set(basePath, Date.now() + ROUTE_RETRY_MS) })   // fallback por cabeçalhos; nova tentativa só depois
      .finally(() => inFlight.delete(basePath))
  }

  const controlFor = (id: string) => {
    const header = resolver.headerById(id)
    return header ? resolver.viewedControl(header.el) : null
  }

  // Compare: restaura do storage os arquivos lembrados como vistos (colapsa), uma vez por contexto e também
  // para arquivos que chegarem depois (carregamento progressivo); depois disso o DOM é a verdade e é espelhado.
  let restoredFor: string | null = null
  let remembered: Set<string> | null = null
  let pruned = false
  const memoryActive = () => memory !== null && config.rememberCompare && pageKindOf(win.location.pathname) === 'compare'
  async function restoreRemembered(ctx: PageContext, files: Array<{ id: string }>): Promise<void> {
    if (!memory) return
    if (restoredFor !== ctx.key) { restoredFor = ctx.key; remembered = await memory.load(ctx.basePath) }
    if (!pruned) { pruned = true; void memory.prune() }
    if (!remembered || remembered.size === 0) return
    const todo = files.filter((f) => remembered!.has(f.id)).map((f) => controlFor(f.id)).filter((c): c is NonNullable<typeof c> => c !== null && !c.isViewed())
    for (let i = 0; i < todo.length; i += restoreBatch) {
      for (const control of todo.slice(i, i + restoreBatch)) control.toggle()
      if (i + restoreBatch < todo.length) await nextFrame(win)
    }
    // Só o que foi restaurado agora deixa de ser pendente; o que não tem controle ainda pode chegar depois.
    for (const f of files) if (controlFor(f.id)) remembered.delete(f.id)
  }

  async function listFiles(): Promise<FileListing> {
    ensureRoute()
    const { files, completeness } = resolver.fileList().list()   // lança UnsupportedPage antes de exigir contexto
    const ctx = requireContext()
    if (memoryActive()) await restoreRemembered(ctx, files)
    const changed: ChangedFile[] = files.map((f) => {
      const control = controlFor(f.id)
      // O overlay guarda o último estado visto no DOM: se o cabeçalho for desmontado (virtualização),
      // uma marcação manual do usuário não volta ao valor antigo do JSON do load.
      if (control) overlay.set(ctx.key, f.id, control.isViewed())
      const viewed = control ? control.isViewed() : overlay.get(ctx.key, f.id) ?? f.viewed
      return { id: f.id, path: f.path, viewed, hasControl: control !== null }
    })
    if (memoryActive() && memory) memory.remember(ctx.basePath, new Set(changed.filter((f) => f.viewed).map((f) => f.id)), new Set(changed.map((f) => f.id)))
    return { context: ctx, files: changed, completeness }
  }

  async function setViewed(file: ChangedFile, viewed: boolean, signal?: AbortSignal): Promise<SetViewedOutcome> {
    const ctx = requireContext()
    const control = controlFor(file.id)
    if (control) {
      if (control.isViewed() === viewed) return 'noop'
      control.toggle()
      try {
        await waitFor(() => control.isViewed() === viewed, domTimeoutMs, signal, `GitHub didn't confirm marking ${file.path}`)
      } catch (e) {
        if (e instanceof WaitAborted) throw new AbortedInFlight()   // o clique já saiu; o estado final é desconhecido
        throw e
      }
      overlay.set(ctx.key, file.id, viewed)
      return 'dom'
    }
    if ((overlay.get(ctx.key, file.id) ?? file.viewed) === viewed) return 'noop'
    if (pageKindOf(win.location.pathname) !== 'pull') throw new Error(`${file.path} is not loaded on this page`)   // compare: só via DOM
    await postFileReview(ctx.basePath, file.path, viewed, fetchImpl, signal)
    overlay.set(ctx.key, file.id, viewed)
    return 'api'
  }

  async function reconcile(ids: string[]): Promise<Map<string, boolean>> {
    const ctx = requireContext()
    if (pageKindOf(win.location.pathname) !== 'pull') {
      // Compare não tem estado no servidor: a verdade é o DOM (arquivo colapsado ou não).
      return new Map(ids.map((id) => [id, controlFor(id)?.isViewed() ?? overlay.get(ctx.key, id) ?? false]))
    }
    const route = await fetchServerRoute(ctx.basePath, fetchImpl)
    if (hasFetchedRoute(ctx.basePath) || !routeFor(doc, ctx.basePath)) storeFetchedRoute(route)   // mantém a cópia buscada fresca
    const server = new Map(route.summaries.map((s) => [s.pathDigest, s.markedAsViewed]))
    const out = new Map<string, boolean>()
    for (const id of ids) { const v = server.get(id) ?? false; out.set(id, v); overlay.set(ctx.key, id, v) }
    return out
  }

  async function loadAll(onProgress?: (done: number, total?: number) => void, signal?: AbortSignal): Promise<void> {
    // Carregamento progressivo (UI clássica): o GitHub busca a próxima página quando o fragmento pendente entra
    // na viewport. Rola até ele e espera ser substituído; repete até não sobrar nenhum. Total desconhecido.
    const source = resolver.fileList()
    for (let fragment = source.pendingLoader?.() ?? null; fragment; fragment = source.pendingLoader?.() ?? null) {
      if (signal?.aborted) return
      ;(fragment as HTMLElement).scrollIntoView?.({ block: 'end' })
      const replaced = await waitFor(() => !fragment!.isConnected, loadTimeoutMs, signal).then(() => true, () => false)
      onProgress?.(resolver.headers().length)
      if (!replaced) return   // GitHub não respondeu a tempo: para em vez de girar
    }
    const pending = resolver.headers().filter((h) => resolver.viewedControl(h.el) === null)
    let done = 0
    for (const h of pending) {
      if (signal?.aborted) return
      ;(h.el as HTMLElement).scrollIntoView?.({ block: 'center' })
      await waitFor(() => resolver.viewedControl(h.el) !== null, loadTimeoutMs, signal).catch(() => undefined)
      onProgress?.(++done, pending.length)
    }
  }

  function onContextChange(cb: (ctx: PageContext | null) => void): () => void {
    let lastKey = currentContext()?.key ?? null
    const check = () => {
      const ctx = currentContext()
      const key = ctx?.key ?? null
      if (key === lastKey) return
      lastKey = key
      resolver.invalidate()
      if (ctx) overlay.clearExcept(ctx.key)
      cb(ctx)
    }
    // Debounce: a página do GitHub muta o DOM o tempo todo; a checagem só roda após 150 ms de calma.
    // Sem characterData: trocas de JSON chegam como substituição de nó (childList) ou por eventos do Turbo.
    let timer: ReturnType<typeof setTimeout> | null = null
    const scheduled = () => { if (timer) clearTimeout(timer); timer = setTimeout(() => { timer = null; check() }, CONTEXT_DEBOUNCE_MS) }
    const observer = new MutationObserver(scheduled)
    observer.observe(doc.documentElement, { childList: true, subtree: true })
    win.addEventListener('popstate', scheduled)
    for (const ev of TURBO_EVENTS) doc.addEventListener(ev, scheduled)
    pokes.add(scheduled)
    return () => {
      if (timer) clearTimeout(timer)
      timer = null
      pokes.delete(scheduled)
      observer.disconnect()
      win.removeEventListener('popstate', scheduled)
      for (const ev of TURBO_EVENTS) doc.removeEventListener(ev, scheduled)
    }
  }

  return {
    resolver,
    isFilesPage: () => isFilesPagePath(win.location.pathname),
    pageKind: () => pageKindOf(win.location.pathname),
    currentContext,
    listFiles,
    setViewed,
    reconcile,
    loadAll,
    onContextChange,
    diagnostics: () => resolver.diagnostics(),
    configure: (c) => { Object.assign(config, c) },
    flushMemory: () => memory?.flush() ?? Promise.resolve(),
    toolbarSlot: () => {
      resolver.invalidateConcept('toolbarSlot')   // cada montagem re-proba: a toolbar do GitHub pode ter (re)aparecido
      try {
        const source = resolver.toolbarSlot()
        const el = source.find()
        return el ? { el, placement: source.placement ?? 'last', hostFlag: source.hostFlag } : null
      } catch { return null }
    },
  }
}

class WaitAborted extends Error {
  constructor() {
    super('Espera abortada')
    this.name = 'WaitAborted'
  }
}

function waitFor(pred: () => boolean, timeoutMs: number, signal?: AbortSignal, message = 'timed out'): Promise<void> {
  return new Promise((resolve, reject) => {
    if (pred()) return resolve()
    const started = Date.now()
    const tick = () => {
      if (pred()) return resolve()
      if (signal?.aborted) return reject(new WaitAborted())
      if (Date.now() - started >= timeoutMs) return reject(new Error(message))
      setTimeout(tick, 16)
    }
    setTimeout(tick, 0)
  })
}

function nextFrame(win: Window): Promise<void> {
  return new Promise((resolve) => (win.requestAnimationFrame ? win.requestAnimationFrame(() => resolve()) : setTimeout(resolve, 0)))
}
