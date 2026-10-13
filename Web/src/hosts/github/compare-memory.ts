import { storage } from '#imports'

/**
 * Estado "visto" por página de compare, persistido em storage.local (o sync tem cota de 8 KB por item).
 * Hoje, no compare, visto = colapsado; quando houver o checkbox próprio, a mesma estrutura guarda o check.
 * Uma chave por compare (owner/repo + range), com os digests de caminho dos arquivos e a data da última escrita.
 */
export interface CompareMemoryEntry { viewed: string[]; updatedAt: number }
export interface CompareMemoryStore {
  get(key: string): Promise<CompareMemoryEntry | null>
  set(key: string, entry: CompareMemoryEntry): Promise<void>
  remove(key: string): Promise<void>
  keys(): Promise<string[]>
}
export interface CompareMemoryOptions {
  store?: CompareMemoryStore
  now?: () => number
  writeDelayMs?: number   // debounce das escritas; default 300
  maxAgeMs?: number       // entradas mais velhas são apagadas na limpeza; default 30 dias
  maxEntries?: number     // limite de compares lembrados (os mais antigos saem); default 100
}

const PREFIX = 'local:ghra:compare:'
export const compareMemoryKey = (basePath: string) => `${PREFIX}${basePath}`

/** Store padrão sobre o wrapper de storage do WXT (funciona em memória nos testes via fake-browser). */
export function wxtCompareMemoryStore(): CompareMemoryStore {
  return {
    get: (key) => storage.getItem<CompareMemoryEntry>(key as `local:${string}`),
    set: (key, entry) => storage.setItem(key as `local:${string}`, entry),
    remove: (key) => storage.removeItem(key as `local:${string}`),
    keys: async () => Object.keys(await storage.snapshot('local')).filter((k) => k.startsWith('ghra:compare:')).map((k) => `local:${k}`),
  }
}

export class CompareMemory {
  private store: CompareMemoryStore
  private now: () => number
  private writeDelayMs: number
  private maxAgeMs: number
  private maxEntries: number
  private pending = new Map<string, { ids: Set<string>; timer: ReturnType<typeof setTimeout> }>()
  private last = new Map<string, string>()   // última escrita por chave (ids ordenados), para não gravar o que não mudou
  private known = new Map<string, Set<string>>()   // último conjunto completo conhecido por chave (carregado ou mesclado)

  constructor(opts: CompareMemoryOptions = {}) {
    this.store = opts.store ?? wxtCompareMemoryStore()
    this.now = opts.now ?? Date.now
    this.writeDelayMs = opts.writeDelayMs ?? 300
    this.maxAgeMs = opts.maxAgeMs ?? 30 * 24 * 60 * 60 * 1000
    this.maxEntries = opts.maxEntries ?? 100
  }

  async load(basePath: string): Promise<Set<string>> {
    try {
      const entry = await this.store.get(compareMemoryKey(basePath))
      const ids = new Set(Array.isArray(entry?.viewed) ? entry.viewed.filter((x): x is string => typeof x === 'string') : [])
      this.last.set(basePath, serialize(ids))
      this.known.set(basePath, new Set(ids))
      return ids
    } catch {
      return new Set()
    }
  }

  /**
   * Espelha o estado atual; grava com debounce e só se mudou. Conjunto vazio apaga a entrada.
   * `present` são os arquivos que estão na página agora: com carregamento progressivo ou virtualização
   * a listagem é parcial, e só esses podem mudar de estado; os demais mantêm o que estava lembrado.
   */
  remember(basePath: string, ids: ReadonlySet<string>, present?: ReadonlySet<string>): void {
    const base = this.known.get(basePath) ?? new Set<string>()
    const snapshot = present ? new Set([...[...base].filter((id) => !present.has(id)), ...ids]) : new Set(ids)
    this.known.set(basePath, new Set(snapshot))
    const serialized = serialize(snapshot)
    if (this.last.get(basePath) === serialized && !this.pending.has(basePath)) return
    const existing = this.pending.get(basePath)
    if (existing) clearTimeout(existing.timer)
    const timer = setTimeout(() => { void this.flushKey(basePath) }, this.writeDelayMs)
    this.pending.set(basePath, { ids: snapshot, timer })
  }

  /** Grava tudo que está pendente agora (unload/testes). */
  async flush(): Promise<void> {
    await Promise.all([...this.pending.keys()].map((k) => this.flushKey(k)))
  }

  /** Apaga entradas velhas e mantém no máximo `maxEntries`, as mais recentes. Uma leitura do storage. */
  async prune(): Promise<void> {
    try {
      const keys = await this.store.keys()
      const entries = await Promise.all(keys.map(async (key) => ({ key, entry: await this.store.get(key) })))
      const cutoff = this.now() - this.maxAgeMs
      const alive = entries
        .filter(({ entry }) => entry && typeof entry.updatedAt === 'number' && entry.updatedAt >= cutoff && entry.viewed.length > 0)
        .sort((a, b) => b.entry!.updatedAt - a.entry!.updatedAt)
      const keep = new Set(alive.slice(0, this.maxEntries).map((e) => e.key))
      await Promise.all(entries.filter((e) => !keep.has(e.key)).map((e) => this.store.remove(e.key)))
    } catch {
      /* limpeza é melhor esforço */
    }
  }

  private async flushKey(basePath: string): Promise<void> {
    const item = this.pending.get(basePath)
    if (!item) return
    clearTimeout(item.timer)
    this.pending.delete(basePath)
    const serialized = serialize(item.ids)
    if (this.last.get(basePath) === serialized) return
    try {
      if (item.ids.size === 0) await this.store.remove(compareMemoryKey(basePath))
      else await this.store.set(compareMemoryKey(basePath), { viewed: [...item.ids].sort(), updatedAt: this.now() })
      this.last.set(basePath, serialized)
    } catch {
      /* storage indisponível: o estado continua na página */
    }
  }
}

const serialize = (ids: ReadonlySet<string>) => [...ids].sort().join(',')
