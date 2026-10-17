import { digestOf } from './build'
import { classicTreeHtml } from './tree'

/**
 * Fixture da página de compare (UI clássica, Rails). Fragmentos copiados de um compare público em 2026-10-09:
 * cada arquivo é `.js-file.js-details-container` com `.file-header[data-path][data-anchor]`, o chevron
 * `button.js-details-target[aria-expanded]` alterna as classes `open`/`Details--on`, e a barra é o `#toc`.
 */
export interface CompareFile { path: string; collapsed?: boolean; loadDiff?: boolean; digest?: string; viewed?: boolean }
export interface CompareOptions {
  files: CompareFile[]
  owner?: string
  repo?: string
  range?: string            // default 'main...feat/x'
  pendingPage?: boolean     // simula carregamento progressivo (compare com mais de 300 arquivos)
  simulateToggle?: boolean  // default true
  /** A página clássica de arquivos do PR: o GitHub põe o checkbox "Viewed" nativo em `.file-actions`. */
  nativeViewed?: boolean
  /** A árvore lateral da página clássica de arquivos do PR (`<file-tree>`); compare ao vivo não tem. */
  tree?: boolean
}

const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;')

function fileHtml(f: CompareFile, nativeViewed = false): string {
  const digest = f.digest ?? digestOf(f.path)
  const expanded = !f.collapsed
  const body = f.loadDiff
    ? `<div class="data highlight empty"><button data-disable-with="Loading…" type="button" class="load-diff-button no-underline js-diff-load Button--link Button--medium Button f4"><span class="Button-content"><span class="Button-label"><div class="text-bold f4 js-button-text">Load diff</div></span></span></button><p>Large diffs are not rendered by default.</p></div>`
    : `<div class="data highlight js-blob-wrapper"><table class="diff-table"><tbody><tr><td>+ linha</td></tr></tbody></table></div>`
  return `
<div id="diff-${digest}" data-details-container-group="file" class="file js-file js-details-container js-targetable-element show-inline-notes Details ${expanded ? 'Details--on open' : ''}" data-file-type=".ts" data-file-deleted="false" data-tagsearch-path="${esc(f.path)}" data-targets="diff-file-filter.diffEntries">
  <div class="file-header d-flex flex-md-row flex-column flex-md-items-center file-header--expandable js-file-header js-skip-tagsearch sticky-file-header" data-path="${esc(f.path)}" data-short-path="${digest.slice(0, 7)}" data-anchor="diff-${digest}" data-file-type=".ts" data-file-deleted="false">
    <div class="file-info flex-auto min-width-0 mb-md-0 mb-2">
      <button type="button" class="btn-octicon js-details-target" aria-label="Toggle diff contents" aria-expanded="${expanded}" style="width: 22px;"><svg aria-hidden="true"></svg></button>
      <span class="sr-only">2 changes: 1 addition &amp; 1 deletion</span>
      <span class="diffstat" aria-hidden="true">2</span>
      <span class="Truncate"><a title="${esc(f.path)}" class="Link--primary Truncate-text" href="#diff-${digest}">${esc(f.path)}</a></span>
    </div>
    <div class="file-actions pt-0 mb-md-0 mb-2 pr-md-0 pr-1 flex-shrink-0">${nativeViewed ? `<div class="d-flex flex-justify-end"><div class="js-replace-file-header-review d-flex"><form class="js-toggle-user-reviewed-file-form d-flex flex-items-stretch" data-autosubmit="true"><input type="hidden" name="_method" value="put"><label class="js-reviewed-toggle ml-2 mr-1"><input type="checkbox" class="mr-1 js-reviewed-checkbox" name="viewed"${f.viewed ? ' checked' : ''}> Viewed</label></form></div></div>` : ''}<button type="button" class="btn-link">View file</button></div>
  </div>
  <div class="js-file-content Details-content--hidden position-relative">${body}</div>
</div>`
}

export function comparePathOf(opts: CompareOptions): string {
  return `/${opts.owner ?? 'acme'}/${opts.repo ?? 'web'}/compare/${opts.range ?? 'main...feat/x'}`
}

export function buildComparePageHtml(opts: CompareOptions): string {
  const basePath = comparePathOf(opts)
  const pending = opts.pendingPage
    ? `<div class="js-diff-progressive-container"><include-fragment aria-label="Loading Files" src="${basePath.replace(/\/compare\/.*/, '/compare/file-list')}?range=x&amp;start_entry=300"></include-fragment></div>`
    : ''
  return `<!doctype html><html><head><title>Comparing ${esc(opts.range ?? 'main...feat/x')} · acme/web</title></head><body class="logged-in env-production">
<div class="repository-content">
  <div class="range-editor"><span>base: main</span></div>
  <div id="toc" class="details-collapse table-of-contents js-details-container Details flex-1">
    <div class="d-flex d-inline-block float-right"><segmented-control><ul aria-label="Diff view" role="list" class="SegmentedControl--small SegmentedControl"><li class="SegmentedControl-item"><button type="button" class="Button--invisible Button--small Button">Split</button></li><li class="SegmentedControl-item"><button type="button" class="Button--invisible Button--small Button">Unified</button></li></ul></segmented-control></div>
    <div class="toc-diff-stats">Showing <strong>${opts.files.length} changed files</strong> with <strong>10 additions</strong> and <strong>2 deletions</strong>.</div>
  </div>
  <div id="files_bucket" class="files-bucket">
    ${opts.tree ? `<diff-layout><div class="Layout-sidebar">${classicTreeHtml(opts.files)}</div></diff-layout>` : ''}
    <div id="files" class="diff-view js-diff-container">${opts.files.map((f) => fileHtml(f, opts.nativeViewed === true)).join('\n')}${pending}</div>
  </div>
</div></body></html>`
}

let toggleEnabled = true
const installed = new WeakSet<Document>()
function installToggleSimulation(doc: Document) {
  if (installed.has(doc)) return
  installed.add(doc)
  doc.addEventListener('click', (ev) => {
    if (!toggleEnabled) return
    const btn = (ev.target as Element).closest('button.js-details-target')
    if (!btn) return
    const container = btn.closest('.js-details-container')
    const expanded = btn.getAttribute('aria-expanded') !== 'true'
    btn.setAttribute('aria-expanded', String(expanded))
    container?.classList.toggle('open', expanded)
    container?.classList.toggle('Details--on', expanded)
  })
}

export function mountComparePage(opts: CompareOptions): Document {
  const html = buildComparePageHtml(opts)
  ;(window as any).happyDOM.setURL(`https://github.com${comparePathOf(opts)}`)
  document.documentElement.innerHTML = html.replace(/^<!doctype html><html>/, '').replace(/<\/html>$/, '')
  toggleEnabled = opts.simulateToggle !== false
  installToggleSimulation(document)
  return document
}
