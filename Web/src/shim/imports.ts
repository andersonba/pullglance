type Area = 'local' | 'session' | 'sync'
type Key = `${Area}:${string}`

interface StorageBridge { (body: Record<string, unknown>): Promise<unknown> }

const memory: Record<Area, Record<string, unknown>> = { local: {}, session: {}, sync: {} }

const bridge: StorageBridge = (body) => {
  const handler = (globalThis as any).webkit?.messageHandlers?.reviewStorage
  if (handler) return handler.postMessage(body)
  // Tests and plain pages: in-memory areas with the same change-set contract.
  const area = memory[body.area as Area]
  const before = { ...area }
  switch (body.op) {
    case 'get': return Promise.resolve({ ...area })
    case 'set': Object.assign(area, body.items as object); break
    case 'remove': for (const k of body.keys as string[]) delete area[k]; break
    case 'clear': for (const k of Object.keys(area)) delete area[k]; break
  }
  const changes: Record<string, { oldValue?: unknown; newValue?: unknown }> = {}
  for (const k of new Set([...Object.keys(before), ...Object.keys(area)])) {
    if (JSON.stringify(before[k]) === JSON.stringify(area[k])) continue
    changes[k] = { ...(k in before ? { oldValue: before[k] } : {}), ...(k in area ? { newValue: area[k] } : {}) }
  }
  return Promise.resolve(changes)
}

const split = (key: Key): { area: Area; name: string } => {
  const i = key.indexOf(':')
  return { area: key.slice(0, i) as Area, name: key.slice(i + 1) }
}

export const storage = {
  async getItem<T>(key: Key): Promise<T | null> {
    const { area, name } = split(key)
    const all = (await bridge({ area, op: 'get' })) as Record<string, unknown>
    return (all[name] as T | undefined) ?? null
  },
  async setItem<T>(key: Key, value: T): Promise<void> {
    const { area, name } = split(key)
    await bridge({ area, op: 'set', items: { [name]: value } })
  },
  async removeItem(key: Key): Promise<void> {
    const { area, name } = split(key)
    await bridge({ area, op: 'remove', keys: [name] })
  },
  async snapshot(area: Area): Promise<Record<string, unknown>> {
    return (await bridge({ area, op: 'get' })) as Record<string, unknown>
  },
  /** Only tests call this. */
  _resetForTests() { for (const a of Object.keys(memory) as Area[]) memory[a] = {} },
}
