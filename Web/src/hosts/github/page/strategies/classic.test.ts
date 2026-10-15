import { fileHeaderClassic } from './file-header/classic-header'
import { viewedControlClassicCollapse } from './viewed-control/classic-collapse'
import { viewedControlClassicButton } from './viewed-control/classic-viewed-button'
import { viewedControlClassicCheckbox } from './viewed-control/classic-checkbox'
import { fileListClassic } from './file-list/classic-files'
import { toolbarSlotClassicToc } from './toolbar-slot/classic-toc'
import { PageResolver } from '../resolver'
import { defaultRegistry } from './index'
import { digestOf, mountFilesPage } from '@@/tests/fixtures/github/build'
import { mountComparePage } from '@@/tests/fixtures/github/compare'

describe('UI clássica (compare)', () => {
  it('file-header/classic-header: id pelo data-anchor, path pelo data-path, selo no .file-info', () => {
    mountComparePage({ files: [{ path: 'src/a b/[id].test.ts' }, { path: 'src/b.ts', collapsed: true }] })
    expect(fileHeaderClassic.probe(document)).toBe(true)
    const loc = fileHeaderClassic.create(document)
    expect(loc.all().map((h) => [h.id, h.path])).toEqual([[digestOf('src/a b/[id].test.ts'), 'src/a b/[id].test.ts'], [digestOf('src/b.ts'), 'src/b.ts']])
    const h = loc.byId(digestOf('src/b.ts'))!
    expect(h.el.classList.contains('file-header')).toBe(true)
    expect(h.labelSlot?.classList.contains('file-info')).toBe(true)
    expect(loc.byId('nope')).toBeNull()
  })

  it('viewed-control/classic-collapse: colapsado = visto; toggle clica no chevron', () => {
    mountComparePage({ files: [{ path: 'a.ts' }, { path: 'b.ts', collapsed: true }] })
    expect(viewedControlClassicCollapse.probe(document)).toBe(true)
    const headers = fileHeaderClassic.create(document)
    const ctl = viewedControlClassicCollapse.create(document)
    const a = ctl.inHeader(headers.byId(digestOf('a.ts'))!.el)!
    expect(a.isViewed()).toBe(false)
    expect(ctl.inHeader(headers.byId(digestOf('b.ts'))!.el)!.isViewed()).toBe(true)
    a.toggle()
    expect(a.isViewed()).toBe(true)
    expect(document.getElementById(`diff-${digestOf('a.ts')}`)!.classList.contains('open')).toBe(false)
  })

  it('file-list/classic-files: visto vem do botão Viewed injetado, não do colapso; parcial se há página pendente', () => {
    mountComparePage({ files: [{ path: 'a.ts' }, { path: 'b.ts', collapsed: true }, { path: 'c.ts', loadDiff: true }] })
    expect(fileListClassic.probe(document)).toBe(true)
    viewedControlClassicButton.create(document).inHeader(fileHeaderClassic.create(document).byId(digestOf('c.ts'))!.el)!.toggle()
    const r = fileListClassic.create(document).list()
    expect(r.files.map((f) => [f.path, f.viewed])).toEqual([['a.ts', false], ['b.ts', false], ['c.ts', true]])
    expect(r.completeness).toBe('full')
    mountComparePage({ files: [{ path: 'a.ts' }], pendingPage: true })
    expect(fileListClassic.create(document).list().completeness).toBe('partial')
  })

  it('viewed-control/classic-viewed-button: injeta um botão Viewed por cabeçalho (idempotente), com o visual do PR', () => {
    mountComparePage({ files: [{ path: 'a.ts' }, { path: 'b.ts' }] })
    expect(viewedControlClassicButton.probe(document)).toBe(true)
    const headers = fileHeaderClassic.create(document)
    const loc = viewedControlClassicButton.create(document)
    const header = headers.byId(digestOf('a.ts'))!.el
    const ctl = loc.inHeader(header)!
    loc.inHeader(header)
    expect(header.querySelectorAll('button[data-ghra-viewed]')).toHaveLength(1)
    const btn = header.querySelector('button[data-ghra-viewed]')!
    expect(btn.parentElement).toBe(header)
    expect(btn.nextElementSibling?.classList.contains('file-actions')).toBe(true)
    expect(btn.className).toContain('Button--small')
    expect(btn.getAttribute('aria-pressed')).toBe('false'); expect(btn.getAttribute('aria-label')).toBe('Not Viewed')
    expect(btn.textContent).toContain('Viewed')
    expect(ctl.isViewed()).toBe(false)
  })

  it('viewed-control/classic-viewed-button: marcar colapsa e pinta de azul; desmarcar expande; chevron não marca', () => {
    mountComparePage({ files: [{ path: 'a.ts' }] })
    const header = fileHeaderClassic.create(document).byId(digestOf('a.ts'))!.el
    const ctl = viewedControlClassicButton.create(document).inHeader(header)!
    const file = document.getElementById(`diff-${digestOf('a.ts')}`)!
    ctl.toggle()
    expect(ctl.isViewed()).toBe(true)
    expect(file.classList.contains('open')).toBe(false)
    expect((ctl.el as HTMLElement).style.cssText).toContain('accent')
    expect(ctl.el.getAttribute('aria-label')).toBe('Viewed')
    ctl.toggle()
    expect(ctl.isViewed()).toBe(false)
    expect(file.classList.contains('open')).toBe(true)
    expect((ctl.el as HTMLElement).style.cssText).toBe('')
    header.querySelector<HTMLButtonElement>('button.js-details-target')!.click()   // colapso manual
    expect(file.classList.contains('open')).toBe(false)
    expect(ctl.isViewed()).toBe(false)
  })

  it('toolbar-slot/classic-toc: área direita do #toc', () => {
    mountComparePage({ files: [{ path: 'a.ts' }] })
    expect(toolbarSlotClassicToc.probe(document)).toBe(true)
    expect(toolbarSlotClassicToc.create(document).find()?.classList.contains('float-right')).toBe(true)
  })

  it('registry: compare escolhe as estratégias clássicas; PR continua com as da UI React', () => {
    mountComparePage({ files: [{ path: 'a.ts' }] })
    const r = new PageResolver(document, defaultRegistry())
    r.fileList(); r.toolbarSlot(); r.headers(); r.viewedControl(r.headers()[0]!.el)
    expect(r.diagnostics().chosen).toMatchObject({ fileList: 'file-list/classic-files', toolbarSlot: 'toolbar-slot/classic-toc', fileHeader: 'file-header/classic-header', viewedControl: 'viewed-control/classic-viewed-button' })
    mountFilesPage({ files: [{ path: 'a.ts' }] })
    const r2 = new PageResolver(document, defaultRegistry())
    r2.fileList(); r2.toolbarSlot(); r2.headers(); r2.viewedControl(r2.headers()[0]!.el)
    expect(r2.diagnostics().chosen).toMatchObject({ fileList: 'file-list/page-route', toolbarSlot: 'toolbar-slot/files-toolbar', fileHeader: 'file-header/aria-link', viewedControl: 'viewed-control/aria' })
  })
})

describe('UI clássica (arquivos do PR): o checkbox Viewed nativo', () => {
  it('viewed-control/classic-checkbox: lê o checked e alterna clicando no checkbox do GitHub', () => {
    mountComparePage({ files: [{ path: 'a.ts' }, { path: 'b.ts', viewed: true, collapsed: true }], nativeViewed: true })
    expect(viewedControlClassicCheckbox.probe(document)).toBe(true)
    const headers = fileHeaderClassic.create(document)
    const ctl = viewedControlClassicCheckbox.create(document)
    const a = ctl.inHeader(headers.byId(digestOf('a.ts'))!.el)!
    expect(a.isViewed()).toBe(false)
    expect(ctl.inHeader(headers.byId(digestOf('b.ts'))!.el)!.isViewed()).toBe(true)
    a.toggle()
    expect(a.isViewed()).toBe(true)
    expect((document.querySelector(`#diff-${digestOf('a.ts')} input.js-reviewed-checkbox`) as HTMLInputElement).checked).toBe(true)
  })

  it('o resolver prefere o checkbox nativo e não injeta o botão Viewed onde ele existe', () => {
    mountComparePage({ files: [{ path: 'a.ts' }, { path: 'b.ts', viewed: true }], nativeViewed: true })
    const resolver = new PageResolver(document, defaultRegistry())
    const header = resolver.headerById(digestOf('b.ts'))!.el
    expect(resolver.viewedControl(header)!.isViewed()).toBe(true)
    expect(viewedControlClassicButton.probe(document)).toBe(false)
    expect(document.querySelector('button[data-ghra-viewed]')).toBeNull()
  })

  it('file-list/classic-files lê o checkbox nativo e não injeta o botão onde ele existe', () => {
    mountComparePage({ files: [{ path: 'a.ts' }, { path: 'b.ts', viewed: true }, { path: 'c.ts', viewed: true, collapsed: true }], nativeViewed: true })
    const r = fileListClassic.create(document).list()
    expect(r.files.map((f) => [f.path, f.viewed])).toEqual([['a.ts', false], ['b.ts', true], ['c.ts', true]])
    expect(document.querySelector('button[data-ghra-viewed]')).toBeNull()
  })

  it('no compare, sem checkbox nativo, o botão injetado continua sendo a estratégia', () => {
    mountComparePage({ files: [{ path: 'a.ts' }] })
    expect(viewedControlClassicCheckbox.probe(document)).toBe(false)
    expect(viewedControlClassicButton.probe(document)).toBe(true)
  })
})
