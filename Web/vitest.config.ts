import { defineConfig } from 'vitest/config'
import { fileURLToPath } from 'node:url'
export default defineConfig({
  resolve: {
    alias: {
      '@@': fileURLToPath(new URL('.', import.meta.url)),
      '@': fileURLToPath(new URL('./src', import.meta.url)),
      '#imports': fileURLToPath(new URL('./src/shim/imports.ts', import.meta.url)),
    },
  },
  test: {
    environment: 'happy-dom',
    globals: true,
    setupFiles: ['./src/test-setup.ts'],
    include: ['src/**/*.test.ts', 'tests/**/*.test.ts'],
  },
})
