import { contextKey, isFilesPagePath, pageKindOf, readContext } from './location'
import { storeFetchedRoute } from './route-source'
import { readEmbeddedRoute } from './embedded'
import { buildFilesPageHtml, mountFilesPage } from '@@/tests/fixtures/github/build'

describe('readContext', () => {
  it('monta contexto a partir da URL e do JSON', () => {
    mountFilesPage({ files: [{ path: 'a.ts' }], basePath: '/acme/web/pull/42', headOid: 'h1' })
    const ctx = readContext({ pathname: '/acme/web/pull/42/files', search: '' }, document)
    expect(ctx).toEqual({ key: contextKey('/acme/web/pull/42', 'h1', ''), basePath: '/acme/web/pull/42', headOid: 'h1' })
  })

  it('aceita /changes, ignora outras abas e inclui search na chave', () => {
    mountFilesPage({ files: [{ path: 'a.ts' }], headOid: 'h1' })
    expect(readContext({ pathname: '/acme/web/pull/42/changes', search: '?range=a..b' }, document)?.key).toContain('?range=a..b')
    expect(readContext({ pathname: '/acme/web/pull/42', search: '' }, document)).toBeNull()
    expect(readContext({ pathname: '/acme/web/pull/42/commits', search: '' }, document)).toBeNull()
  })

  it('sem JSON legível devolve contexto degradado (headOid vazio) para o fallback por cabeçalhos', () => {
    const degraded = { key: contextKey('/acme/web/pull/42', '', '?w=1'), basePath: '/acme/web/pull/42', headOid: '' }
    mountFilesPage({ files: [{ path: 'a.ts' }], variant: 'no-embedded' })
    expect(readContext({ pathname: '/acme/web/pull/42/files', search: '?w=1' }, document)).toEqual(degraded)
    mountFilesPage({ files: [{ path: 'a.ts' }], variant: 'broken-json' })
    expect(readContext({ pathname: '/acme/web/pull/42/files', search: '?w=1' }, document)).toEqual(degraded)
    expect(readContext({ pathname: '/acme/web/pull/42/commits', search: '' }, document)).toBeNull()
  })

  it('JSON de outro PR (navegação interna) devolve contexto degradado deste PR, não null', () => {
    mountFilesPage({ files: [{ path: 'a.ts' }], basePath: '/acme/web/pull/42' })
    expect(readContext({ pathname: '/acme/web/pull/43/files', search: '' }, document)).toEqual({ key: contextKey('/acme/web/pull/43', '', ''), basePath: '/acme/web/pull/43', headOid: '' })
  })

  it('rota buscada preenche o headOid quando o JSON embutido é de outro PR', () => {
    mountFilesPage({ files: [{ path: 'a.ts' }], basePath: '/acme/web/pull/42' })
    const fetched = new DOMParser().parseFromString(buildFilesPageHtml({ files: [{ path: 'b.ts' }], basePath: '/acme/web/pull/43', headOid: 'h43' }), 'text/html')
    storeFetchedRoute(readEmbeddedRoute(fetched)!)
    expect(readContext({ pathname: '/acme/web/pull/43/files', search: '' }, document)?.headOid).toBe('h43')
  })
})

describe('compare', () => {
  it('reconhece /owner/repo/compare/<range> com pontos, barras, encoding e query; ignora /compare sem range', () => {
    for (const p of ['/acme/web/compare/main...feat/x', '/acme/web/compare/a%2Fb...c', '/acme/web/compare/v1.0.0...v1.0.1/']) {
      expect(pageKindOf(p)).toBe('compare'); expect(isFilesPagePath(p)).toBe(true)
    }
    expect(pageKindOf('/acme/web/compare')).toBeNull()
    expect(pageKindOf('/acme/web/compare/')).toBeNull()
    expect(pageKindOf('/acme/web/pull/42/files')).toBe('pull')
  })

  it('contexto do compare: basePath com o range, sem headOid, sem consultar o JSON embutido', () => {
    mountFilesPage({ files: [{ path: 'a.ts' }], basePath: '/acme/web/pull/42' })   // JSON de um PR na página não interfere
    const ctx = readContext({ pathname: '/acme/web/compare/main...feat/x', search: '?expand=1' }, document)
    expect(ctx).toEqual({ key: contextKey('/acme/web/compare/main...feat/x', '', '?expand=1'), basePath: '/acme/web/compare/main...feat/x', headOid: '' })
  })
})
