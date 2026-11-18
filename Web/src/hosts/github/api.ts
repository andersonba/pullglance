import { AbortedInFlight } from '@/core/host'
import { readEmbeddedRoute, type EmbeddedRoute } from './page/embedded'
import { fileReviewRequest, filesPageRequest } from './page/endpoints'

export type FetchLike = (url: string, init?: RequestInit) => Promise<Response>

export class FileReviewError extends Error {
  constructor(public status: number, message = `file_review responded ${status}`) { super(message); this.name = 'FileReviewError' }
}

function isAbort(e: unknown) { return e instanceof DOMException && e.name === 'AbortError' }

/** How long a 429 asks to wait, in milliseconds: its `Retry-After` in seconds when it has one, within reason. */
export function retryAfterMs(res: Response, fallbackMs = 5000, capMs = 30_000): number {
  const seconds = Number(res.headers.get('Retry-After'))
  return Number.isFinite(seconds) && seconds >= 0 && res.headers.get('Retry-After') !== null ? Math.min(seconds * 1000, capMs) : fallbackMs
}

const pause = (ms: number, signal?: AbortSignal) => new Promise<void>((resolve) => {
  const timer = setTimeout(resolve, ms)
  signal?.addEventListener('abort', () => { clearTimeout(timer); resolve() }, { once: true })
})

/**
 * GitHub answers 429 when marks come too fast: a few hundred files in a row get there (seen live 2026-11-18,
 * after some 600 requests in two minutes). The request is fine and so is the session; it waits what the
 * answer asks and goes again, a few times, instead of failing the file and stopping the batch.
 */
export async function postFileReview(basePath: string, path: string, viewed: boolean, fetchImpl: FetchLike, signal?: AbortSignal, retries = 3): Promise<void> {
  const { url, init } = fileReviewRequest(basePath, path, viewed)
  let res: Response
  for (let attempt = 0; ; attempt++) {
    try {
      res = await fetchImpl(url, { ...init, signal })
    } catch (e) {
      if (isAbort(e) || signal?.aborted) throw new AbortedInFlight()
      throw e
    }
    if (res.status !== 429 || attempt >= retries) break
    await pause(retryAfterMs(res), signal)
    if (signal?.aborted) throw new AbortedInFlight()
  }
  if (res.ok) return
  let detail = ''
  try { detail = (await res.json())?.error ?? '' } catch { /* corpo não JSON */ }
  throw new FileReviewError(res.status, detail ? `file_review responded ${res.status}: ${detail}` : undefined)
}

/** Baixa a página de arquivos do PR e lê a rota embutida nela (lista completa, estado viewed, oids). */
export async function fetchServerRoute(basePath: string, fetchImpl: FetchLike): Promise<EmbeddedRoute> {
  const { url, init } = filesPageRequest(basePath)
  const res = await fetchImpl(url, init)
  if (!res.ok) throw new Error(`GET ${url} responded ${res.status}`)
  const doc = new DOMParser().parseFromString(await res.text(), 'text/html')
  const route = readEmbeddedRoute(doc)
  if (!route) throw new Error('files page without embedded JSON')
  return route
}

export async function fetchServerViewedState(basePath: string, fetchImpl: FetchLike): Promise<Map<string, boolean>> {
  const route = await fetchServerRoute(basePath, fetchImpl)
  return new Map(route.summaries.map((s) => [s.pathDigest, s.markedAsViewed]))
}
