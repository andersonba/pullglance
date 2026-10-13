import { CompareMemory, compareMemoryKey, wxtCompareMemoryStore } from './compare-memory'
import { storage } from '#imports'

describe('wxtCompareMemoryStore (storage.local via fake-browser)', () => {
  it('round-trip e listagem de chaves com o prefixo', async () => {
    const m = new CompareMemory({ store: wxtCompareMemoryStore(), writeDelayMs: 0 })
    m.remember('/acme/web/compare/a...b', new Set(['d1']))
    await m.flush()
    expect(await storage.getItem(compareMemoryKey('/acme/web/compare/a...b') as `local:${string}`)).toMatchObject({ viewed: ['d1'] })
    await storage.setItem('local:other', { x: 1 })
    expect(await wxtCompareMemoryStore().keys()).toEqual([compareMemoryKey('/acme/web/compare/a...b')])
    expect(await m.load('/acme/web/compare/a...b')).toEqual(new Set(['d1']))
  })
})
