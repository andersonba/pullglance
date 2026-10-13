export interface Diagnostics {
  url: string
  chosen: Record<string, string | null>
  probes: Record<string, Record<string, boolean>>
  misses: Record<string, number>
}

export function formatDiagnostics(d: Diagnostics): string {
  const lines = [`gh-review-assistant diagnostics`, `url: ${d.url}`, '']
  for (const concept of Object.keys({ ...d.chosen, ...d.probes, ...d.misses })) {
    lines.push(`[${concept}] chosen=${d.chosen[concept] ?? 'none'} misses=${d.misses[concept] ?? 0}`)
    for (const [id, ok] of Object.entries(d.probes[concept] ?? {})) lines.push(`  probe ${id}: ${ok}`)
  }
  return lines.join('\n')
}
