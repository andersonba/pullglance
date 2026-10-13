import { clearEmbeddedCache, readEmbeddedRoute } from './embedded'
import { digestOf, mountFilesPage, replaceEmbeddedJson } from '@@/tests/fixtures/github/build'

describe('readEmbeddedRoute', () => {
  it('lê resumo completo, digests renderizados e oids', () => {
    mountFilesPage({ files: [{ path: 'a.ts', viewed: true }, { path: 'b dir/[x].ts', rendered: false }] })
    const r = readEmbeddedRoute(document)!
    expect(r.basePath).toBe('/acme/web/pull/42')
    expect(r.headOid).toMatch(/^headoid/)
    expect(r.summaries).toEqual([
      { path: 'a.ts', pathDigest: digestOf('a.ts'), markedAsViewed: true },
      { path: 'b dir/[x].ts', pathDigest: digestOf('b dir/[x].ts'), markedAsViewed: false },
    ])
    expect([...r.renderedDigests]).toEqual([digestOf('a.ts')])
    expect(r.filesLimitExceeded).toBe(false)
  })

  it('devolve null sem script ou com JSON quebrado', () => {
    mountFilesPage({ files: [{ path: 'a.ts' }], variant: 'no-embedded' })
    expect(readEmbeddedRoute(document)).toBeNull()
    mountFilesPage({ files: [{ path: 'a.ts' }], variant: 'broken-json' })
    expect(readEmbeddedRoute(document)).toBeNull()
  })

  it('devolve null se diffSummaries não é array', () => {
    mountFilesPage({ files: [{ path: 'a.ts' }] })
    replaceEmbeddedJson(() => ({ payload: { pullRequestsChangesRoute: { diffSummaries: 'nope' } } }))
    expect(readEmbeddedRoute(document)).toBeNull()
  })

  it('selectedRange sem headOid cai para pullRequest.comparison', () => {
    mountFilesPage({ files: [{ path: 'a.ts' }], headOid: 'h-pr' })
    replaceEmbeddedJson((j) => { j.payload.pullRequestsChangesRoute.comparison.selectedRange = { baseOid: 'x' } })
    expect(readEmbeddedRoute(document)?.headOid).toBe('h-pr')
  })

  it('selectedRange com headOid tem prioridade', () => {
    mountFilesPage({ files: [{ path: 'a.ts' }], headOid: 'h-pr' })
    replaceEmbeddedJson((j) => { j.payload.pullRequestsChangesRoute.comparison.selectedRange = { headOid: 'h-range', baseOid: 'b-range' } })
    expect(readEmbeddedRoute(document)).toMatchObject({ headOid: 'h-range', baseOid: 'b-range' })
  })

  it('memoiza pelo nó <script> + tamanho do texto; trocar o nó ou o tamanho relê', () => {
    clearEmbeddedCache()
    mountFilesPage({ files: [{ path: 'a.ts' }], headOid: 'h1' })
    const first = readEmbeddedRoute(document)
    expect(readEmbeddedRoute(document)).toBe(first)                       // mesmo nó, mesmo tamanho: sem reparse
    replaceEmbeddedJson((j) => { j.payload.pullRequestsChangesRoute.pullRequest.comparison.headOid = 'h2' })
    expect(readEmbeddedRoute(document)?.headOid).toBe('h2')               // nó novo (mesmo tamanho de texto)
    const s = document.querySelector('script[data-target="react-app.embeddedData"]')!
    s.textContent = s.textContent!.replace('"h2"', '"h333"')
    expect(readEmbeddedRoute(document)?.headOid).toBe('h333')             // mesmo nó, tamanho diferente
    s.remove()
    expect(readEmbeddedRoute(document)).toBeNull()
  })
})
