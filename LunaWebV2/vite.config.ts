import { transformWithEsbuild } from 'vite'
import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [
    // Transform JSX in @vidstack/react before Rollup parses it
    {
      name: 'vidstack-jsx-transform',
      enforce: 'pre',
      async transform(code, id) {
        if (!id.includes('@vidstack/react')) return null;
        if (!code.includes('<') || !code.includes('return <')) return null;
        return transformWithEsbuild(code, id, { loader: 'tsx', jsx: 'automatic' });
      },
    },
    react(),
  ],
  resolve: {
    alias: { '@': path.resolve(__dirname, './src') },
  },
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: './src/test/setup.ts',
  },
})
