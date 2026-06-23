import { transformWithEsbuild } from 'vite'
import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import path from 'path'

// Dev-only CORS proxy that mirrors the Vercel edge functions in api/stremio/
function srtToVtt(srt: string): string {
  return (
    'WEBVTT\n\n' +
    srt
      .replace(/\r\n/g, '\n')
      .replace(/\r/g, '\n')
      .replace(/^\d+\n/gm, '')
      .replace(/(\d{2}:\d{2}:\d{2}),(\d{3})/g, '$1.$2')
      .trim()
  );
}

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
          } else if (route === 'vtt') {
            const url = params.get('url');
            if (!url) { res.writeHead(400); res.end('Missing url'); return; }
            const upstream = await fetch(url, { headers: { 'Accept-Encoding': 'identity' } });
            if (!upstream.ok) {
              res.writeHead(upstream.status, { 'Access-Control-Allow-Origin': '*' });
              res.end('Upstream error');
              return;
            }
            let text = await upstream.text();
            if (!text.trimStart().startsWith('WEBVTT')) {
              text = srtToVtt(text);
            }
            res.writeHead(200, {
              'Content-Type': 'text/vtt; charset=utf-8',
              'Access-Control-Allow-Origin': '*',
            });
            res.end(text);
            return;
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

function mediaProxyDevProxy() {
  return {
    name: 'media-dev-proxy',
    configureServer(server: any) {
      server.middlewares.use(async (req: any, res: any, next: any) => {
        if (!req.url?.startsWith('/api/media-proxy')) return next();

        const base = `http://localhost${req.url}`;
        const url = new URL(base).searchParams.get('url');
        if (!url) {
          res.writeHead(400, { 'Access-Control-Allow-Origin': '*' });
          res.end('Missing url param');
          return;
        }

        const headers: HeadersInit = {};
        const range = req.headers.range;
        if (range) headers.Range = range;

        try {
          const controller = new AbortController();
          const timeoutId = setTimeout(() => controller.abort(), 15000);
          const upstream = await fetch(url, { headers, signal: controller.signal });
          clearTimeout(timeoutId);
          const responseHeaders: Record<string, string> = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Range',
            'Access-Control-Expose-Headers': 'Content-Range, Content-Length, Accept-Ranges',
          };

          for (const key of ['content-type', 'content-length', 'content-range', 'accept-ranges']) {
            const value = upstream.headers.get(key);
            if (value) responseHeaders[key] = value;
          }

          res.writeHead(upstream.status, responseHeaders);
          if (!upstream.body) {
            res.end();
            return;
          }

          const reader = upstream.body.getReader();
          try {
            while (true) {
              const { done, value } = await reader.read();
              if (done) break;
              res.write(Buffer.from(value));
            }
            res.end();
          } catch (error) {
            res.destroy(error as Error);
          }
        } catch (error) {
          res.writeHead(502, { 'Access-Control-Allow-Origin': '*' });
          res.end(String(error));
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
    mediaProxyDevProxy(),
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
