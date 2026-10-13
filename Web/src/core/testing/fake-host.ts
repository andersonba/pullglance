import { AbortedInFlight, type HostAdapter } from '../host'
import type { ChangedFile, Completeness, FileListing, PageContext, SetViewedOutcome } from '../model'

export class FakeHostAdapter implements HostAdapter {
  server = new Map<string, boolean>()
  calls: Array<{ id: string; viewed: boolean }> = []
  failIds = new Set<string>()
  hangIds = new Set<string>()
  optimisticLiars = new Set<string>()
  private files: ChangedFile[]
  private context: PageContext | null
  private completeness: Completeness
  private pending: Array<() => void> = []
  private listeners = new Set<(ctx: PageContext | null) => void>()

  constructor(init: { context: PageContext; files: ChangedFile[]; completeness?: Completeness }) {
    this.context = init.context
    this.files = init.files.map((f) => ({ ...f }))
    this.completeness = init.completeness ?? 'full'
    for (const f of this.files) this.server.set(f.id, f.viewed)
  }

  currentContext() {
    return this.context
  }

  async listFiles(): Promise<FileListing> {
    if (!this.context) throw new Error('sem contexto')
    return { context: this.context, completeness: this.completeness, files: this.files.map((f) => ({ ...f })) }
  }

  async setViewed(file: ChangedFile, viewed: boolean, signal?: AbortSignal): Promise<SetViewedOutcome> {
    if (this.hangIds.has(file.id)) {
      await new Promise<void>((resolve, reject) => {
        this.pending.push(resolve)
        signal?.addEventListener('abort', () => reject(new AbortedInFlight()), { once: true })
      })
    }
    if (signal?.aborted) throw new AbortedInFlight()
    if (this.failIds.has(file.id)) throw new Error(`falha simulada em ${file.id}`)
    const current = this.files.find((f) => f.id === file.id)!
    if (current.viewed === viewed) return 'noop'
    this.calls.push({ id: file.id, viewed })
    current.viewed = viewed
    if (!this.optimisticLiars.has(file.id)) this.server.set(file.id, viewed)
    return current.hasControl ? 'dom' : 'api'
  }

  async reconcile(ids: string[]) {
    return new Map(ids.map((id) => [id, this.server.get(id) ?? false]))
  }

  async loadAll(onProgress?: (done: number, total?: number) => void) {
    const pending = this.files.filter((f) => !f.hasControl)
    pending.forEach((f, i) => {
      f.hasControl = true
      onProgress?.(i + 1, pending.length)
    })
  }

  onContextChange(cb: (ctx: PageContext | null) => void) {
    this.listeners.add(cb)
    return () => {
      this.listeners.delete(cb)
    }
  }

  release() {
    this.pending.splice(0).forEach((r) => r())
  }

  changeContext(ctx: PageContext | null) {
    this.context = ctx
    this.listeners.forEach((cb) => cb(ctx))
  }

  /** usado pelos testes para simular clique do usuário no GitHub */
  userToggles(id: string) {
    const f = this.files.find((x) => x.id === id)!
    f.viewed = !f.viewed
    this.server.set(id, f.viewed)
  }
}
