export class BusyError extends Error {
  constructor() { super('An operation is already running'); this.name = 'BusyError' }
}

const noop = () => {}

export class OperationLock {
  private current: AbortController | null = null
  private settled: Promise<void> = Promise.resolve()

  get busy() { return this.current !== null }

  async run<T>(fn: (signal: AbortSignal) => Promise<T>): Promise<T> {
    if (this.current) throw new BusyError()
    const controller = new AbortController()
    this.current = controller
    const op = (async () => {
      try {
        return await fn(controller.signal)
      } finally {
        if (this.current === controller) this.current = null
      }
    })()
    this.settled = op.then(noop, noop)
    return op
  }

  /** Resolve quando não houver operação em andamento (sucesso ou falha). */
  whenIdle(): Promise<void> { return this.busy ? this.settled : Promise.resolve() }

  cancel() { this.current?.abort() }
}
