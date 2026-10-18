import { pageReadyReactHydration } from './page-ready/react-hydration'
import { pageReadyDocument } from './page-ready/document'
import { mountFilesPage } from '@@/tests/fixtures/github/build'
import { mountComparePage } from '@@/tests/fixtures/github/compare'

const root = () => document.querySelector('[data-target="react-app.reactRoot"]') as any
const buttons = () => Array.from(document.querySelectorAll('button[aria-pressed]')) as any[]

describe('page-ready/react-hydration (new Files UI)', () => {
  it('probes a React page only', () => {
    mountFilesPage({ files: [{ path: 'a.ts' }] })
    expect(pageReadyReactHydration.probe(document)).toBe(true)
    mountComparePage({ files: [{ path: 'a.ts' }] })
    expect(pageReadyReactHydration.probe(document)).toBe(false)
  })

  it('is ready once GitHub\'s app has mounted: the `loaded` class on <react-app>', () => {
    mountFilesPage({ files: [{ path: 'a.ts' }, { path: 'b.ts' }], hydrated: false })
    const ready = pageReadyReactHydration.create(document)
    expect(ready.isReady()).toBe(false)              // the server's page
    document.querySelector('react-app')!.classList.add('loaded')
    expect(ready.isReady()).toBe(true)
    expect(root()).not.toBeNull(); expect(buttons().length).toBe(2)
  })
})

describe('page-ready/document (classic pages)', () => {
  it('is the fallback and follows readyState', () => {
    mountComparePage({ files: [{ path: 'a.ts' }] })
    expect(pageReadyDocument.probe(document)).toBe(true)
    expect(pageReadyDocument.priority).toBeLessThan(pageReadyReactHydration.priority)
    expect(pageReadyDocument.create(document).isReady()).toBe(document.readyState === 'complete')
  })
})
