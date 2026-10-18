import type { PageReadiness, Strategy } from '../../concepts'

/** Pages without a client framework in the way (the classic UI, compare): ready when the document has loaded. */
export const pageReadyDocument: Strategy<PageReadiness> = {
  id: 'page-ready/document',
  priority: 0,
  probe: () => true,
  create: (doc) => ({ isReady: () => doc.readyState === 'complete' }),
}
