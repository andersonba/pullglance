import picomatch from 'picomatch/posix'
import type { ChangedFile, MatchResult, Rule } from './model'

export type InvalidGlobReporter = (rule: Rule, glob: string, error: Error) => void

type Compiled = { rule: Rule; positive: Array<(p: string) => boolean>; negative: Array<(p: string) => boolean> }

function compile(rules: Rule[], onInvalidGlob?: InvalidGlobReporter): Compiled[] {
  return rules
    .filter((r) => r.enabled)
    .map((rule) => {
      const compiled: Compiled = { rule, positive: [], negative: [] }
      for (const glob of rule.globs) {
        const negated = glob.startsWith('!')
        const pattern = negated ? glob.slice(1) : glob
        try {
          const fn = picomatch(pattern, { dot: true })
          ;(negated ? compiled.negative : compiled.positive).push(fn)
        } catch (error) {
          onInvalidGlob?.(rule, glob, error as Error)
        }
      }
      return compiled
    })
}

function matchCompiled(path: string, compiled: Compiled[]): Rule | null {
  if (compiled.some((c) => c.negative.some((fn) => fn(path)))) return null
  const hit = compiled.find((c) => c.positive.some((fn) => fn(path)))
  return hit ? hit.rule : null
}

export function matchFiles(files: ChangedFile[], rules: Rule[], onInvalidGlob?: InvalidGlobReporter): MatchResult[] {
  const compiled = compile(rules, onInvalidGlob)
  const out: MatchResult[] = []
  for (const file of files) {
    const matchedBy = matchCompiled(file.path, compiled)
    if (matchedBy) out.push({ file, matchedBy })
  }
  return out
}

export function pathMatches(path: string, rules: Rule[]): Rule | null {
  return matchCompiled(path, compile(rules))
}
