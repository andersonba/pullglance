import { matchFiles, pathMatches } from './matcher'
import type { ChangedFile, Rule } from './model'

const file = (path: string, viewed = false): ChangedFile => ({ path, id: path, viewed, hasControl: true })
const rule = (id: string, globs: string[], enabled = true): Rule => ({ id, label: id, globs, enabled })

describe('matchFiles', () => {
  it('casa pelo caminho completo com dot: true', () => {
    const r = rule('unit', ['**/*.test.ts', '**/__tests__/**'])
    const out = matchFiles([file('src/a.test.ts'), file('src/.hidden/b.test.ts'), file('src/__tests__/c.ts'), file('src/a.ts')], [r])
    expect(out.map((m) => m.file.path)).toEqual(['src/a.test.ts', 'src/.hidden/b.test.ts', 'src/__tests__/c.ts'])
    expect(out[0]!.matchedBy.id).toBe('unit')
  })

  it('ignora regras desabilitadas', () => {
    expect(matchFiles([file('a.test.ts')], [rule('unit', ['**/*.test.ts'], false)])).toEqual([])
  })

  it('globs negativos excluem depois dos positivos, de qualquer regra', () => {
    const out = matchFiles(
      [file('test/helpers/x.ts'), file('test/y.ts')],
      [rule('dirs', ['**/test/**']), rule('custom', ['!**/test/helpers/**'])],
    )
    expect(out.map((m) => m.file.path)).toEqual(['test/y.ts'])
  })

  it('primeira regra habilitada que casa é a matchedBy', () => {
    const out = matchFiles([file('a.spec.ts')], [rule('one', ['**/*.spec.ts']), rule('two', ['**/*.ts'])])
    expect(out[0]!.matchedBy.id).toBe('one')
  })

  it('casa caminhos com espaços, parênteses, colchetes e unicode literalmente', () => {
    const paths = ['src/my dir/a.test.ts', 'src/(group)/b.test.ts', 'src/[id]/c.test.ts', 'src/ação/d.test.ts']
    const out = matchFiles(paths.map((p) => file(p)), [rule('unit', ['**/*.test.ts'])])
    expect(out.map((m) => m.file.path)).toEqual(paths)
  })

  it('glob inválido é descartado e reportado, sem derrubar os outros', () => {
    const reported: string[] = []
    const tooLong = 'a'.repeat(70000)
    const out = matchFiles([file('a.test.ts')], [rule('bad', [tooLong, '**/*.test.ts'])], (_r, g) => reported.push(g))
    expect(reported).toEqual([tooLong])
    expect(out).toHaveLength(1)
  })
})

describe('pathMatches', () => {
  it('devolve a regra ou null', () => {
    expect(pathMatches('a_test.go', [rule('go', ['**/*_test.go'])])?.id).toBe('go')
    expect(pathMatches('a.go', [rule('go', ['**/*_test.go'])])).toBeNull()
  })
})
