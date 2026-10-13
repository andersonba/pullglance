import { AbortedInFlight, ContextMismatch, type HostAdapter } from './host'
import { matchFiles } from './matcher'
import type { ChangedFile, FileListing, Receipt, Rule } from './model'

export interface MarkOptions {
  signal?: AbortSignal
  verify?: boolean
  concurrency?: number
  maxConsecutiveFailures?: number
  onProgress?: (done: number, total: number) => void
}

export function countMatching(listing: FileListing, rules: Rule[]): number {
  return matchFiles(listing.files.filter((f) => !f.viewed), rules).length
}

interface BatchResult {
  marked: Receipt['marked']
  failed: Receipt['failed']
  unknown: ChangedFile[]
  skipped: ChangedFile[]
  stoppedEarly: boolean
}

async function runBatch(
  adapter: HostAdapter,
  files: ChangedFile[],
  viewed: boolean,
  expectedKey: string,
  opts: MarkOptions,
): Promise<BatchResult> {
  const concurrency = Math.max(1, opts.concurrency ?? 4)
  const maxFailures = opts.maxConsecutiveFailures ?? 3
  const result: BatchResult = { marked: [], failed: [], unknown: [], skipped: [], stoppedEarly: false }
  const queue = [...files]
  let consecutiveFailures = 0
  let done = 0
  let stop = false
  const progress = () => opts.onProgress?.(++done, files.length)

  const worker = async () => {
    while (queue.length > 0) {
      // Abortado ou página trocada: o arquivo fica na fila e sai como skipped (nunca marca no PR errado).
      if (stop || opts.signal?.aborted || adapter.currentContext()?.key !== expectedKey) return
      const file = queue.shift()!
      try {
        const via = await adapter.setViewed(file, viewed, opts.signal)
        consecutiveFailures = 0
        if (via !== 'noop') result.marked.push({ file, via })
        progress()
      } catch (error) {
        if (error instanceof AbortedInFlight) {
          result.unknown.push(file)
          return
        }
        result.failed.push({ file, error: error instanceof Error ? error.message : String(error) })
        progress()
        if (++consecutiveFailures >= maxFailures) {
          stop = true
          result.stoppedEarly = true
          return
        }
      }
    }
  }

  await Promise.all(Array.from({ length: concurrency }, worker))
  result.skipped = queue
  return result
}

async function verify(adapter: HostAdapter, receipt: Receipt): Promise<void> {
  const candidates = [...receipt.marked.map((m) => m.file), ...receipt.unknown]
  if (candidates.length === 0) return
  try {
    const server = await adapter.reconcile(candidates.map((f) => f.id))
    const diverged = candidates.filter((f) => server.get(f.id) !== true)
    receipt.verified = { confirmed: candidates.length - diverged.length, diverged }
  } catch {
    receipt.verified = undefined
  }
}

export async function markMatching(adapter: HostAdapter, rules: Rule[], opts: MarkOptions = {}): Promise<Receipt> {
  const listing = await adapter.listFiles()
  const targets = matchFiles(listing.files.filter((f) => !f.viewed), rules).map((m) => m.file)
  const batch = await runBatch(adapter, targets, true, listing.context.key, opts)
  const receipt: Receipt = { context: listing.context, completeness: listing.completeness, ...batch }
  if (opts.verify) await verify(adapter, receipt)
  return receipt
}

export async function undo(adapter: HostAdapter, receipt: Receipt, opts: { signal?: AbortSignal } = {}): Promise<Receipt> {
  const current = adapter.currentContext()
  if (!current || current.key !== receipt.context.key) throw new ContextMismatch()

  let targets = receipt.marked.map((m) => m.file)
  if (receipt.unknown.length > 0) {
    const server = await adapter.reconcile(receipt.unknown.map((f) => f.id))
    targets = [...targets, ...receipt.unknown.filter((f) => server.get(f.id) === true)]
  }
  const asViewed = targets.map((f) => ({ ...f, viewed: true }))
  const batch = await runBatch(adapter, asViewed, false, receipt.context.key, { signal: opts.signal })
  return { context: receipt.context, completeness: receipt.completeness, ...batch }
}

export function loadAll(adapter: HostAdapter, onProgress?: (done: number, total?: number) => void, signal?: AbortSignal) {
  return adapter.loadAll(onProgress, signal)
}
