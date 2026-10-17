import { PageResolver } from './resolver'
import { UnsupportedPage, type Strategy, type StrategyRegistry, type ViewedControlLocator, type FileListSource, type ToolbarSlotSource, type FileHeaderLocator } from './concepts'

const strat = <T>(id: string, priority: number, probe: boolean, value: T): Strategy<T> => ({ id, priority, probe: () => probe, create: () => value })
const emptyRegistry = (): StrategyRegistry => ({ fileList: [], fileHeader: [], viewedControl: [], toolbarSlot: [], fileTree: [] })

describe('PageResolver', () => {
  it('conceito de documento: escolhe maior prioridade que responde e cacheia', () => {
    const reg = emptyRegistry()
    let created = 0
    const src: FileListSource = { list: () => ({ files: [], completeness: 'full' }) }
    reg.fileList = [
      strat('file-list/low', 10, true, src),
      { id: 'file-list/high', priority: 30, probe: () => true, create: () => { created++; return src } },
      strat('file-list/off', 50, false, src),
    ]
    const r = new PageResolver(document, reg)
    r.fileList(); r.fileList()
    expect(created).toBe(1)
    expect(r.diagnostics().chosen.fileList).toBe('file-list/high')
    expect(r.diagnostics().probes.fileList).toEqual({ 'file-list/off': false, 'file-list/high': true })
  })

  it('invalidate refaz a escolha', () => {
    const reg = emptyRegistry()
    let created = 0
    reg.toolbarSlot = [{ id: 'slot/a', priority: 1, probe: () => true, create: () => { created++; return { find: () => null } as ToolbarSlotSource } }]
    const r = new PageResolver(document, reg)
    r.toolbarSlot(); r.invalidate(); r.toolbarSlot()
    expect(created).toBe(2)
  })

  it('invalidateConcept refaz só o conceito pedido', () => {
    const reg = emptyRegistry()
    const created = { slot: 0, list: 0 }
    reg.toolbarSlot = [{ id: 'slot/a', priority: 1, probe: () => true, create: () => { created.slot++; return { find: () => null } as ToolbarSlotSource } }]
    reg.fileList = [{ id: 'list/a', priority: 1, probe: () => true, create: () => { created.list++; return { list: () => ({ files: [], completeness: 'full' }) } as FileListSource } }]
    const r = new PageResolver(document, reg)
    r.toolbarSlot(); r.fileList()
    r.invalidateConcept('toolbarSlot')
    r.toolbarSlot(); r.fileList()
    expect(created).toEqual({ slot: 2, list: 1 })
    expect(r.diagnostics().chosen.toolbarSlot).toBe('slot/a')
  })

  it('nenhuma responde lança UnsupportedPage com o conceito', () => {
    const r = new PageResolver(document, emptyRegistry())
    expect(() => r.fileList()).toThrow(UnsupportedPage)
    try { r.fileList() } catch (e) { expect((e as UnsupportedPage).concept).toBe('fileList') }
    expect(r.diagnostics().chosen.fileList).toBeNull()
  })

  it('conceito de elemento: tenta em ordem por chamada e conta misses', () => {
    const reg = emptyRegistry()
    const a = document.createElement('div'); const b = document.createElement('div'); const c = document.createElement('div')
    const only = (el: Element): ViewedControlLocator => ({ inHeader: (h) => (h === el ? { el: h, isViewed: () => false, toggle() {} } : null) })
    reg.viewedControl = [strat('vc/aria', 30, true, only(a)), strat('vc/css', 10, true, only(b))]
    const r = new PageResolver(document, reg)
    expect(r.viewedControl(a)).not.toBeNull()
    expect(r.viewedControl(b)).not.toBeNull()
    expect(r.viewedControl(c)).toBeNull()
    expect(r.diagnostics().misses.viewedControl).toBe(1)
  })

  it('headers(): primeira estratégia com resultados; headerById em ordem', () => {
    const reg = emptyRegistry()
    const el = document.createElement('div')
    const none: FileHeaderLocator = { byId: () => null, all: () => [] }
    const some: FileHeaderLocator = { byId: (id) => (id === 'x' ? { id, path: 'x.ts', el } : null), all: () => [{ id: 'x', path: 'x.ts', el }] }
    reg.fileHeader = [strat('fh/high', 30, true, none), strat('fh/low', 10, true, some)]
    const r = new PageResolver(document, reg)
    expect(r.headers()).toHaveLength(1)
    expect(r.headerById('x')?.path).toBe('x.ts')
    expect(r.headerById('y')).toBeNull()
  })

  it('conceito de documento: probe que lança cai para próxima estratégia', () => {
    const reg = emptyRegistry()
    const src: FileListSource = { list: () => ({ files: [], completeness: 'full' }) }
    reg.fileList = [
      strat('file-list/low', 10, true, src),
      { id: 'file-list/high', priority: 30, probe: () => { throw new Error('probe falhou') }, create: () => src },
    ]
    const r = new PageResolver(document, reg)
    expect(r.fileList()).toBe(src)
    expect(r.diagnostics().chosen.fileList).toBe('file-list/low')
    expect(r.diagnostics().probes.fileList!['file-list/high']).toBe(false)
  })

  it('locator que lança inHeader tenta próxima estratégia', () => {
    const reg = emptyRegistry()
    const el = document.createElement('div')
    const working: ViewedControlLocator = { inHeader: (h) => (h === el ? { el: h, isViewed: () => false, toggle() {} } : null) }
    const throwing: ViewedControlLocator = { inHeader: () => { throw new Error('inHeader falhou') } }
    reg.viewedControl = [
      { id: 'vc/throws', priority: 30, probe: () => true, create: () => throwing },
      { id: 'vc/works', priority: 10, probe: () => true, create: () => working },
    ]
    const r = new PageResolver(document, reg)
    expect(r.viewedControl(el)).not.toBeNull()
    expect(r.diagnostics().misses.viewedControl).toBeUndefined()
  })

  it('conceito de documento: create que lança cai para próxima estratégia', () => {
    const reg = emptyRegistry()
    const src: FileListSource = { list: () => ({ files: [], completeness: 'full' }) }
    reg.fileList = [
      strat('file-list/low', 10, true, src),
      { id: 'file-list/high', priority: 30, probe: () => true, create: () => { throw new Error('create falhou') } },
    ]
    const r = new PageResolver(document, reg)
    expect(r.fileList()).toBe(src)
    expect(r.diagnostics().chosen.fileList).toBe('file-list/low')
    expect(r.diagnostics().probes.fileList!['file-list/high']).toBe(false)
  })
})
