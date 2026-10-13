import type { Strategy, ToolbarSlotSource } from '../../concepts'

const SLOT = '[class*="PullRequestFilesToolbar-module__file-controls"]'

export const toolbarSlotFilesToolbar: Strategy<ToolbarSlotSource> = {
  id: 'toolbar-slot/files-toolbar',
  priority: 30,
  probe: (doc) => doc.querySelector(SLOT) !== null,
  create: (doc) => ({ find: () => doc.querySelector(SLOT) }),
}
