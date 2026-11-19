import type { ChangedFile, FileListing, PageContext, SetViewedOutcome } from './model'

export class AbortedInFlight extends Error {
  constructor() {
    super('Request aborted in flight')
    this.name = 'AbortedInFlight'
  }
}

export class ContextMismatch extends Error {
  constructor() {
    super('The page changed; this operation belongs to another context')
    this.name = 'ContextMismatch'
  }
}

export interface HostAdapter {
  currentContext(): PageContext | null
  listFiles(): Promise<FileListing>
  setViewed(file: ChangedFile, viewed: boolean, signal?: AbortSignal): Promise<SetViewedOutcome>
  reconcile(ids: string[]): Promise<Map<string, boolean>>
  /**
   * Writes the state on the server itself, whatever the page shows, and throws when the server refuses. For a
   * mark the page showed and the server does not have. Absent where there is no server state (compare pages).
   */
  saveViewed?(file: ChangedFile, viewed: boolean, signal?: AbortSignal): Promise<void>
  loadAll(onProgress?: (done: number, total?: number) => void, signal?: AbortSignal): Promise<void>
  onContextChange(cb: (ctx: PageContext | null) => void): () => void
}
