import type { Completeness } from '@/core/model'

export interface Strategy<T> {
  id: string
  priority: number
  probe(doc: Document): boolean
  create(doc: Document): T
}

export interface PageFile {
  id: string
  path: string
  viewed: boolean
}

export interface FileListSource {
  list(): { files: PageFile[]; completeness: Completeness }
  /** elemento que, ao entrar na viewport, faz a página carregar mais arquivos (carregamento progressivo); null se nada pendente */
  pendingLoader?(): Element | null
}

export interface FileHeader {
  id: string
  path: string
  el: Element
  /** onde o selo deve ser inserido (ex.: ao lado do caminho); default: o próprio cabeçalho */
  labelSlot?: Element
}

export interface FileHeaderLocator {
  byId(id: string): FileHeader | null
  all(): FileHeader[]
}

export interface ViewedControl {
  el: Element
  isViewed(): boolean
  toggle(): void
}

export interface ViewedControlLocator {
  inHeader(header: Element): ViewedControl | null
}

export interface ToolbarSlotSource {
  find(): Element | null
  /** onde o nosso controle entra em relação ao slot: dentro ('first'/'last') ou como irmão ('after'); default 'last' */
  placement?: 'first' | 'last' | 'after'
  /** marca o host do shadow root (atributo data-ghra-host) para o CSS da UI posicioná-lo; ex.: 'float-right' */
  hostFlag?: string
}

export interface StrategyRegistry {
  fileList: Strategy<FileListSource>[]
  fileHeader: Strategy<FileHeaderLocator>[]
  viewedControl: Strategy<ViewedControlLocator>[]
  toolbarSlot: Strategy<ToolbarSlotSource>[]
}

export class UnsupportedPage extends Error {
  constructor(public concept: keyof StrategyRegistry) {
    super(`Unsupported concept on this page: ${concept}`)
    this.name = 'UnsupportedPage'
  }
}
