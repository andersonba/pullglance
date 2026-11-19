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

/**
 * What the page showed is not what the server has: GitHub flips a Viewed button before its request answers,
 * and a refused request (a 429 when marks come too fast, seen live 2026-11-18) leaves the page saying
 * viewed over a server that never took it. So the batch is checked against the server, and a file the
 * server does not have in the wanted state is written there directly, where the answer is per file. One
 * that still does not go through leaves `marked` for `failed`: the count is what was saved.
 * When the check itself cannot be made, `verified` stays absent and the receipt is the page's word.
 */
async function verify(adapter: HostAdapter, receipt: Receipt, viewed: boolean, opts: MarkOptions): Promise<void> {
  const candidates = [...receipt.marked.map((m) => m.file), ...receipt.unknown]
  if (candidates.length === 0) return
  let server: Map<string, boolean>
  try {
    server = await adapter.reconcile(candidates.map((f) => f.id))
  } catch {
    receipt.verified = undefined
    return
  }
  const diverged = candidates.filter((f) => server.get(f.id) !== viewed)
  receipt.verified = { confirmed: candidates.length - diverged.length, diverged: [] }
  if (diverged.length === 0) return
  const lost = new Map<string, string>()
  const queue = [...diverged]
  let done = receipt.verified.confirmed
  let consecutive = 0
  const worker = async () => {
    while (queue.length > 0) {
      const file = queue.shift()!
      // The server keeps refusing: the rest would only wait their turn to be refused too.
      if (!adapter.saveViewed || opts.signal?.aborted || consecutive >= (opts.maxConsecutiveFailures ?? 3)) { lost.set(file.id, 'not saved on the server'); continue }
      try {
        await adapter.saveViewed(file, viewed, opts.signal)
        consecutive = 0
        receipt.verified!.confirmed++
      } catch (error) {
        consecutive++
        lost.set(file.id, error instanceof Error ? error.message : String(error))
      }
      opts.onProgress?.(++done, candidates.length)
    }
  }
  opts.onProgress?.(done, candidates.length)
  await Promise.all(Array.from({ length: Math.max(1, opts.concurrency ?? 4) }, worker))
  if (lost.size === 0) return
  receipt.verified.diverged = diverged.filter((f) => lost.has(f.id))
  receipt.failed.push(...receipt.verified.diverged.map((file) => ({ file, error: lost.get(file.id)! })))
  receipt.marked = receipt.marked.filter((m) => !lost.has(m.file.id))
  receipt.unknown = receipt.unknown.filter((f) => !lost.has(f.id))
}

export async function markMatching(adapter: HostAdapter, rules: Rule[], opts: MarkOptions = {}): Promise<Receipt> {
  const listing = await adapter.listFiles()
  const targets = matchFiles(listing.files.filter((f) => !f.viewed), rules).map((m) => m.file)
  const batch = await runBatch(adapter, targets, true, listing.context.key, opts)
  const receipt: Receipt = { context: listing.context, completeness: listing.completeness, ...batch }
  if (opts.verify) await verify(adapter, receipt, true, opts)
  return receipt
}

export async function undo(adapter: HostAdapter, receipt: Receipt, opts: MarkOptions = {}): Promise<Receipt> {
  const current = adapter.currentContext()
  if (!current || current.key !== receipt.context.key) throw new ContextMismatch()

  let targets = receipt.marked.map((m) => m.file)
  if (receipt.unknown.length > 0) {
    const server = await adapter.reconcile(receipt.unknown.map((f) => f.id))
    targets = [...targets, ...receipt.unknown.filter((f) => server.get(f.id) === true)]
  }
  const asViewed = targets.map((f) => ({ ...f, viewed: true }))
  const batch = await runBatch(adapter, asViewed, false, receipt.context.key, { signal: opts.signal, onProgress: opts.onProgress })
  const undone: Receipt = { context: receipt.context, completeness: receipt.completeness, ...batch }
  if (opts.verify) await verify(adapter, undone, false, opts)
  return undone
}

/** Unmarks every viewed file of the page, several at a time like a marking, and stops on repeated failures like one. */
export async function unmarkAll(adapter: HostAdapter, opts: MarkOptions = {}): Promise<Receipt> {
  const listing = await adapter.listFiles()
  const batch = await runBatch(adapter, listing.files.filter((f) => f.viewed), false, listing.context.key, opts)
  const receipt: Receipt = { context: listing.context, completeness: listing.completeness, ...batch }
  if (opts.verify) await verify(adapter, receipt, false, opts)
  return receipt
}

export function loadAll(adapter: HostAdapter, onProgress?: (done: number, total?: number) => void, signal?: AbortSignal) {
  return adapter.loadAll(onProgress, signal)
}
