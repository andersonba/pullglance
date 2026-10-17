import type { StrategyRegistry } from '../concepts'
import { fileHeaderAriaLink } from './file-header/aria-link'
import { fileHeaderClassic } from './file-header/classic-header'
import { fileListClassic } from './file-list/classic-files'
import { fileListPageRoute } from './file-list/embedded-json'
import { fileListRenderedHeaders } from './file-list/rendered-headers'
import { fileTreeClassic } from './file-tree/classic-file-tree'
import { fileTreePrimer } from './file-tree/primer-tree-view'
import { toolbarSlotClassicToc } from './toolbar-slot/classic-toc'
import { toolbarSlotFilesToolbar } from './toolbar-slot/files-toolbar'
import { toolbarSlotFloating } from './toolbar-slot/floating'
import { viewedControlAria } from './viewed-control/aria'
import { viewedControlClassicButton } from './viewed-control/classic-viewed-button'
import { viewedControlClassicCheckbox } from './viewed-control/classic-checkbox'
import { viewedControlClassicCollapse } from './viewed-control/classic-collapse'
import { viewedControlCssModule } from './viewed-control/css-module'

export function defaultRegistry(): StrategyRegistry {
  return {
    fileList: [fileListPageRoute, fileListClassic, fileListRenderedHeaders],
    fileHeader: [fileHeaderAriaLink, fileHeaderClassic],
    viewedControl: [viewedControlAria, viewedControlClassicCheckbox, viewedControlClassicButton, viewedControlClassicCollapse, viewedControlCssModule],
    toolbarSlot: [toolbarSlotFilesToolbar, toolbarSlotClassicToc, toolbarSlotFloating],
    fileTree: [fileTreePrimer, fileTreeClassic],
  }
}
