import type { PageContext } from '@/core/model'
import { routeFor } from './route-source'

const PULL_FILES = /^(\/[^/]+\/[^/]+\/pull\/\d+)\/(files|changes)(\/|$)/
// O range do compare pode ter pontos, barras e caracteres codificados: `main...feat/x`, `a%2Fb...c`.
const COMPARE = /^(\/[^/]+\/[^/]+\/compare\/[^?#]+?)\/?$/

/** `pull`: aba de arquivos de um PR (UI React). `compare`: página de comparação de refs (UI clássica, sem Viewed). */
export type PageKind = 'pull' | 'compare'

export function pageKindOf(pathname: string): PageKind | null {
  if (PULL_FILES.test(pathname)) return 'pull'
  if (COMPARE.test(pathname)) return 'compare'
  return null
}

export function contextKey(basePath: string, headOid: string, search: string) {
  return `${basePath}|${headOid}|${search}`
}

export function isFilesPagePath(pathname: string): boolean {
  return pageKindOf(pathname) !== null
}

export function basePathOf(pathname: string): string | null {
  return PULL_FILES.exec(pathname)?.[1] ?? COMPARE.exec(pathname)?.[1] ?? null
}

export function readContext(loc: { pathname: string; search: string }, doc: Document): PageContext | null {
  const basePath = basePathOf(loc.pathname)
  if (!basePath) return null
  const route = pageKindOf(loc.pathname) === 'pull' ? routeFor(doc, basePath) : null
  // Sem rota deste PR (JSON ausente, ilegível ou de outra página) ou página de compare: contexto sem headOid.
  if (!route) return { key: contextKey(basePath, '', loc.search), basePath, headOid: '' }
  return { key: contextKey(basePath, route.headOid, loc.search), basePath, headOid: route.headOid }
}
