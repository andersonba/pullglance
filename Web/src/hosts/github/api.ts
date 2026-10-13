import { AbortedInFlight } from '@/core/host'
import { readEmbeddedRoute, type EmbeddedRoute } from './page/embedded'
import { fileReviewRequest, filesPageRequest } from './page/endpoints'

export type FetchLike = (url: string, init?: RequestInit) => Promise<Response>

export class FileReviewError extends Error {
  constructor(public status: number, message = `file_review responded ${status}`) { super(message); this.name = 'FileReviewError' }
}

function isAbort(e: unknown) { return e instanceof DOMException && e.name === 'AbortError' }

export async function postFileReview(basePath: string, path: string, viewed: boolean, fetchImpl: FetchLike, signal?: AbortSignal): Promise<void> {
  const { url, init } = fileReviewRequest(basePath, path, viewed)
  let res: Response
  try {
    res = await fetchImpl(url, { ...init, signal })
  } catch (e) {
    if (isAbort(e) || signal?.aborted) throw new AbortedInFlight()
    throw e
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
