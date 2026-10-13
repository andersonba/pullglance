export interface PageContext {
  key: string
  basePath: string
  headOid: string
}

export interface ChangedFile {
  path: string
  id: string
  viewed: boolean
  hasControl: boolean
}

export interface Rule {
  id: string
  label: string
  globs: string[]
  enabled: boolean
}

export interface MatchResult {
  file: ChangedFile
  matchedBy: Rule
}

export type Completeness = 'full' | 'partial'

export interface FileListing {
  context: PageContext
  files: ChangedFile[]
  completeness: Completeness
}

export type SetViewedOutcome = 'dom' | 'api' | 'noop'

export interface Receipt {
  context: PageContext
  marked: Array<{ file: ChangedFile; via: 'dom' | 'api' }>
  failed: Array<{ file: ChangedFile; error: string }>
  unknown: ChangedFile[]
  skipped: ChangedFile[]
  stoppedEarly: boolean
  completeness: Completeness
  verified?: { confirmed: number; diverged: ChangedFile[] }
}
