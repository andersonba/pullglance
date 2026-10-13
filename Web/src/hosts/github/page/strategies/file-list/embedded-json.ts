import type { FileListSource, Strategy } from '../../concepts'
import { basePathOf } from '../../location'
import { routeFor } from '../../route-source'

/** Lista completa a partir da rota do PR: JSON embutido quando é deste PR, senão a cópia buscada da página. */
export const fileListPageRoute: Strategy<FileListSource> = {
  id: 'file-list/page-route',
  priority: 30,
  probe: (doc) => currentRoute(doc) !== null,
  create: (doc) => ({
    list: () => {
      const route = currentRoute(doc)
      if (!route) return { files: [], completeness: 'partial' }
      return {
        files: route.summaries.map((s) => ({ id: s.pathDigest, path: s.path, viewed: s.markedAsViewed })),
        completeness: route.filesLimitExceeded ? 'partial' : 'full',
      }
    },
  }),
}

function currentRoute(doc: Document) {
  const basePath = basePathOf(doc.location?.pathname ?? '')
  return basePath ? routeFor(doc, basePath) : null
}
