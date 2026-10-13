import { DEFAULT_SETTINGS, normalize, parseCustomGlobs, rulesFromSettings, type Settings } from './settings'
import { PRESETS } from './presets'

describe('settings', () => {
  it('defaults: todos presets com seu enabled padrão, sem globs, autoMark off, verify on', () => {
    expect(DEFAULT_SETTINGS.version).toBe(1)
    expect(DEFAULT_SETTINGS.presets['js-stories']).toBe(false)
    expect(DEFAULT_SETTINGS.presets['js-unit']).toBe(true)
    expect(DEFAULT_SETTINGS.customGlobs).toEqual([])
    expect(DEFAULT_SETTINGS.customGlobsText).toBe('')
    expect(DEFAULT_SETTINGS.autoMark).toBe(false)
    expect(DEFAULT_SETTINGS.verify).toBe(true)
  })

  it('rulesFromSettings aplica toggles e acrescenta regra custom por último', () => {
    const s: Settings = { ...DEFAULT_SETTINGS, presets: { ...DEFAULT_SETTINGS.presets, go: false }, customGlobs: ['**/*.golden', '!**/keep/**'] }
    const rules = rulesFromSettings(s)
    expect(rules.find((r) => r.id === 'go')?.enabled).toBe(false)
    expect(rules.at(-1)).toEqual({ id: 'custom', label: 'Custom', globs: ['**/*.golden', '!**/keep/**'], enabled: true })
    expect(rules).toHaveLength(PRESETS.length + 1)
  })

  it('parseCustomGlobs ignora linhas vazias, espaços e comentários', () => {
    expect(parseCustomGlobs(' **/*.golden \n\n# comentário\n!**/keep/**\n')).toEqual(['**/*.golden', '!**/keep/**'])
  })

  it('normalize devolve defaults quando vazio e mescla presets novos', () => {
    expect(normalize(null)).toEqual(DEFAULT_SETTINGS)
    const loaded = normalize({ version: 1, presets: { 'js-unit': false }, autoMark: true })
    expect(loaded.presets['js-unit']).toBe(false)
    expect(loaded.presets['go']).toBe(true)
    expect(loaded.autoMark).toBe(true)
    expect(loaded.customGlobs).toEqual([])
    expect(loaded.customGlobsText).toBe('')
    expect(loaded.verify).toBe(true)
  })

  it('normalize sem customGlobsText normaliza para empty string', () => {
    expect(normalize({ version: 1, presets: {}, autoMark: false, verify: true }).customGlobsText).toBe('')
  })
})
