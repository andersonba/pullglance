import { toolbarSlotFilesToolbar } from './toolbar-slot/files-toolbar'
import { toolbarSlotFloating } from './toolbar-slot/floating'
import { toolbarSlotClassicToc } from './toolbar-slot/classic-toc'
import { mountComparePage } from '@@/tests/fixtures/github/compare'
import { mountFilesPage } from '@@/tests/fixtures/github/build'

describe('toolbar-slot', () => {
  it('files-toolbar acha a área de controles de arquivos', () => {
    mountFilesPage({ files: [{ path: 'a.ts' }] })
    expect(toolbarSlotFilesToolbar.probe(document)).toBe(true)
    expect(toolbarSlotFilesToolbar.create(document).find()?.className).toContain('file-controls')
  })

  it('floating sempre responde e cria um contêiner único no body', () => {
    document.documentElement.innerHTML = '<head></head><body></body>'
    expect(toolbarSlotFilesToolbar.probe(document)).toBe(false)
    expect(toolbarSlotFloating.probe(document)).toBe(true)
    const a = toolbarSlotFloating.create(document).find(); const b = toolbarSlotFloating.create(document).find()
    expect(a).toBe(b)
    expect(a?.getAttribute('data-ghra-floating')).toBe('true')
  })

  it('classic-toc entra como irmão flutuante depois do bloco Split/Unified; files-toolbar fica no fim', () => {
    mountComparePage({ files: [{ path: 'a.ts' }] })
    expect(toolbarSlotClassicToc.create(document)).toMatchObject({ placement: 'after', hostFlag: 'float-right' })
    mountFilesPage({ files: [{ path: 'a.ts' }] })
    expect(toolbarSlotFilesToolbar.create(document).placement).toBeUndefined()
  })
})
