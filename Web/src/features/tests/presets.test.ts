import { PRESETS } from './presets'
import { pathMatches } from '@/core/matcher'

const enabled = PRESETS.filter((p) => p.enabled)

const POSITIVE: Array<[string, string]> = [
  ['src/a.test.ts', 'js-unit'], ['src/a.spec.tsx', 'js-unit'], ['src/__tests__/a.ts', 'js-unit'], ['lib/b.test.mjs', 'js-unit'],
  ['src/__snapshots__/a.snap', 'snapshots-fixtures'], ['src/__mocks__/fs.ts', 'snapshots-fixtures'], ['test/fixtures/x.json', 'snapshots-fixtures'],
  ['e2e/login.cy.ts', 'e2e'], ['cypress/support/e2e.ts', 'e2e'], ['apps/web/playwright/a.ts', 'e2e'],
  ['pkg/test/helper.ts', 'generic-dirs'], ['spec/models/user_spec.rb', 'generic-dirs'],
  ['cmd/server/main_test.go', 'go'], ['internal/testdata/golden.json', 'go'],
  ['app/tests/test_models.py', 'python'], ['app/conftest.py', 'python'], ['app/models_test.py', 'python'],
  ['lib/user_spec.rb', 'ruby'], ['lib/user_test.rb', 'ruby'],
  ['service/src/test/java/A.java', 'jvm'], ['service/src/main/kotlin/ATest.kt', 'jvm'],
  ['Foo.Tests/FooTests.cs', 'dotnet'], ['src/FooTests.cs', 'dotnet'],
  ['app/UserTest.php', 'php'], ['lib/user_test.exs', 'elixir'],
]

const NEGATIVE = ['src/app.ts', 'src/testing-library-wrapper.ts', 'README.md', 'src/contest.py', 'src/latest.go', 'docs/test-plan.md']

describe('PRESETS', () => {
  it('ids únicos e stories desligado por padrão', () => {
    expect(new Set(PRESETS.map((p) => p.id)).size).toBe(PRESETS.length)
    expect(PRESETS.find((p) => p.id === 'js-stories')?.enabled).toBe(false)
  })

  it.each(POSITIVE)('%s casa com algum preset habilitado (esperado grupo %s ou generic-dirs)', (path, expected) => {
    const hit = pathMatches(path, [...enabled])
    expect(hit).not.toBeNull()
    expect([expected, 'generic-dirs', 'snapshots-fixtures']).toContain(hit!.id)
  })

  it.each(NEGATIVE)('%s não casa', (path) => {
    expect(pathMatches(path, [...enabled])).toBeNull()
  })

  it('stories casa só quando habilitado', () => {
    expect(pathMatches('src/Button.stories.tsx', [...enabled])).toBeNull()
    expect(pathMatches('src/Button.stories.tsx', PRESETS.map((p) => ({ ...p, enabled: true })))?.id).toBe('js-stories')
  })
})
