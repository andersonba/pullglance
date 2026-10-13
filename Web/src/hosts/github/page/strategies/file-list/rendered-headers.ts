import type { FileListSource, Strategy } from '../../concepts'
import { fileHeaderAriaLink } from '../file-header/aria-link'
import { viewedControlAria } from '../viewed-control/aria'
import { viewedControlCssModule } from '../viewed-control/css-module'

export const fileListRenderedHeaders: Strategy<FileListSource> = {
  id: 'file-list/rendered-headers',
  priority: 10,
  probe: (doc) => fileHeaderAriaLink.probe(doc),
  create: (doc) => ({
    list: () => {
      const headers = fileHeaderAriaLink.create(doc).all()
      const locators = [viewedControlAria, viewedControlCssModule].filter((s) => s.probe(doc)).map((s) => s.create(doc))
      const files = headers.map((h) => {
        const control = locators.map((l) => l.inHeader(h.el)).find((c) => c !== null) ?? null
        return { id: h.id, path: h.path, viewed: control?.isViewed() ?? false }
      })
      return { files, completeness: 'partial' as const }
    },
  }),
}
