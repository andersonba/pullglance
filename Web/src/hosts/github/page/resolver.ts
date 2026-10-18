import { UnsupportedPage, type FileHeader, type FileHeaderLocator, type FileListSource, type FileTreeSource, type PageReadiness, type Strategy, type StrategyRegistry, type ToolbarSlotSource, type ViewedControl, type ViewedControlLocator } from './concepts'
import type { Diagnostics } from './diagnostics'

type DocConcept = 'fileList' | 'toolbarSlot' | 'fileTree' | 'pageReady'

export class PageResolver {
  private cache = new Map<DocConcept, unknown>()
  private chosen: Record<string, string | null> = {}
  private probes: Record<string, Record<string, boolean>> = {}
  private misses: Record<string, number> = {}

  constructor(private doc: Document, private registry: StrategyRegistry) {}

  private ordered<T>(concept: keyof StrategyRegistry): Strategy<T>[] {
    return [...(this.registry[concept] as Strategy<T>[])].sort((a, b) => b.priority - a.priority)
  }

  private resolveDoc<T>(concept: DocConcept): T {
    if (this.cache.has(concept)) return this.cache.get(concept) as T
    const probes: Record<string, boolean> = {}
    for (const s of this.ordered<T>(concept)) {
      const ok = safe(() => s.probe(this.doc), false)
      probes[s.id] = ok
      if (!ok) continue
      const value = safe(() => s.create(this.doc), null)
      if (value === null) { probes[s.id] = false; continue }
      this.cache.set(concept, value)
      this.chosen[concept] = s.id
      this.probes[concept] = probes
      return value
    }
    this.chosen[concept] = null
    this.probes[concept] = probes
    throw new UnsupportedPage(concept)
  }

  private *instances<T>(concept: 'fileHeader' | 'viewedControl'): Generator<[Strategy<T>, T]> {
    const probes = (this.probes[concept] ??= {})
    for (const s of this.ordered<T>(concept)) {
      const ok = safe(() => s.probe(this.doc), false)
      probes[s.id] = ok
      if (!ok) continue
      const value = safe(() => s.create(this.doc), null)
      if (value === null) { probes[s.id] = false; continue }
      yield [s, value]
    }
  }

  private miss(concept: string) { this.misses[concept] = (this.misses[concept] ?? 0) + 1 }

  fileList(): FileListSource { return this.resolveDoc<FileListSource>('fileList') }
  toolbarSlot(): ToolbarSlotSource { return this.resolveDoc<ToolbarSlotSource>('toolbarSlot') }
  fileTree(): FileTreeSource { return this.resolveDoc<FileTreeSource>('fileTree') }
  pageReady(): PageReadiness { return this.resolveDoc<PageReadiness>('pageReady') }

  headerById(id: string): FileHeader | null {
    for (const [s, loc] of this.instances<FileHeaderLocator>('fileHeader')) {
      const h = safe(() => loc.byId(id), null)
      if (h) { this.chosen.fileHeader = s.id; return h }
    }
    this.miss('fileHeader')
    return null
  }

  headers(): FileHeader[] {
    for (const [s, loc] of this.instances<FileHeaderLocator>('fileHeader')) {
      const all = safe(() => loc.all(), [])
      if (all.length > 0) { this.chosen.fileHeader = s.id; return all }
    }
    return []
  }

  viewedControl(header: Element): ViewedControl | null {
    for (const [s, loc] of this.instances<ViewedControlLocator>('viewedControl')) {
      const c = safe(() => loc.inHeader(header), null)
      if (c) { this.chosen.viewedControl = s.id; return c }
    }
    this.miss('viewedControl')
    return null
  }

  /** Esquece a escolha de um conceito de documento (ex.: re-probar a toolbar quando o GitHub re-renderiza). */
  invalidateConcept(concept: DocConcept) { this.cache.delete(concept); delete this.chosen[concept]; delete this.probes[concept] }

  invalidate() { this.cache.clear(); this.chosen = {}; this.probes = {}; this.misses = {} }

  diagnostics(): Diagnostics {
    return { url: this.doc.location?.href ?? '', chosen: { ...this.chosen }, probes: structuredClone(this.probes), misses: { ...this.misses } }
  }
}

function safe<T>(fn: () => T, fallback: T): T {
  try { return fn() } catch { return fallback }
}
