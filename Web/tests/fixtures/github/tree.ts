import { digestOf } from './build'

/**
 * The file tree sidebar, in both of GitHub's markups, read from live pages on 2026-10-17 (PR #1032 of a
 * private repository, 30 files). Neither tree is virtualized: every file is in the DOM.
 *
 * New Files UI (Primer TreeView): `#pr-file-tree > ul[role=tree][aria-label="File Tree"]`. Every node is a
 * `li[role=treeitem]` whose `id` is its full path; a directory has `aria-expanded` and a `ul[role=group]`;
 * a file has the class `file-tree-row__<hash>`, `aria-label` = its basename, and a link to `#diff-<digest>`.
 * The tree carries no viewed state and is not re-rendered when a file is marked.
 *
 * Classic UI: `<file-tree data-target="diff-layout.fileTree">` with `li[role=treeitem][data-tree-entry-type]`;
 * a file is `li#file-tree-item-diff-<digest>` with a link to `#diff-<digest>` and, while viewed, an empty
 * `data-file-user-viewed` attribute that GitHub keeps in step with the checkbox.
 */
export interface TreeFile { path: string; digest?: string; viewed?: boolean }

interface Node { name: string; path: string; children: Map<string, Node>; file?: TreeFile }

function buildNodes(files: TreeFile[]): Node {
  const root: Node = { name: '', path: '', children: new Map() }
  for (const f of files) {
    const parts = f.path.split('/')
    let node = root
    parts.forEach((part, i) => {
      const path = parts.slice(0, i + 1).join('/')
      if (!node.children.has(part)) node.children.set(part, { name: part, path, children: new Map() })
      node = node.children.get(part)!
      if (i === parts.length - 1) node.file = f
    })
  }
  return root
}

const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;')

export function primerTreeHtml(files: TreeFile[]): string {
  const render = (node: Node, level: number): string => {
    if (node.file) {
      const digest = node.file.digest ?? digestOf(node.file.path)
      return `<li aria-level="${level}" class="PRIVATE_TreeView-item file-tree-row__nVsQSE prc-TreeView-TreeViewItem-Ter5f" tabindex="-1" id="${esc(node.path)}" role="treeitem" aria-label="${esc(node.name)}" aria-selected="false">
  <div class="PRIVATE_TreeView-item-container prc-TreeView-TreeViewItemContainer-Qg9Ej" style="--level:${level}">
    <div id="c-${esc(node.path)}" class="PRIVATE_TreeView-item-content prc-TreeView-TreeViewItemContent-cG1Vb">
      <div class="PRIVATE_TreeView-item-visual prc-TreeView-TreeViewItemVisual-UrvZQ" aria-hidden="true"><svg class="octicon octicon-file-diff"></svg></div>
      <span class="PRIVATE_TreeView-item-content-text prc-TreeView-TreeViewItemContentText-xA2Ne"><a class="fgColor-default prc-Link-Link-9ZwDx" data-component="Link" href="#diff-${digest}" role="presentation" tabindex="-1">${esc(node.name)}</a></span>
    </div>
  </div>
</li>`
    }
    const children = Array.from(node.children.values()).map((c) => render(c, level + 1)).join('\n')
    return `<li class="PRIVATE_TreeView-item prc-TreeView-TreeViewItem-Ter5f" tabindex="-1" id="${esc(node.path)}" role="treeitem" aria-level="${level}" aria-expanded="true" aria-selected="false">
  <div class="PRIVATE_TreeView-item-container prc-TreeView-TreeViewItemContainer-Qg9Ej" style="--level:${level}">
    <div id="c-${esc(node.path)}" class="PRIVATE_TreeView-item-content prc-TreeView-TreeViewItemContent-cG1Vb"><span class="PRIVATE_TreeView-item-content-text">${esc(node.name)}</span></div>
  </div>
  <ul role="group" class="prc-TreeView-TreeViewSubTree-ifpSH">${children}</ul>
</li>`
  }
  const top = Array.from(buildNodes(files).children.values()).map((c) => render(c, 1)).join('\n')
  return `<div id="pr-file-tree"><div class="FileTreeScrollable__jjz6Or"><ul role="tree" aria-label="File Tree" data-truncate-text="true" class="prc-TreeView-TreeViewRootUlStyles-Mzrmj">${top}</ul></div></div>`
}

export function classicTreeHtml(files: TreeFile[]): string {
  const render = (node: Node, level: number): string => {
    if (node.file) {
      const digest = node.file.digest ?? digestOf(node.file.path)
      return `<li id="file-tree-item-diff-${digest}" class="ActionList-item js-tree-node" role="treeitem" aria-level="${level}" style="--ActionList-tree-depth: ${level};" data-action="click:diff-file-filter#toggleFile" data-target="diff-file-filter.treeEntries" data-file-type=".ts" data-file-deleted="false"${node.file.viewed ? ' data-file-user-viewed=""' : ''} data-tree-entry-type="file">
  <span data-filterable-item-text="" hidden="">${esc(node.file.path)}</span>
  <a class="ActionList-content hx_ActionList-content" href="#diff-${digest}" data-turbo="false" tabindex="-1">
    <span class="ActionList-item-visual ActionList-item-visual--leading"><svg class="octicon octicon-file"></svg></span>
    <span class="ActionList-item-label ActionList-item-label--truncate">${esc(node.name)}</span>
    <span class="ActionList-item-visual ActionList-item-visual--trailing"><svg title="modified" class="octicon octicon-diff-modified"></svg></span>
  </a>
</li>`
    }
    const children = Array.from(node.children.values()).map((c) => render(c, level + 1)).join('\n')
    return `<li class="ActionList-item ActionList-item--hasSubItem" role="treeitem" aria-level="${level}" style="--ActionList-tree-depth: ${level};" data-skip-substring-filter="" data-tree-entry-type="directory">
  <button class="ActionList-content" aria-expanded="true" type="button" tabindex="-1"><span class="ActionList-item-label ActionList-item-label--truncate">${esc(node.name)}</span></button>
  <ul class="ActionList ActionList--subGroup" data-filterable-for="file-tree-filter-field" data-filterable-type="substring" role="group">${children}</ul>
</li>`
  }
  const top = Array.from(buildNodes(files).children.values()).map((c) => render(c, 1)).join('\n')
  return `<file-tree data-target="diff-layout.fileTree" data-catalyst=""><ul role="tree" aria-label="File Tree Navigation" data-filterable-for="file-tree-filter-field" data-filterable-type="substring" class="ActionList ActionList--tree ActionList--full">${top}</ul></file-tree>`
}
