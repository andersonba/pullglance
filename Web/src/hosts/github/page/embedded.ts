export interface EmbeddedSummary {
  path: string
  pathDigest: string
  markedAsViewed: boolean
}

export interface EmbeddedRoute {
  basePath: string
  headOid: string
  baseOid: string
  summaries: EmbeddedSummary[]
  renderedDigests: Set<string>
  filesLimitExceeded: boolean
}

export const EMBEDDED_SELECTOR = 'script[type="application/json"][data-target="react-app.embeddedData"]'

// Cache de 1 entrada: o observer de contexto relê a rota a cada mutação do DOM; o JSON pode ter MBs.
// Chave = identidade do nó <script> + tamanho do texto (o GitHub troca o nó ao navegar).
let cache: { script: Element; length: number; route: EmbeddedRoute | null } | null = null

export function clearEmbeddedCache(): void {
  cache = null
}

export function readEmbeddedRoute(doc: Document): EmbeddedRoute | null {
  const script = doc.querySelector(EMBEDDED_SELECTOR)
  const text = script?.textContent
  if (!script || !text) return null
  if (cache && cache.script === script && cache.length === text.length) return cache.route
  const route = parseRoute(text)
  cache = { script, length: text.length, route }
  return route
}

function parseRoute(text: string): EmbeddedRoute | null {
  let route: any
  try {
    route = JSON.parse(text)?.payload?.pullRequestsChangesRoute
  } catch {
    return null
  }
  if (!route || !Array.isArray(route.diffSummaries)) return null
  const pr = route.pullRequest ?? {}
  const basePath: unknown = pr.pathName
  const range = route.comparison?.selectedRange
  const comparison = typeof range?.headOid === 'string' ? range : pr.comparison ?? {}
  if (typeof basePath !== 'string' || typeof comparison.headOid !== 'string') return null
  const summaries: EmbeddedSummary[] = []
  for (const d of route.diffSummaries) {
    if (typeof d?.path !== 'string' || typeof d?.pathDigest !== 'string') continue
    summaries.push({ path: d.path, pathDigest: d.pathDigest, markedAsViewed: d.markedAsViewed === true })
  }
  const renderedDigests = new Set<string>(
    Array.isArray(route.diffContents) ? route.diffContents.map((c: any) => c?.pathDigest).filter((x: unknown): x is string => typeof x === 'string') : [],
  )
  return {
    basePath,
    headOid: comparison.headOid,
    baseOid: typeof comparison.baseOid === 'string' ? comparison.baseOid : '',
    summaries,
    renderedDigests,
    filesLimitExceeded: route.pageLimits?.filesLimitExceeded === true,
  }
}
