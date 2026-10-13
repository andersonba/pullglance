import { OperationLock, BusyError } from './lock'

describe('OperationLock', () => {
  it('executa uma operação por vez e expõe busy', async () => {
    const lock = new OperationLock()
    let release!: () => void
    const p = lock.run(() => new Promise<void>((r) => { release = r }))
    expect(lock.busy).toBe(true)
    await expect(lock.run(async () => 1)).rejects.toBeInstanceOf(BusyError)
    release(); await p
    expect(lock.busy).toBe(false)
    expect(await lock.run(async () => 2)).toBe(2)
  })

  it('cancel aborta o signal da operação atual', async () => {
    const lock = new OperationLock()
    let seen: AbortSignal | undefined
    const p = lock.run((signal) => new Promise<void>((r) => { seen = signal; signal.addEventListener('abort', () => r()) }))
    lock.cancel()
    await p
    expect(seen?.aborted).toBe(true)
  })

  it('libera o lock mesmo quando a operação lança', async () => {
    const lock = new OperationLock()
    await expect(lock.run(async () => { throw new Error('x') })).rejects.toThrow('x')
    expect(lock.busy).toBe(false)
  })

  it('whenIdle resolve na hora sem operação e, com operação, quando ela termina (sucesso ou falha)', async () => {
    const lock = new OperationLock()
    await lock.whenIdle()

    let release!: () => void
    const ok = lock.run(() => new Promise<void>((r) => { release = r }))
    let idle = false
    const waiting = lock.whenIdle().then(() => { idle = true })
    await Promise.resolve()
    expect(idle).toBe(false)
    release(); await ok; await waiting
    expect(idle).toBe(true)

    let fail!: (e: Error) => void
    const bad = lock.run(() => new Promise<void>((_, rej) => { fail = rej }))
    const waitingBad = lock.whenIdle()
    fail(new Error('x'))
    await expect(bad).rejects.toThrow('x')
    await expect(waitingBad).resolves.toBeUndefined()
    expect(lock.busy).toBe(false)
  })
})
