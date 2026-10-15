import type { FileListSource, Strategy } from '../../concepts'
import { fileHeaderClassic } from '../file-header/classic-header'
import { viewedControlClassicButton } from '../viewed-control/classic-viewed-button'
import { viewedControlClassicCheckbox } from '../viewed-control/classic-checkbox'
import { viewedControlClassicCollapse } from '../viewed-control/classic-collapse'

/**
 * Lista da UI clássica: um `.file-header` por arquivo já na página. Visto = o checkbox nativo do GitHub
 * (aba de arquivos do PR); sem ele, o botão Viewed injetado (compare); o chevron só como fallback.
 */
const PENDING = '.js-diff-progressive-container include-fragment, include-fragment[src*="/compare/file-list"]'

export const fileListClassic: Strategy<FileListSource> = {
  id: 'file-list/classic-files',
  priority: 20,
  probe: (doc) => fileHeaderClassic.probe(doc),
  create: (doc) => ({
    list: () => {
      const headers = fileHeaderClassic.create(doc).all()
      const native = viewedControlClassicCheckbox.create(doc)
      // Só cria o botão onde o GitHub não oferece Viewed: criar é injetar no DOM.
      const button = viewedControlClassicButton.probe(doc) ? viewedControlClassicButton.create(doc) : null
      const chevron = viewedControlClassicCollapse.create(doc)
      const files = headers.map((h) => ({ id: h.id, path: h.path, viewed: (native.inHeader(h.el) ?? button?.inHeader(h.el) ?? chevron.inHeader(h.el))?.isViewed() ?? false }))
      return { files, completeness: doc.querySelector(PENDING) ? 'partial' as const : 'full' as const }
    },
    pendingLoader: () => doc.querySelector(PENDING),
  }),
}
