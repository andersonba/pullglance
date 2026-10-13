import { readEmbeddedRoute, type EmbeddedRoute } from './embedded'

/**
 * Rota "viva" de um PR. O JSON embutido só vale para o PR carregado por reload: numa navegação interna
 * (Conversation → Files, lista de PRs → PR) o GitHub não o reescreve, e ele descreve outra página.
 * Nesse caso o adapter busca a página de arquivos e guarda a rota aqui, por basePath.
 */
const fetched = new Map<string, EmbeddedRoute>()

export function routeFor(doc: Document, basePath: string): EmbeddedRoute | null {
  const embedded = readEmbeddedRoute(doc)
  if (embedded && embedded.basePath === basePath) return embedded
  return fetched.get(basePath) ?? null
}

export function storeFetchedRoute(route: EmbeddedRoute): void {
  fetched.set(route.basePath, route)
}

export function hasFetchedRoute(basePath: string): boolean {
  return fetched.has(basePath)
}

export function clearFetchedRoutes(): void {
  fetched.clear()
}
