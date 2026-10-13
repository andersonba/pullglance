import { CompareMemory, compareMemoryKey, type CompareMemoryEntry, type CompareMemoryStore } from './compare-memory'

function memStore() {
  const data = new Map<string, CompareMemoryEntry>()
  const ops: string[] = []
  const store: CompareMemoryStore = {
    get: async (k) => { ops.push(`get ${k}`); return data.get(k) ?? null },
    set: async (k, e) => { ops.push(`set ${k}`); data.set(k, e) },
    remove: async (k) => { ops.push(`remove ${k}`); data.delete(k) },
    keys: async () => [...data.keys()],
  }
  return { store, data, ops }
}
const BP = '/acme/web/compare/main...feat/x'
const KEY = compareMemoryKey(BP)

describe('CompareMemory', () => {
  beforeEach(() => vi.useFakeTimers())
  afterEach(() => vi.useRealTimers())

  it('load devolve vazio sem entrada e os ids quando existe', async () => {
    const { store, data } = memStore()
    const m = new CompareMemory({ store })
    expect(await m.load(BP)).toEqual(new Set())
    data.set(KEY, { viewed: ['a', 'b'], updatedAt: 1 })
    expect(await m.load(BP)).toEqual(new Set(['a', 'b']))
  })

  it('remember grava com debounce, uma vez por rajada, só o último conjunto', async () => {
    const { store, data, ops } = memStore()
    const m = new CompareMemory({ store, writeDelayMs: 300, now: () => 42 })
    m.remember(BP, new Set(['a']))
    m.remember(BP, new Set(['a', 'b']))
    expect(ops.filter((o) => o.startsWith('set'))).toHaveLength(0)
    await vi.advanceTimersByTimeAsync(300)
    expect(ops.filter((o) => o.startsWith('set'))).toHaveLength(1)
    expect(data.get(KEY)).toEqual({ viewed: ['a', 'b'], updatedAt: 42 })
  })

  it('com a listagem presente, mantém os ids dos arquivos que não estão na página', async () => {
    const { store, data } = memStore()
    data.set(KEY, { viewed: ['a', 'b', 'c'], updatedAt: 1 })
    const m = new CompareMemory({ store, writeDelayMs: 0, now: () => 42 })
    await m.load(BP)
    // Só b e d carregaram: b foi desmarcado, d marcado; a e c não estão na página e continuam vistos.
    m.remember(BP, new Set(['d']), new Set(['b', 'd']))
    await vi.advanceTimersByTimeAsync(0)
    expect(data.get(KEY)).toEqual({ viewed: ['a', 'c', 'd'], updatedAt: 42 })
  })

  it('marcações em listagens parciais sucessivas se acumulam em vez de se sobrescrever', async () => {
    const { store, data } = memStore()
    const m = new CompareMemory({ store, writeDelayMs: 0, now: () => 42 })
    m.remember(BP, new Set(['a']), new Set(['a']))
    m.remember(BP, new Set(['b']), new Set(['b']))
    await vi.advanceTimersByTimeAsync(0)
    expect(data.get(KEY)).toEqual({ viewed: ['a', 'b'], updatedAt: 42 })
  })

  it('não grava o que não mudou; conjunto vazio apaga a entrada', async () => {
    const { store, data, ops } = memStore()
    const m = new CompareMemory({ store, writeDelayMs: 10 })
    m.remember(BP, new Set(['a'])); await vi.advanceTimersByTimeAsync(10)
    m.remember(BP, new Set(['a'])); await vi.advanceTimersByTimeAsync(10)
    expect(ops.filter((o) => o.startsWith('set'))).toHaveLength(1)
    m.remember(BP, new Set()); await vi.advanceTimersByTimeAsync(10)
    expect(data.has(KEY)).toBe(false)
  })

  it('load registra o estado conhecido: lembrar o mesmo conjunto depois do load não grava', async () => {
    const { store, data, ops } = memStore()
    data.set(KEY, { viewed: ['a'], updatedAt: 1 })
    const m = new CompareMemory({ store, writeDelayMs: 10 })
    await m.load(BP)
    m.remember(BP, new Set(['a'])); await vi.advanceTimersByTimeAsync(10)
    expect(ops.filter((o) => o.startsWith('set'))).toHaveLength(0)
  })

  it('flush grava o pendente imediatamente', async () => {
    const { store, data } = memStore()
    const m = new CompareMemory({ store, writeDelayMs: 1000 })
    m.remember(BP, new Set(['z']))
    await m.flush()
    expect(data.get(KEY)?.viewed).toEqual(['z'])
  })

  it('prune apaga entradas velhas, vazias e além do limite, mantendo as mais recentes', async () => {
    const { store, data } = memStore()
    const day = 24 * 60 * 60 * 1000
    const now = 100 * day
    data.set('local:ghra:compare:/a/b/compare/old', { viewed: ['x'], updatedAt: now - 31 * day })
    data.set('local:ghra:compare:/a/b/compare/empty', { viewed: [], updatedAt: now })
    data.set('local:ghra:compare:/a/b/compare/r1', { viewed: ['x'], updatedAt: now - 3 * day })
    data.set('local:ghra:compare:/a/b/compare/r2', { viewed: ['x'], updatedAt: now - 2 * day })
    data.set('local:ghra:compare:/a/b/compare/r3', { viewed: ['x'], updatedAt: now - 1 * day })
    const m = new CompareMemory({ store, now: () => now, maxAgeMs: 30 * day, maxEntries: 2 })
    await m.prune()
    expect([...data.keys()].sort()).toEqual(['local:ghra:compare:/a/b/compare/r2', 'local:ghra:compare:/a/b/compare/r3'])
  })

  it('storage quebrado não lança: load vazio, remember e prune silenciosos', async () => {
    const broken: CompareMemoryStore = { get: async () => { throw new Error('x') }, set: async () => { throw new Error('x') }, remove: async () => { throw new Error('x') }, keys: async () => { throw new Error('x') } }
    const m = new CompareMemory({ store: broken, writeDelayMs: 1 })
    expect(await m.load(BP)).toEqual(new Set())
    m.remember(BP, new Set(['a'])); await vi.advanceTimersByTimeAsync(1)
    await expect(m.prune()).resolves.toBeUndefined()
  })
})
