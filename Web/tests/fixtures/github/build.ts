import { DIFF_BODY, EMBEDDED_SCRIPT_OPEN, FILE_HEADER, LARGE_DIFF_BODY, TOOLBAR, VIEWED_BUTTON_ARIA, VIEWED_BUTTON_CSS_ONLY } from './fragments'

/**
 * `largeDiff`: GitHub's "Large diffs are not rendered by default." placeholder instead of the diff body.
 * Markup assumed (not captured from a live page): header present, a "Load Diff" button, no diff table.
 */
export interface FixtureFile { path: string; viewed?: boolean; rendered?: boolean; digest?: string; largeDiff?: boolean }
export interface FixtureOptions {
  files: FixtureFile[]
  basePath?: string
  headOid?: string
  baseOid?: string
  variant?: 'aria' | 'css-only' | 'no-embedded' | 'broken-json'
  simulateToggle?: boolean
  /** Wraps each file in a `#diff-<digest>` container, as the live new Files UI does. */
  containers?: boolean
}

export function digestOf(path: string): string {
  let h1 = 0x811c9dc5, h2 = 0x01000193
  for (const ch of path) { h1 = Math.imul(h1 ^ ch.codePointAt(0)!, 0x01000193); h2 = Math.imul(h2 + ch.codePointAt(0)!, 0x9e3779b1) }
  const hex = (n: number) => (n >>> 0).toString(16).padStart(8, '0')
  return (hex(h1) + hex(h2) + hex(h1 ^ h2) + hex(h1 + h2)).repeat(2).slice(0, 64)
}

const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;')

function fill(tpl: string, vars: Record<string, string>) {
  return tpl.replace(/\{\{(\w+)\}\}/g, (_, k) => vars[k] ?? '')
}

function viewedButton(viewed: boolean, variant: FixtureOptions['variant']) {
  const tpl = variant === 'css-only' ? VIEWED_BUTTON_CSS_ONLY : VIEWED_BUTTON_ARIA
  return fill(tpl, {
    pressed: String(viewed),
    label: viewed ? 'Viewed' : 'Not Viewed',
    viewedClass: viewed ? 'MarkAsViewedButton-module__viewed__k8dzo ' : '',
  })
}

function embeddedJson(opts: Required<Pick<FixtureOptions, 'files' | 'basePath' | 'headOid' | 'baseOid'>>) {
  const diffSummaries = opts.files.map((f) => ({
    changeType: 'MODIFIED', isCodeowner: null, isManifestFile: false, isVendored: false, isSymlink: false,
    linesAdded: 1, linesChanged: 1, linesDeleted: 0, markedAsViewed: f.viewed ?? false, markersMap: {},
    path: f.path, pathDigest: f.digest ?? digestOf(f.path), highestAnnotationLevel: null,
  }))
  const diffContents = opts.files.filter((f) => f.rendered !== false).map((f) => ({ path: f.path, pathDigest: f.digest ?? digestOf(f.path), diffLines: [] }))
  const number = Number(opts.basePath.split('/').pop())
  return {
    payload: {
      pullRequestsChangesRoute: {
        isSingleFileMode: false,
        diffSummaries,
        diffContents,
        pullRequest: { number, pathName: opts.basePath, comparison: { baseOid: opts.baseOid, headOid: opts.headOid } },
        comparison: { selectedRange: null },
        user: { viewedFilesCount: diffSummaries.filter((d) => d.markedAsViewed).length },
        pageLimits: { filesLimit: 3000, filesLimitExceeded: false },
        virtualizeDiffEntries: false,
      },
    },
    title: 'PR de teste',
    appPayload: {},
  }
}

export function buildFilesPageHtml(options: FixtureOptions): string {
  const opts = {
    basePath: '/acme/web/pull/42',
    headOid: 'headoid0000000000000000000000000000000001',
    baseOid: 'baseoid0000000000000000000000000000000001',
    variant: 'aria' as const,
    ...options,
  }
  const headers = opts.files
    .filter((f) => f.rendered !== false)
    .map((f) => {
      const digest = f.digest ?? digestOf(f.path)
      const header = fill(FILE_HEADER, { digest, path: esc(f.path), viewedButton: viewedButton(f.viewed ?? false, opts.variant), collapsedClass: f.viewed ? ' collapsed' : '', body: f.largeDiff ? LARGE_DIFF_BODY : DIFF_BODY })
      return opts.containers ? `<div id="diff-${digest}" class="Diff-module__diff__x">${header}</div>` : header
    })
    .join('\n')
  const toolbar = fill(TOOLBAR, { viewedCount: String(opts.files.filter((f) => f.viewed).length), total: String(opts.files.length) })
  let embedded = ''
  if (opts.variant === 'broken-json') embedded = `${EMBEDDED_SCRIPT_OPEN}{"payload": {</script>`
  else if (opts.variant !== 'no-embedded') embedded = `${EMBEDDED_SCRIPT_OPEN}${JSON.stringify(embeddedJson(opts)).replace(/</g, '\\u003c')}</script>`
  return `<!doctype html><html><head><title>PR de teste by acme · Pull Request #42 · acme/web</title></head><body class="logged-in">
<react-app app-name="repo" initial-path="${opts.basePath}/files">${embedded}
<div data-target="react-app.reactRoot">${toolbar}<div id="diff-content-parent">${headers}</div></div></react-app></body></html>`
}

const installedDocuments = new WeakSet<Document>()
let toggleEnabled = true

function installToggleSimulation(doc: Document) {
  if (installedDocuments.has(doc)) return
  installedDocuments.add(doc)
  doc.addEventListener('click', (ev) => {
    if (!toggleEnabled) return
    // O chevron do cabeçalho (primeiro botão) só recolhe/expande, sem mexer no Viewed, como na UI nova.
    const chevron = (ev.target as Element).closest('[data-diff-header-wrapper] .d-flex.flex-shrink-0 > button')
    if (chevron) { chevron.closest('.diff-file-header')?.classList.toggle('collapsed'); return }
    const btn = (ev.target as Element).closest('button[aria-label="Viewed"], button[aria-label="Not Viewed"], button[class*="MarkAsViewedButton-module__"]')
    if (!btn || btn.hasAttribute('data-ghra-viewed')) return   // o botão injetado pela extensão cuida do próprio estado
    const wasViewed = btn.getAttribute('aria-pressed') === 'true' || btn.className.includes('MarkAsViewedButton-module__viewed__')
    const now = !wasViewed
    if (btn.hasAttribute('aria-pressed')) { btn.setAttribute('aria-pressed', String(now)); btn.setAttribute('aria-label', now ? 'Viewed' : 'Not Viewed') }
    btn.classList.toggle('MarkAsViewedButton-module__viewed__k8dzo', now)
  })
}

export function mountFilesPage(options: FixtureOptions): Document {
  const html = buildFilesPageHtml(options)
  const basePath = options.basePath ?? '/acme/web/pull/42'
  ;(window as any).happyDOM.setURL(`https://github.com${basePath}/files`)
  document.documentElement.innerHTML = html.replace(/^<!doctype html><html>/, '').replace(/<\/html>$/, '')
  toggleEnabled = options.simulateToggle !== false
  if (toggleEnabled) installToggleSimulation(document)
  return document
}

/**
 * Simula o GitHub trocando o JSON embutido: substitui o nó <script> (dispara childList, como numa navegação real).
 * `mutate` recebe o JSON parseado; se devolver um valor, ele substitui o JSON inteiro.
 */
export function replaceEmbeddedJson(mutate: (json: any) => unknown, doc: Document = document): void {
  const old = doc.querySelector('script[data-target="react-app.embeddedData"]')!
  const json = JSON.parse(old.textContent!)
  const next = mutate(json) ?? json
  const script = doc.createElement('script')
  script.setAttribute('type', 'application/json')
  script.setAttribute('data-target', 'react-app.embeddedData')
  script.textContent = JSON.stringify(next)
  old.replaceWith(script)
}
