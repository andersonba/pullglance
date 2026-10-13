import type { Rule } from '@/core/model'

export interface Preset extends Rule { description: string; group: string }

const p = (id: string, group: string, label: string, description: string, globs: string[], enabled = true): Preset =>
  ({ id, group, label, description, globs, enabled })

export const PRESETS: readonly Preset[] = [
  p('js-unit', 'JavaScript / TypeScript', 'Unit tests', 'Jest, Vitest, Mocha: *.test.*, *.spec.*, __tests__/', ['**/*.{test,spec}.{js,jsx,ts,tsx,mjs,cjs}', '**/__tests__/**']),
  p('js-stories', 'JavaScript / TypeScript', 'Storybook', '*.stories.*', ['**/*.stories.{js,jsx,ts,tsx}'], false),
  p('snapshots-fixtures', 'General', 'Snapshots, fixtures and mocks', '__snapshots__/, *.snap, __fixtures__/, fixtures/, __mocks__/', ['**/__snapshots__/**', '**/*.snap', '**/__fixtures__/**', '**/fixtures/**', '**/__mocks__/**']),
  p('e2e', 'General', 'End-to-end', 'Cypress, Playwright, *.e2e.*, *.cy.*', ['**/*.{e2e,cy}.{js,ts,tsx}', '**/cypress/**', '**/e2e/**', '**/playwright/**']),
  p('generic-dirs', 'General', 'Test folders', 'test/, tests/, spec/, testing/', ['**/test/**', '**/tests/**', '**/spec/**', '**/testing/**']),
  p('go', 'Go', 'Go', '*_test.go, testdata/', ['**/*_test.go', '**/testdata/**']),
  p('python', 'Python', 'pytest / unittest', 'test_*.py, *_test.py, conftest.py', ['**/test_*.py', '**/*_test.py', '**/conftest.py']),
  p('ruby', 'Ruby', 'RSpec / Minitest', '*_spec.rb, *_test.rb', ['**/*_spec.rb', '**/*_test.rb']),
  p('jvm', 'Java / Kotlin', 'JUnit', 'src/test/, *Test.java, *Tests.kt', ['**/src/test/**', '**/*Test.{java,kt}', '**/*Tests.{java,kt}']),
  p('dotnet', '.NET', 'xUnit / NUnit', '*.Tests/, *Tests.cs', ['**/*.Tests/**', '**/*Tests.cs']),
  p('php', 'PHP', 'PHPUnit', '*Test.php', ['**/*Test.php']),
  p('elixir', 'Elixir', 'ExUnit', '*_test.exs', ['**/*_test.exs']),
]
