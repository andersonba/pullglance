import { build } from 'esbuild'
import { writeFileSync } from 'node:fs'
import { PRESETS } from './src/features/tests/presets.ts' // Node 22.18+/24 strips TypeScript types natively.
const out = new URL('../Sources/Pullglance/Resources/', import.meta.url)
await build({
  entryPoints: ['src/entry.ts'], bundle: true, format: 'iife', platform: 'browser', target: 'safari17',
  minify: true, sourcemap: false, legalComments: 'none',
  alias: { '@': './src', '#imports': './src/shim/imports.ts' },
  outfile: new URL('review.js', out).pathname,
})
writeFileSync(new URL('review-presets.json', out), JSON.stringify(PRESETS, null, 1) + '\n')
