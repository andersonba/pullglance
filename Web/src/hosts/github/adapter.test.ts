import { AbortedInFlight } from '@/core/host'
import { createGitHubAdapter } from './adapter'
import { UnsupportedPage } from './page/concepts'
import { digestOf, mountFilesPage, buildFilesPageHtml, replaceEmbeddedJson } from '@@/tests/fixtures/github/build'
import { mountComparePage } from '@@/tests/fixtures/github/compare'
import { CompareMemory, type CompareMemoryEntry, type CompareMemoryStore } from './compare-memory'

const okJson = () => new Response('{}', { status: 200 })
const file = (path: string, viewed = false, hasControl = true) => ({ path, id: digestOf(path), viewed, hasControl })

describe('createGitHubAdapter', () => {
  it('navegação interna: JSON de outro PR → busca a página de arquivos, troca o contexto e lista tudo', async () => {
    // Página montada para o PR 42 (cabeçalho de a.test.ts renderizado), mas o JSON embutido é do PR 41.
    mountFilesPage({ files: [{ path: 'a.test.ts' }, { path: 'b.test.ts', rendered: false }], basePath: '/acme/web/pull/42' })
    replaceEmbeddedJson(() => JSON.parse(buildFilesPageHtml({ files: [{ path: 'old.ts' }], basePath: '/acme/web/pull/41' }).split('embeddedData">')[1]!.split('</script>')[0]!))
    const served = buildFilesPageHtml({ files: [{ path: 'a.test.ts' }, { path: 'b.test.ts', viewed: true }], basePath: '/acme/web/pull/42', headOid: 'h42' })
    const urls: string[] = []
    const a = createGitHubAdapter({ fetchImpl: async (u) => { urls.push(u); return new Response(served, { status: 200 }) } })
    const keys: string[] = []
    const stop = a.onContextChange((c) => keys.push(c?.key ?? 'null'))

    expect(a.currentContext()).toMatchObject({ basePath: '/acme/web/pull/42', headOid: '' })
    const first = await a.listFiles()                      // dispara a busca; enquanto isso, só os cabeçalhos renderizados
    expect(first.completeness).toBe('partial')
    expect(first.files.map((f) => f.path)).toEqual(['a.test.ts'])

    await vi.waitFor(() => expect(keys.at(-1)).toBe('/acme/web/pull/42|h42|'))
    expect(urls).toEqual(['/acme/web/pull/42/files'])
    const second = await a.listFiles()
    expect(second.completeness).toBe('full')
    expect(second.files.map((f) => [f.path, f.viewed])).toEqual([['a.test.ts', false], ['b.test.ts', true]])
    expect(urls).toHaveLength(1)                           // buscou uma vez só
    stop()
  })

  it('listFiles: JSON embutido + hasControl + revalidação pelo DOM', async () => {
    mountFilesPage({ files: [{ path: 'a.ts' }, { path: 'b.ts', rendered: false }] })
    document.querySelector<HTMLButtonElement>('button[aria-label="Not Viewed"]')!.click()   // usuário marcou a.ts depois do load
    const a = createGitHubAdapter()
    const l = await a.listFiles()
    expect(l.completeness).toBe('full')
    expect(l.files).toEqual([file('a.ts', true, true), file('b.ts', false, false)])
    expect(a.currentContext()?.basePath).toBe('/acme/web/pull/42')
  })

  it('setViewed via DOM: clica, espera o estado virar, grava overlay', async () => {
    mountFilesPage({ files: [{ path: 'a.ts' }] })
    const calls: string[] = []
    const a = createGitHubAdapter({ fetchImpl: async (u) => { calls.push(u); return okJson() } })
    expect(await a.setViewed(file('a.ts'), true)).toBe('dom')
    expect(document.querySelector('button[aria-label="Viewed"]')).not.toBeNull()
    expect(calls).toEqual([])
    expect((await a.listFiles()).files[0]!.viewed).toBe(true)
  })

  it('setViewed devolve noop se já está no estado pedido', async () => {
    mountFilesPage({ files: [{ path: 'a.ts', viewed: true }] })
    expect(await createGitHubAdapter().setViewed(file('a.ts'), true)).toBe('noop')
  })

  it('setViewed via DOM: timeout quando o botão não reage', async () => {
    mountFilesPage({ files: [{ path: 'a.ts' }], simulateToggle: false })
    const a = createGitHubAdapter({ domTimeoutMs: 20 })
    await expect(a.setViewed(file('a.ts'), true)).rejects.toThrow(/didn't confirm/)
  })

  it('setViewed via API quando não há controle, e overlay reflete na listagem', async () => {
    mountFilesPage({ files: [{ path: 'a.ts' }, { path: 'b.ts', rendered: false }] })
    const calls: Array<[string, string]> = []
    const a = createGitHubAdapter({ fetchImpl: async (u, i) => { calls.push([u, i!.method!]); return okJson() } })
    expect(await a.setViewed(file('b.ts', false, false), true)).toBe('api')
    expect(calls).toEqual([['/acme/web/pull/42/file_review', 'POST']])
    expect((await a.listFiles()).files[1]!.viewed).toBe(true)
    expect(await a.setViewed(file('b.ts', true, false), true)).toBe('noop')
  })

  it('reconcile baixa a página, devolve o estado do servidor e corrige o overlay dos arquivos sem controle', async () => {
    mountFilesPage({ files: [{ path: 'a.ts' }, { path: 'b.ts', rendered: false }] })
    const serverHtml = buildFilesPageHtml({ files: [{ path: 'a.ts', viewed: false }, { path: 'b.ts', viewed: false }] })
    const a = createGitHubAdapter({ fetchImpl: async (u) => (u.endsWith('/files') ? new Response(serverHtml, { status: 200 }) : okJson()) })
    await a.setViewed(file('a.ts'), true)                 // DOM otimista
    await a.setViewed(file('b.ts', false, false), true)   // API, 2xx mas o servidor "não persistiu"
    const state = await a.reconcile([digestOf('a.ts'), digestOf('b.ts')])
    expect(state.get(digestOf('a.ts'))).toBe(false)
    expect(state.get(digestOf('b.ts'))).toBe(false)
    const files = (await a.listFiles()).files
    expect(files[0]!.viewed).toBe(true)    // DOM continua sendo a verdade enquanto o controle existe
    expect(files[1]!.viewed).toBe(false)   // overlay corrigido pelo servidor
  })

  it('loadAll: só arquivos com cabeçalho montado, reporta progresso, respeita timeout', async () => {
    mountFilesPage({ files: [{ path: 'a.ts' }, { path: 'b.ts', rendered: false }] })
    document.querySelector('button[aria-label="Not Viewed"]')!.remove()   // a.ts montado sem controle
    const a = createGitHubAdapter({ loadTimeoutMs: 10 })
    const progress: Array<[number, number | undefined]> = []
    await a.loadAll((d, t) => progress.push([d, t]))
    expect(progress).toEqual([[1, 1]])
  })

  it('onContextChange dispara quando a chave muda e invalida o resolver', async () => {
    mountFilesPage({ files: [{ path: 'a.ts' }], headOid: 'h1' })
    const a = createGitHubAdapter()
    const seen: Array<string | null> = []
    const stop = a.onContextChange((c) => seen.push(c?.key ?? null))
    replaceEmbeddedJson((j) => { j.payload.pullRequestsChangesRoute.pullRequest.comparison.headOid = 'h2' })
    document.title = 'outro título'
    await vi.waitFor(() => expect(seen.at(-1)).toContain('|h2|'))
    stop()
  })

  it('onContextChange: debounce de 150 ms coalesce mutações', async () => {
    mountFilesPage({ files: [{ path: 'a.ts' }], headOid: 'h1' })
    const a = createGitHubAdapter()
    const cb = vi.fn()
    const stop = a.onContextChange(cb)
    replaceEmbeddedJson((j) => { j.payload.pullRequestsChangesRoute.pullRequest.comparison.headOid = 'h2' })
    await new Promise((r) => setTimeout(r, 60))
    replaceEmbeddedJson((j) => { j.payload.pullRequestsChangesRoute.pullRequest.comparison.headOid = 'h3' })
    await new Promise((r) => setTimeout(r, 60))
    expect(cb).not.toHaveBeenCalled()                     // ainda dentro da janela de debounce
    await vi.waitFor(() => expect(cb).toHaveBeenCalledTimes(1))
    expect(cb.mock.calls[0]![0].key).toContain('|h3|')
    stop()
  })

  it('onContextChange: só characterData não dispara; turbo:render dispara a checagem', async () => {
    mountFilesPage({ files: [{ path: 'a.ts' }], headOid: 'h1' })
    const a = createGitHubAdapter()
    const cb = vi.fn()
    const stop = a.onContextChange(cb)
    const text = document.querySelector('script[data-target="react-app.embeddedData"]')!.firstChild as Text
    text.data = text.data.replace('"h1"', '"h22"')        // mutação só de characterData
    await new Promise((r) => setTimeout(r, 250))
    expect(cb).not.toHaveBeenCalled()
    document.dispatchEvent(new Event('turbo:render'))
    await vi.waitFor(() => expect(cb).toHaveBeenCalledTimes(1))
    expect(cb.mock.calls[0]![0].key).toContain('|h22|')
    stop()
  })

  it('I3: toolbarSlot re-proba a cada chamada; troca do floating para a toolbar quando ela aparece', async () => {
    mountFilesPage({ files: [{ path: 'a.ts' }] })
    const slot = document.querySelector('[class*="PullRequestFilesToolbar-module__file-controls"]')!
    const parent = slot.parentElement!
    slot.remove()                                          // toolbar do GitHub ainda não renderizada
    const a = createGitHubAdapter()
    expect(a.toolbarSlot()?.el.getAttribute('data-ghra-floating')).toBe('true')
    parent.append(slot)                                    // GitHub re-renderiza a toolbar
    expect(a.toolbarSlot()).toEqual({ el: slot, placement: 'last' })
    expect(a.diagnostics().chosen.toolbarSlot).toBe('toolbar-slot/files-toolbar')
  })

  it('setViewed via DOM: abort durante a espera vira AbortedInFlight', async () => {
    mountFilesPage({ files: [{ path: 'a.ts' }], simulateToggle: false })
    const a = createGitHubAdapter({ domTimeoutMs: 500 })
    const ac = new AbortController()
    setTimeout(() => ac.abort(), 20)
    await expect(a.setViewed(file('a.ts'), true, ac.signal)).rejects.toBeInstanceOf(AbortedInFlight)
  })

  it('onContextChange: stop() cancela o tick pendente', async () => {
    mountFilesPage({ files: [{ path: 'a.ts' }], headOid: 'h1' })
    const a = createGitHubAdapter()
    const cb = vi.fn()
    const stop = a.onContextChange(cb)
    replaceEmbeddedJson((j) => { j.payload.pullRequestsChangesRoute.pullRequest.comparison.headOid = 'h2' })
    window.dispatchEvent(new PopStateEvent('popstate'))   // agenda o tick de forma síncrona
    stop()
    await new Promise((r) => setTimeout(r, 250))
    expect(cb).not.toHaveBeenCalled()
  })

  it('C1: estado visto no DOM sobrevive à desmontagem do cabeçalho (virtualização)', async () => {
    mountFilesPage({ files: [{ path: 'x.ts' }, { path: 'y.ts' }] })
    const calls: string[] = []
    const a = createGitHubAdapter({ fetchImpl: async (u) => { calls.push(u); return okJson() } })
    const header = () => document.querySelector(`a[href="#diff-${digestOf('x.ts')}"]`)!.closest('[data-diff-header-wrapper]')!
    ;(header().querySelector('button[aria-label="Not Viewed"]') as HTMLButtonElement).click()   // usuário marca x.ts à mão
    expect((await a.listFiles()).files[0]!.viewed).toBe(true)
    header().remove()                                                                             // GitHub desmonta x.ts
    const x = (await a.listFiles()).files[0]!
    expect(x).toEqual(file('x.ts', true, false))
    expect(await a.setViewed(file('x.ts', false, false), true)).toBe('noop')
    expect(calls).toEqual([])
  })

  it('I1: JSON quebrado com cabeçalhos montados usa o fallback por cabeçalhos de ponta a ponta', async () => {
    mountFilesPage({ files: [{ path: 'a.ts', viewed: true }, { path: 'b.ts' }], variant: 'broken-json' })
    const a = createGitHubAdapter()
    expect(a.currentContext()).toEqual({ key: '/acme/web/pull/42||', basePath: '/acme/web/pull/42', headOid: '' })
    const l = await a.listFiles()
    expect(l.completeness).toBe('partial')
    expect(l.files).toEqual([file('a.ts', true, true), file('b.ts', false, true)])
  })

  it('página sem JSON e sem cabeçalhos: contexto degradado e listFiles lança UnsupportedPage', async () => {
    document.documentElement.innerHTML = '<head><title>x</title></head><body></body>'
    ;(window as any).happyDOM.setURL('https://github.com/acme/web/pull/42/files')
    const a = createGitHubAdapter()
    expect(a.currentContext()?.headOid).toBe('')
    expect(a.isFilesPage()).toBe(true)
    await expect(a.listFiles()).rejects.toBeInstanceOf(UnsupportedPage)
  })
})

describe('rota buscada com falha', () => {
  it('não refaz o GET a cada leitura: espera o intervalo de nova tentativa', async () => {
    mountFilesPage({ files: [{ path: 'a.test.ts' }], variant: 'no-embedded' })
    let calls = 0
    const a = createGitHubAdapter({ fetchImpl: async () => { calls++; return new Response('', { status: 500 }) } })
    await a.listFiles(); await vi.waitFor(() => expect(calls).toBe(1))
    await a.listFiles(); await a.listFiles(); await new Promise((r) => setTimeout(r, 30))
    expect(calls).toBe(1)
  })
})

describe('compare (UI clássica)', () => {
  it('lista com visto = botão Viewed injetado; marcar colapsa, desmarcar expande; nenhum fetch', async () => {
    mountComparePage({ files: [{ path: 'a.test.ts' }, { path: 'b.ts', collapsed: true }] })
    const calls: string[] = []
    const a = createGitHubAdapter({ fetchImpl: async (u) => { calls.push(u); return okJson() } })
    expect(a.pageKind()).toBe('compare'); expect(a.isFilesPage()).toBe(true)
    expect(a.currentContext()).toMatchObject({ basePath: '/acme/web/compare/main...feat/x', headOid: '' })
    const l = await a.listFiles()
    expect(l.completeness).toBe('full')
    expect(l.files).toEqual([file('a.test.ts', false, true), file('b.ts', false, true)])   // colapsado à mão não é visto
    expect(await a.setViewed(file('a.test.ts'), true)).toBe('dom')
    expect(document.getElementById(`diff-${digestOf('a.test.ts')}`)!.classList.contains('open')).toBe(false)
    expect(document.querySelector(`[data-anchor="diff-${digestOf('a.test.ts')}"] button[data-ghra-viewed]`)?.getAttribute('aria-pressed')).toBe('true')
    expect(await a.setViewed(file('a.test.ts', true), true)).toBe('noop')
    expect(await a.setViewed(file('a.test.ts', true), false)).toBe('dom')
    expect(document.getElementById(`diff-${digestOf('a.test.ts')}`)!.classList.contains('open')).toBe(true)
    expect(calls).toEqual([])
  })

  it('reconcile no compare lê o DOM e não busca nada; sem controle, setViewed falha em vez de chamar a API', async () => {
    mountComparePage({ files: [{ path: 'a.test.ts', collapsed: true }, { path: 'b.ts' }] })
    const calls: string[] = []
    const a = createGitHubAdapter({ fetchImpl: async (u) => { calls.push(u); return okJson() } })
    await a.setViewed(file('a.test.ts'), true)
    const state = await a.reconcile([digestOf('a.test.ts'), digestOf('b.ts')])
    expect(state.get(digestOf('a.test.ts'))).toBe(true); expect(state.get(digestOf('b.ts'))).toBe(false)
    await expect(a.setViewed(file('ghost.ts', false, false), true)).rejects.toThrow(/not loaded/)
    expect(calls).toEqual([])
  })
})

describe('compare: memória de vistos', () => {
  function memStore(initial: Record<string, CompareMemoryEntry> = {}) {
    const data = new Map(Object.entries(initial))
    const store: CompareMemoryStore = {
      get: async (k) => data.get(k) ?? null, set: async (k, e) => { data.set(k, e) }, remove: async (k) => { data.delete(k) }, keys: async () => [...data.keys()],
    }
    return { store, data }
  }
  const KEY = 'local:ghra:compare:/acme/web/compare/main...feat/x'

  it('restaura os lembrados colapsando no primeiro listFiles e espelha mudanças manuais no storage', async () => {
    const { store, data } = memStore({ [KEY]: { viewed: [digestOf('a.test.ts'), digestOf('ghost.ts')], updatedAt: 1 } })
    mountComparePage({ files: [{ path: 'a.test.ts' }, { path: 'b.ts' }] })
    const a = createGitHubAdapter({ compareMemory: new CompareMemory({ store, writeDelayMs: 0 }), restoreBatch: 1 })
    const first = await a.listFiles()
    expect(first.files.map((f) => [f.path, f.viewed])).toEqual([['a.test.ts', true], ['b.ts', false]])
    expect(document.getElementById(`diff-${digestOf('a.test.ts')}`)!.classList.contains('open')).toBe(false)
    expect(document.querySelector(`[data-anchor="diff-${digestOf('a.test.ts')}"] button[data-ghra-viewed]`)?.getAttribute('aria-pressed')).toBe('true')
    // usuário desmarca a.test.ts e marca b.ts pelo botão Viewed
    document.querySelector<HTMLButtonElement>(`[data-anchor="diff-${digestOf('a.test.ts')}"] button[data-ghra-viewed]`)!.click()
    document.querySelector<HTMLButtonElement>(`[data-anchor="diff-${digestOf('b.ts')}"] button[data-ghra-viewed]`)!.click()
    await a.listFiles()
    await a.flushMemory()
    // ghost.ts não está na página: fica como estava (pode ser um arquivo que ainda não carregou)
    expect(data.get(KEY)?.viewed).toEqual([digestOf('b.ts'), digestOf('ghost.ts')].sort())
    // o listFiles seguinte não re-colapsa a.test.ts: a restauração é uma vez por contexto
    const again = await a.listFiles()
    expect(again.files.map((f) => f.viewed)).toEqual([false, true])
  })

  it('arquivo lembrado que chega depois (carregamento progressivo) é restaurado quando aparece', async () => {
    const { store } = memStore({ [KEY]: { viewed: [digestOf('late.test.ts')], updatedAt: 1 } })
    mountComparePage({ files: [{ path: 'a.ts' }] })
    const a = createGitHubAdapter({ compareMemory: new CompareMemory({ store, writeDelayMs: 0 }) })
    await a.listFiles()
    const files = document.getElementById('files')!
    const extra = document.createElement('div')
    extra.innerHTML = mountComparePageHtmlFor('late.test.ts')
    files.append(...Array.from(extra.children))
    const l = await a.listFiles()
    expect(l.files.find((f) => f.path === 'late.test.ts')?.viewed).toBe(true)
  })

  it('arquivo marcado que sai do DOM (virtualização) continua gravado', async () => {
    const { store, data } = memStore({})
    mountComparePage({ files: [{ path: 'a.ts' }, { path: 'b.ts' }] })
    const a = createGitHubAdapter({ compareMemory: new CompareMemory({ store, writeDelayMs: 0 }) })
    await a.listFiles()
    document.querySelector<HTMLButtonElement>(`[data-anchor="diff-${digestOf('a.ts')}"] button[data-ghra-viewed]`)!.click()
    await a.listFiles(); await a.flushMemory()
    expect(data.get(KEY)?.viewed).toEqual([digestOf('a.ts')])
    // a.ts é desmontado da página; marcar b.ts não pode apagar a.ts do storage
    document.querySelector(`[data-anchor="diff-${digestOf('a.ts')}"]`)!.closest('.file')?.remove()
    document.getElementById(`diff-${digestOf('a.ts')}`)?.remove()
    document.querySelector<HTMLButtonElement>(`[data-anchor="diff-${digestOf('b.ts')}"] button[data-ghra-viewed]`)!.click()
    await a.listFiles(); await a.flushMemory()
    expect(data.get(KEY)?.viewed).toEqual([digestOf('a.ts'), digestOf('b.ts')].sort())
  })

  it('setting desligado: não restaura nem grava', async () => {
    const { store, data } = memStore({ [KEY]: { viewed: [digestOf('a.test.ts')], updatedAt: 1 } })
    mountComparePage({ files: [{ path: 'a.test.ts' }] })
    const a = createGitHubAdapter({ compareMemory: new CompareMemory({ store, writeDelayMs: 0 }) })
    a.configure({ rememberCompare: false })
    expect((await a.listFiles()).files[0]!.viewed).toBe(false)
    await a.setViewed(file('a.test.ts'), true)
    await a.listFiles(); await a.flushMemory()
    expect(data.get(KEY)?.viewed).toEqual([digestOf('a.test.ts')])   // intocado
  })

  it('no PR a memória do compare não é usada', async () => {
    const { store, data } = memStore()
    mountFilesPage({ files: [{ path: 'a.test.ts', viewed: true }] })
    const a = createGitHubAdapter({ compareMemory: new CompareMemory({ store, writeDelayMs: 0 }) })
    await a.listFiles(); await a.flushMemory()
    expect(data.size).toBe(0)
  })
})

describe('compare: loadAll carrega o restante (carregamento progressivo)', () => {
  /** Simula o GitHub: quando o fragmento pendente é rolado para a viewport, ele é trocado pelos próximos arquivos. */
  function simulateProgressiveLoad(pages: string[][]) {
    const fragment = () => document.querySelector('.js-diff-progressive-container include-fragment') as HTMLElement | null
    const pending = [...pages]
    const original = Element.prototype.scrollIntoView
    Element.prototype.scrollIntoView = function (this: Element) {
      const f = fragment()
      if (this !== f || !f) return
      setTimeout(() => {
        const next = pending.shift() ?? []
        const html = next.map(mountComparePageHtmlFor).join('')
        const container = f.closest('.js-diff-progressive-container')!
        // Como no GitHub: a resposta traz os próximos arquivos e, se houver mais, um NOVO fragmento pendente.
        const nextFragment = pending.length > 0 ? '<div class="js-diff-progressive-container"><include-fragment src="/acme/web/compare/file-list?range=x&amp;start_entry=600"></include-fragment></div>' : ''
        container.outerHTML = html + nextFragment
      }, 5)
    }
    return () => { Element.prototype.scrollIntoView = original }
  }

  it('rola até o fragmento pendente até não sobrar nenhum, reportando o total de cabeçalhos; depois lista completa', async () => {
    mountComparePage({ files: [{ path: 'a.ts' }], pendingPage: true })
    const restore = simulateProgressiveLoad([['b.test.ts', 'c.ts'], ['d.test.ts']])
    try {
      const a = createGitHubAdapter({ compareMemory: null, loadTimeoutMs: 500 })
      expect((await a.listFiles()).completeness).toBe('partial')
      const progress: Array<[number, number | undefined]> = []
      await a.loadAll((d, t) => progress.push([d, t]))
      expect(progress).toEqual([[3, undefined], [4, undefined]])
      const l = await a.listFiles()
      expect(l.completeness).toBe('full')
      expect(l.files.map((f) => f.path)).toEqual(['a.ts', 'b.test.ts', 'c.ts', 'd.test.ts'])
    } finally { restore() }
  })

  it('GitHub não responde: para após o timeout em vez de girar; abort interrompe', async () => {
    mountComparePage({ files: [{ path: 'a.ts' }], pendingPage: true })
    const a = createGitHubAdapter({ compareMemory: null, loadTimeoutMs: 30 })
    await a.loadAll()
    expect((await a.listFiles()).completeness).toBe('partial')
    const ac = new AbortController(); ac.abort()
    await a.loadAll(undefined, ac.signal)
  })
})

function mountComparePageHtmlFor(path: string): string {
  // um arquivo clássico extra, igual ao da fixture, para simular a página seguinte do carregamento progressivo
  const d = digestOf(path)
  return `<div id="diff-${d}" class="file js-file js-details-container Details Details--on open" data-tagsearch-path="${path}">
    <div class="file-header js-file-header" data-path="${path}" data-anchor="diff-${d}"><div class="file-info">
      <button type="button" class="btn-octicon js-details-target" aria-label="Toggle diff contents" aria-expanded="true"></button>
      <span class="Truncate"><a class="Link--primary" href="#diff-${d}">${path}</a></span></div><div class="file-actions"></div></div>
    <div class="js-file-content"></div></div>`
}
