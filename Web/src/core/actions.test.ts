import { markMatching, countMatching, undo } from './actions'
import { ContextMismatch } from './host'
import { FakeHostAdapter } from './testing/fake-host'
import type { ChangedFile, PageContext, Rule, Receipt } from './model'

const ctx: PageContext = { key: '/acme/web/pull/1|abc|', basePath: '/acme/web/pull/1', headOid: 'abc' }
const f = (path: string, o: Partial<ChangedFile> = {}): ChangedFile => ({ path, id: path, viewed: false, hasControl: true, ...o })
const TEST_RULE: Rule = { id: 'unit', label: 'Unit', globs: ['**/*.test.ts'], enabled: true }

describe('markMatching', () => {
  it('marca só os não vistos que casam e registra via dom/api', async () => {
    const host = new FakeHostAdapter({ context: ctx, files: [f('a.test.ts'), f('b.test.ts', { hasControl: false }), f('c.test.ts', { viewed: true }), f('d.ts')] })
    const r = await markMatching(host, [TEST_RULE])
    expect(r.marked.map((m) => [m.file.id, m.via])).toEqual([['a.test.ts', 'dom'], ['b.test.ts', 'api']])
    expect(r.failed).toEqual([])
    expect(r.skipped).toEqual([])
    expect(r.unknown).toEqual([])
    expect(r.stoppedEarly).toBe(false)
    expect(r.context).toEqual(ctx)
    expect(r.completeness).toBe('full')
  })

  it('noop (usuário marcou no meio) fica fora do receipt', async () => {
    const host = new FakeHostAdapter({ context: ctx, files: [f('a.test.ts'), f('b.test.ts')] })
    const original = host.setViewed.bind(host)
    host.setViewed = async (file, v, s) => {
      if (file.id === 'b.test.ts') host.userToggles('b.test.ts')
      return original(file, v, s)
    }
    const r = await markMatching(host, [TEST_RULE])
    expect(r.marked.map((m) => m.file.id)).toEqual(['a.test.ts'])
    expect(r.failed).toEqual([])
  })

  it('respeita concorrência máxima', async () => {
    const files = Array.from({ length: 10 }, (_, i) => f(`${i}.test.ts`))
    const host = new FakeHostAdapter({ context: ctx, files })
    let inFlight = 0,
      peak = 0
    const original = host.setViewed.bind(host)
    host.setViewed = async (file, v, s) => {
      inFlight++
      peak = Math.max(peak, inFlight)
      await new Promise((r) => setTimeout(r, 1))
      inFlight--
      return original(file, v, s)
    }
    await markMatching(host, [TEST_RULE], { concurrency: 4 })
    expect(peak).toBeLessThanOrEqual(4)
  })

  it('para após 3 falhas consecutivas e lista os não tentados em skipped', async () => {
    const files = Array.from({ length: 8 }, (_, i) => f(`${i}.test.ts`))
    const host = new FakeHostAdapter({ context: ctx, files })
    ;['0.test.ts', '1.test.ts', '2.test.ts'].forEach((id) => host.failIds.add(id))
    const r = await markMatching(host, [TEST_RULE], { concurrency: 1 })
    expect(r.failed.map((x) => x.file.id)).toEqual(['0.test.ts', '1.test.ts', '2.test.ts'])
    expect(r.skipped.map((x) => x.id)).toEqual(['3.test.ts', '4.test.ts', '5.test.ts', '6.test.ts', '7.test.ts'])
    expect(r.stoppedEarly).toBe(true)
    expect(r.marked).toEqual([])
  })

  it('falhas não consecutivas não param o lote', async () => {
    const host = new FakeHostAdapter({ context: ctx, files: [f('0.test.ts'), f('1.test.ts'), f('2.test.ts'), f('3.test.ts')] })
    host.failIds.add('0.test.ts')
    host.failIds.add('2.test.ts')
    const r = await markMatching(host, [TEST_RULE], { concurrency: 1 })
    expect(r.failed).toHaveLength(2)
    expect(r.marked).toHaveLength(2)
    expect(r.stoppedEarly).toBe(false)
  })

  it('abort: em voo vira unknown, não iniciado vira skipped', async () => {
    const host = new FakeHostAdapter({ context: ctx, files: [f('0.test.ts'), f('1.test.ts'), f('2.test.ts')] })
    host.hangIds.add('0.test.ts')
    const ac = new AbortController()
    const p = markMatching(host, [TEST_RULE], { concurrency: 1, signal: ac.signal })
    await new Promise((r) => setTimeout(r, 0))
    ac.abort()
    const r = await p
    expect(r.unknown.map((x) => x.id)).toEqual(['0.test.ts'])
    expect(r.skipped.map((x) => x.id)).toEqual(['1.test.ts', '2.test.ts'])
  })

  it('verify: reconcilia marked e unknown e reporta divergências', async () => {
    const host = new FakeHostAdapter({ context: ctx, files: [f('a.test.ts'), f('b.test.ts')] })
    host.optimisticLiars.add('b.test.ts')
    const r = await markMatching(host, [TEST_RULE], { verify: true })
    expect(r.verified).toEqual({ confirmed: 1, diverged: [expect.objectContaining({ id: 'b.test.ts' })] })
  })

  it('verify com reconcile falhando deixa verified ausente', async () => {
    const host = new FakeHostAdapter({ context: ctx, files: [f('a.test.ts')] })
    host.reconcile = async () => {
      throw new Error('rede')
    }
    const r = await markMatching(host, [TEST_RULE], { verify: true })
    expect(r.verified).toBeUndefined()
    expect(r.marked).toHaveLength(1)
  })

  it('reporta progresso por arquivo concluído', async () => {
    const host = new FakeHostAdapter({ context: ctx, files: [f('a.test.ts'), f('b.test.ts'), f('c.ts')] })
    const seen: Array<[number, number]> = []
    await markMatching(host, [TEST_RULE], { concurrency: 1, onProgress: (d, t) => seen.push([d, t]) })
    expect(seen).toEqual([[1, 2], [2, 2]])
  })

  it('contexto muda entre dois arquivos: o seguinte vai para skipped sem chamada', async () => {
    const host = new FakeHostAdapter({ context: ctx, files: [f('a.test.ts'), f('b.test.ts')] })
    const original = host.setViewed.bind(host)
    host.setViewed = async (file, v, s) => {
      const out = await original(file, v, s)
      if (file.id === 'a.test.ts') host.changeContext({ ...ctx, key: 'outro', headOid: 'def' })
      return out
    }
    const r = await markMatching(host, [TEST_RULE], { concurrency: 1 })
    expect(r.marked.map((m) => m.file.id)).toEqual(['a.test.ts'])
    expect(r.skipped.map((x) => x.id)).toEqual(['b.test.ts'])
    expect(host.calls).toEqual([{ id: 'a.test.ts', viewed: true }])
  })

  it('signal já abortado antes do primeiro arquivo: todos em skipped, nenhuma chamada', async () => {
    const host = new FakeHostAdapter({ context: ctx, files: [f('a.test.ts'), f('b.test.ts')] })
    const ac = new AbortController()
    ac.abort()
    const r = await markMatching(host, [TEST_RULE], { signal: ac.signal })
    expect(r.skipped.map((x) => x.id)).toEqual(['a.test.ts', 'b.test.ts'])
    expect(host.calls).toEqual([])
  })

  it('propaga completeness da listagem', async () => {
    const host = new FakeHostAdapter({ context: ctx, files: [f('a.test.ts')], completeness: 'partial' })
    expect((await markMatching(host, [TEST_RULE])).completeness).toBe('partial')
  })
})

describe('countMatching', () => {
  it('conta só não vistos que casam', async () => {
    const host = new FakeHostAdapter({ context: ctx, files: [f('a.test.ts'), f('b.test.ts', { viewed: true }), f('c.ts')] })
    expect(countMatching(await host.listFiles(), [TEST_RULE])).toBe(1)
  })
})

describe('undo', () => {
  it('desmarca só o que está em marked e devolve novo receipt', async () => {
    const host = new FakeHostAdapter({ context: ctx, files: [f('a.test.ts'), f('b.test.ts', { viewed: true })] })
    const first = await markMatching(host, [TEST_RULE])
    const r = await undo(host, first)
    expect(host.calls).toEqual([{ id: 'a.test.ts', viewed: true }, { id: 'a.test.ts', viewed: false }])
    expect(r.marked.map((m) => m.file.id)).toEqual(['a.test.ts'])
    expect(host.server.get('b.test.ts')).toBe(true)
  })

  it('recusa com ContextMismatch quando a página mudou', async () => {
    const host = new FakeHostAdapter({ context: ctx, files: [f('a.test.ts')] })
    const first = await markMatching(host, [TEST_RULE])
    host.changeContext({ ...ctx, key: 'outro', headOid: 'def' })
    await expect(undo(host, first)).rejects.toBeInstanceOf(ContextMismatch)
    expect(host.calls).toHaveLength(1)
  })

  it('contexto muda durante o reconcile do undo: alvos vão para skipped sem chamada', async () => {
    const host = new FakeHostAdapter({ context: ctx, files: [f('a.test.ts', { viewed: true }), f('u.test.ts', { viewed: true })] })
    const receipt: Receipt = { context: ctx, marked: [{ file: f('a.test.ts'), via: 'dom' }], failed: [], unknown: [f('u.test.ts')], skipped: [], stoppedEarly: false, completeness: 'full' }
    const original = host.reconcile.bind(host)
    host.reconcile = async (ids) => {
      const out = await original(ids)
      host.changeContext({ ...ctx, key: 'outro', headOid: 'def' })
      return out
    }
    const r = await undo(host, receipt)
    expect(r.marked).toEqual([])
    expect(r.skipped.map((x) => x.id)).toEqual(['a.test.ts', 'u.test.ts'])
    expect(host.calls).toEqual([])
  })

  it('reconcilia unknown antes: só desfaz os que o servidor diz vistos', async () => {
    const host = new FakeHostAdapter({ context: ctx, files: [f('u1.test.ts', { viewed: true }), f('u2.test.ts')] })
    const receipt: Receipt = { context: ctx, marked: [], failed: [], unknown: [f('u1.test.ts'), f('u2.test.ts')], skipped: [], stoppedEarly: false, completeness: 'full' }
    await undo(host, receipt)
    expect(host.calls).toEqual([{ id: 'u1.test.ts', viewed: false }])
  })
})
