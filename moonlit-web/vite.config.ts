import { transformWithEsbuild } from 'vite'
import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import path from 'path'

// Dev-only CORS proxy that mirrors the Vercel edge functions in api/stremio/
function stremioDevProxy() {
  return {
    name: 'stremio-dev-proxy',
    configureServer(server: any) {
      server.middlewares.use(async (req: any, res: any, next: any) => {
        if (!req.url?.startsWith('/api/stremio/')) return next();

        const base = `http://localhost${req.url}`;
        const params = new URL(base).searchParams;
        const corsHeaders = { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' };

        try {
          const route = req.url.split('?')[0].replace('/api/stremio/', '');
          let upstreamUrl = '';

          if (route === 'manifest') {
            const url = params.get('url');
            if (!url) { res.writeHead(400); res.end('Missing url'); return; }
            upstreamUrl = url;
          } else if (route === 'meta') {
            const [url, type, id] = [params.get('url'), params.get('type'), params.get('id')];
            if (!url || !type || !id) { res.writeHead(400); res.end('Missing params'); return; }
            upstreamUrl = `${url}/meta/${type}/${id}.json`;
          } else if (route === 'catalog') {
            const [url, type, id] = [params.get('url'), params.get('type'), params.get('id')];
            if (!url || !type || !id) { res.writeHead(400); res.end('Missing params'); return; }
            const extrasJson = params.get('extras');
            if (extrasJson) {
              const extras = JSON.parse(extrasJson) as Record<string, string>;
              const extraParts = Object.entries(extras).map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join('&');
              upstreamUrl = `${url}/catalog/${type}/${id}/${extraParts}.json`;
            } else {
              upstreamUrl = `${url}/catalog/${type}/${id}.json`;
            }
          } else if (route === 'stream') {
            const [url, type, id] = [params.get('url'), params.get('type'), params.get('id')];
            if (!url || !type || !id) { res.writeHead(400); res.end('Missing params'); return; }
            upstreamUrl = `${url}/stream/${type}/${id}.json`;
          } else if (route === 'subtitles') {
            const [url, type, id] = [params.get('url'), params.get('type'), params.get('id')];
            if (!url || !type || !id) { res.writeHead(400); res.end('Missing params'); return; }
            upstreamUrl = `${url}/subtitles/${type}/${id}.json`;
          } else {
            return next();
          }

          const upstream = await fetch(upstreamUrl);
          const body = await upstream.text();
          res.writeHead(upstream.ok ? 200 : upstream.status, corsHeaders);
          res.end(body);
        } catch (e) {
          res.writeHead(500, corsHeaders);
          res.end(JSON.stringify({ error: String(e) }));
        }
      });
    },
  };
}

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
    stremioDevProxy(),
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
