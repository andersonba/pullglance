import type { FileListSource, Strategy } from '../../concepts'
import { fileHeaderClassic } from '../file-header/classic-header'
import { viewedControlClassicButton } from '../viewed-control/classic-viewed-button'
import { viewedControlClassicCollapse } from '../viewed-control/classic-collapse'

/** Lista da UI clássica: um `.file-header` por arquivo já na página; visto = botão Viewed injetado (chevron só como fallback). */
const PENDING = '.js-diff-progressive-container include-fragment, include-fragment[src*="/compare/file-list"]'

export const fileListClassic: Strategy<FileListSource> = {
  id: 'file-list/classic-files',
  priority: 20,
  probe: (doc) => fileHeaderClassic.probe(doc),
  create: (doc) => ({
    list: () => {
      const headers = fileHeaderClassic.create(doc).all()
      const button = viewedControlClassicButton.create(doc)
      const chevron = viewedControlClassicCollapse.create(doc)
      const files = headers.map((h) => ({ id: h.id, path: h.path, viewed: (button.inHeader(h.el) ?? chevron.inHeader(h.el))?.isViewed() ?? false }))
      return { files, completeness: doc.querySelector(PENDING) ? 'partial' as const : 'full' as const }
    },
    pendingLoader: () => doc.querySelector(PENDING),
  }),
}
