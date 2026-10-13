import { viewedControlAria } from './viewed-control/aria'
import { viewedControlCssModule } from './viewed-control/css-module'
import { fileHeaderAriaLink } from './file-header/aria-link'
import { digestOf, mountFilesPage } from '@@/tests/fixtures/github/build'

const headerOf = (path: string) => fileHeaderAriaLink.create(document).byId(digestOf(path))!.el

describe('viewed-control/aria', () => {
  it('probe positivo na variante aria, negativo na css-only', () => {
    mountFilesPage({ files: [{ path: 'a.ts' }] })
    expect(viewedControlAria.probe(document)).toBe(true)
    mountFilesPage({ files: [{ path: 'a.ts' }], variant: 'css-only' })
    expect(viewedControlAria.probe(document)).toBe(false)
  })

  it('lê estado e alterna via clique', () => {
    mountFilesPage({ files: [{ path: 'a.ts' }, { path: 'b.ts', viewed: true }] })
    const loc = viewedControlAria.create(document)
    const a = loc.inHeader(headerOf('a.ts'))!; const b = loc.inHeader(headerOf('b.ts'))!
    expect(a.isViewed()).toBe(false); expect(b.isViewed()).toBe(true)
    a.toggle()
    expect(a.isViewed()).toBe(true)
  })

  it('devolve null para cabeçalho sem botão', () => {
    mountFilesPage({ files: [{ path: 'a.ts' }] })
    const h = headerOf('a.ts'); h.querySelector('button[aria-label]')?.remove()
    expect(viewedControlAria.create(document).inHeader(h)).toBeNull()
  })
})

describe('viewed-control/css-module', () => {
  it('funciona na variante css-only lendo a classe __viewed__', () => {
    mountFilesPage({ files: [{ path: 'a.ts' }, { path: 'b.ts', viewed: true }], variant: 'css-only' })
    expect(viewedControlCssModule.probe(document)).toBe(true)
    const loc = viewedControlCssModule.create(document)
    const a = loc.inHeader(headerOf('a.ts'))!
    expect(a.isViewed()).toBe(false)
    expect(loc.inHeader(headerOf('b.ts'))!.isViewed()).toBe(true)
    a.toggle(); expect(a.isViewed()).toBe(true)
  })

  it('prioridade menor que a aria', () => {
    expect(viewedControlCssModule.priority).toBeLessThan(viewedControlAria.priority)
  })
})
