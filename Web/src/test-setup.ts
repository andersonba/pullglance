import { storage } from '#imports'
import { clearEmbeddedCache } from '@/hosts/github/page/embedded'
import { clearFetchedRoutes } from '@/hosts/github/page/route-source'

beforeEach(() => {
  storage._resetForTests()
  clearEmbeddedCache()
  clearFetchedRoutes()
})
