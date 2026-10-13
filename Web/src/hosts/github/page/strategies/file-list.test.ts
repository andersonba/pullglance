import { fileListPageRoute } from './file-list/embedded-json'
import { storeFetchedRoute } from '../route-source'
import { readEmbeddedRoute } from '../embedded'
import { fileListRenderedHeaders } from './file-list/rendered-headers'
import { PageResolver } from '../resolver'
import { defaultRegistry } from './index'
import { buildFilesPageHtml, digestOf, mountFilesPage, replaceEmbeddedJson } from '@@/tests/fixtures/github/build'

describe('file-list/page-route', () => {
  it('lista todos os arquivos com estado, full', () => {
    mountFilesPage({ files: [{ path: 'a.ts', viewed: true }, { path: 'b.ts', rendered: false }] })
    expect(fileListPageRoute.probe(document)).toBe(true)
    const { files, completeness } = fileListPageRoute.create(document).list()
    expect(files).toEqual([{ id: digestOf('a.ts'), path: 'a.ts', viewed: true }, { id: digestOf('b.ts'), path: 'b.ts', viewed: false }])
    expect(completeness).toBe('full')
  })

  it('probe falso sem JSON ou com JSON quebrado', () => {
    mountFilesPage({ files: [{ path: 'a.ts' }], variant: 'no-embedded' })
    expect(fileListPageRoute.probe(document)).toBe(false)
    mountFilesPage({ files: [{ path: 'a.ts' }], variant: 'broken-json' })
    expect(fileListPageRoute.probe(document)).toBe(false)
  })

  it('partial quando filesLimitExceeded', () => {
    mountFilesPage({ files: [{ path: 'a.ts' }] })
    replaceEmbeddedJson((j) => { j.payload.pullRequestsChangesRoute.pageLimits.filesLimitExceeded = true })
    expect(fileListPageRoute.create(document).list().completeness).toBe('partial')
  })
})

describe('file-list/page-route com JSON de outra página (navegação interna)', () => {
  it('probe falso enquanto só há o JSON de outro PR; verdadeiro após a rota buscada chegar', () => {
    mountFilesPage({ files: [{ path: 'old.ts' }], basePath: '/acme/web/pull/41' })
    ;(window as any).happyDOM.setURL('https://github.com/acme/web/pull/42/files')   // URL já é do PR 42, JSON ainda do 41
    expect(fileListPageRoute.probe(document)).toBe(false)
    const fetchedDoc = new DOMParser().parseFromString(buildFilesPageHtml({ files: [{ path: 'new.test.ts' }, { path: 'x.ts', viewed: true }], basePath: '/acme/web/pull/42' }), 'text/html')
    storeFetchedRoute(readEmbeddedRoute(fetchedDoc)!)
    expect(fileListPageRoute.probe(document)).toBe(true)
    const { files, completeness } = fileListPageRoute.create(document).list()
    expect(files.map((f) => [f.path, f.viewed])).toEqual([['new.test.ts', false], ['x.ts', true]])
    expect(completeness).toBe('full')
  })
})

describe('file-list/rendered-headers', () => {
  it('lista só renderizados, lendo estado do controle, partial', () => {
    mountFilesPage({ files: [{ path: 'a.ts', viewed: true }, { path: 'b.ts' }, { path: 'c.ts', rendered: false }], variant: 'no-embedded' })
    expect(fileListRenderedHeaders.probe(document)).toBe(true)
    const { files, completeness } = fileListRenderedHeaders.create(document).list()
    expect(files.map((f) => [f.path, f.viewed])).toEqual([['a.ts', true], ['b.ts', false]])
    expect(completeness).toBe('partial')
  })
})

describe('registry completo', () => {
  it('JSON quebrado cai em rendered-headers sem lançar', () => {
    mountFilesPage({ files: [{ path: 'a.ts' }, { path: 'b.ts', rendered: false }], variant: 'broken-json' })
    const r = new PageResolver(document, defaultRegistry())
    const { files, completeness } = r.fileList().list()
    expect(files.map((f) => f.path)).toEqual(['a.ts'])
    expect(completeness).toBe('partial')
    expect(r.diagnostics().chosen.fileList).toBe('file-list/rendered-headers')
  })
})
