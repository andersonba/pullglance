import { fileHeaderAriaLink } from './file-header/aria-link'
import { digestOf, mountFilesPage } from '@@/tests/fixtures/github/build'

describe('file-header/aria-link', () => {
  it('lista cabeçalhos renderizados com id (digest) e path limpo', () => {
    mountFilesPage({ files: [{ path: 'src/a b/[id].test.ts' }, { path: 'c.ts', rendered: false }] })
    expect(fileHeaderAriaLink.probe(document)).toBe(true)
    const all = fileHeaderAriaLink.create(document).all()
    expect(all.map((h) => [h.id, h.path])).toEqual([[digestOf('src/a b/[id].test.ts'), 'src/a b/[id].test.ts']])
    expect(all[0]!.el.getAttribute('data-diff-header-wrapper')).toBe('true')
  })

  it('byId devolve null para digest não renderizado', () => {
    mountFilesPage({ files: [{ path: 'c.ts', rendered: false }] })
    expect(fileHeaderAriaLink.create(document).byId(digestOf('c.ts'))).toBeNull()
  })

  it('probe falso sem links #diff-', () => {
    document.documentElement.innerHTML = '<head></head><body><p>nada</p></body>'
    expect(fileHeaderAriaLink.probe(document)).toBe(false)
  })
})
