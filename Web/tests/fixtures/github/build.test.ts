import { buildFilesPageHtml, digestOf, mountFilesPage } from './build'

describe('fixture builder', () => {
  it('gera JSON embutido legível com todos os arquivos e só os renderizados em diffContents', () => {
    const html = buildFilesPageHtml({ files: [{ path: 'a.ts' }, { path: 'b.ts', rendered: false, viewed: true }] })
    const json = JSON.parse(html.split('data-target="react-app.embeddedData">')[1]!.split('</script>')[0]!)
    const route = json.payload.pullRequestsChangesRoute
    expect(route.diffSummaries.map((d: any) => [d.path, d.markedAsViewed])).toEqual([['a.ts', false], ['b.ts', true]])
    expect(route.diffContents.map((d: any) => d.path)).toEqual(['a.ts'])
    expect(route.pullRequest.pathName).toBe('/acme/web/pull/42')
  })

  it('monta no happy-dom com URL, cabeçalhos e botões', () => {
    const doc = mountFilesPage({ files: [{ path: 'src/x.test.ts' }, { path: 'src/y.ts', viewed: true }] })
    expect(location.href).toBe('https://github.com/acme/web/pull/42/files')
    expect(doc.querySelectorAll('a[href^="#diff-"]')).toHaveLength(2)
    expect(doc.querySelector(`a[href="#diff-${digestOf('src/x.test.ts')}"]`)?.textContent).toContain('src/x.test.ts')
    expect(doc.querySelectorAll('button[aria-label="Not Viewed"]')).toHaveLength(1)
    expect(doc.querySelectorAll('button[aria-label="Viewed"]')).toHaveLength(1)
  })

  it('simula o toggle do GitHub ao clicar', () => {
    const doc = mountFilesPage({ files: [{ path: 'a.ts' }] })
    const btn = doc.querySelector<HTMLButtonElement>('button[aria-label="Not Viewed"]')!
    btn.click()
    expect(btn.getAttribute('aria-pressed')).toBe('true')
    expect(btn.getAttribute('aria-label')).toBe('Viewed')
  })

  it('variantes: css-only sem aria, no-embedded sem script, broken-json inválido', () => {
    expect(buildFilesPageHtml({ files: [{ path: 'a.ts' }], variant: 'css-only' })).not.toContain('aria-pressed')
    expect(buildFilesPageHtml({ files: [{ path: 'a.ts' }], variant: 'no-embedded' })).not.toContain('embeddedData')
    expect(() => JSON.parse(buildFilesPageHtml({ files: [{ path: 'a.ts' }], variant: 'broken-json' }).split('embeddedData">')[1]!.split('</script>')[0]!)).toThrow()
  })

  it('simulateToggle: false desliga o toggle mesmo após um mount anterior com toggle', () => {
    let doc = mountFilesPage({ files: [{ path: 'a.ts' }] })
    let btn = doc.querySelector<HTMLButtonElement>('button[aria-label="Not Viewed"]')!
    btn.click()
    expect(btn.getAttribute('aria-pressed')).toBe('true')
    expect(btn.getAttribute('aria-label')).toBe('Viewed')

    doc = mountFilesPage({ files: [{ path: 'b.ts' }], simulateToggle: false })
    btn = doc.querySelector<HTMLButtonElement>('button[aria-label="Not Viewed"]')!
    btn.click()
    expect(btn.getAttribute('aria-pressed')).toBe('false')
    expect(btn.getAttribute('aria-label')).toBe('Not Viewed')

    doc = mountFilesPage({ files: [{ path: 'c.ts' }] })
    btn = doc.querySelector<HTMLButtonElement>('button[aria-label="Not Viewed"]')!
    btn.click()
    expect(btn.getAttribute('aria-pressed')).toBe('true')
    expect(btn.getAttribute('aria-label')).toBe('Viewed')
  })

  it('JSON embutido é legível pelo DOM após o mount', () => {
    mountFilesPage({ files: [{ path: 'a.ts' }] })
    const json = JSON.parse(document.querySelector('script[data-target="react-app.embeddedData"]')!.textContent!)
    expect(json.payload.pullRequestsChangesRoute.diffSummaries[0].path).toBe('a.ts')
  })
})
