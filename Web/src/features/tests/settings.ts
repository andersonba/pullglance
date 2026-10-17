import type { Rule } from '@/core/model'
import { PRESETS } from './presets'

export interface Settings {
  version: 1
  presets: Record<string, boolean>
  customGlobs: string[]
  customGlobsText: string
  autoMark: boolean
  verify: boolean
  rememberCompare: boolean
  loadBeforeMark: boolean
  /** Viewed files leave the file tree sidebar (the bar's toggle). */
  treeHidesViewed: boolean
}

export const DEFAULT_SETTINGS: Settings = {
  version: 1,
  presets: Object.fromEntries(PRESETS.map((p) => [p.id, p.enabled])),
  customGlobs: [],
  customGlobsText: '',
  autoMark: false,
  verify: true,
  rememberCompare: true,
  loadBeforeMark: true,
  treeHidesViewed: true,
}

export function normalize(raw: Partial<Settings> | null | undefined): Settings {
  return {
    version: 1,
    presets: { ...DEFAULT_SETTINGS.presets, ...(raw?.presets ?? {}) },
    customGlobs: Array.isArray(raw?.customGlobs) ? raw!.customGlobs.filter((g): g is string => typeof g === 'string') : [],
    customGlobsText: typeof raw?.customGlobsText === 'string' ? raw!.customGlobsText : '',
    autoMark: raw?.autoMark ?? DEFAULT_SETTINGS.autoMark,
    verify: raw?.verify ?? DEFAULT_SETTINGS.verify,
    rememberCompare: typeof raw?.rememberCompare === 'boolean' ? raw.rememberCompare : DEFAULT_SETTINGS.rememberCompare,
    loadBeforeMark: typeof raw?.loadBeforeMark === 'boolean' ? raw.loadBeforeMark : DEFAULT_SETTINGS.loadBeforeMark,
    treeHidesViewed: typeof raw?.treeHidesViewed === 'boolean' ? raw.treeHidesViewed : DEFAULT_SETTINGS.treeHidesViewed,
  }
}

export function parseCustomGlobs(text: string): string[] {
  return text.split('\n').map((l) => l.trim()).filter((l) => l.length > 0 && !l.startsWith('#'))
}

export function rulesFromSettings(s: Settings): Rule[] {
  const presets: Rule[] = PRESETS.map(({ id, label, globs }) => ({ id, label, globs, enabled: s.presets[id] ?? false }))
  return [...presets, { id: 'custom', label: 'Custom', globs: s.customGlobs, enabled: true }]
}
