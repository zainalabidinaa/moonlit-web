/* eslint-disable @typescript-eslint/no-explicit-any */
import { transformWithEsbuild } from 'vite'
import { configDefaults, defineConfig } from 'vitest/config'
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

        const url = new URL(req.url, `http://${req.headers.host ?? 'localhost'}`);

        if (req.method === 'POST' && url.pathname.endsWith('/session')) {
          const chunks: Buffer[] = [];
          req.on('data', (c: Buffer) => chunks.push(c));
          req.on('end', async () => {
            try {
              let body: any = {};
              try { body = JSON.parse(Buffer.concat(chunks).toString()); } catch { /* keep default */ }
              if (!body.target || typeof body.target !== 'string') {
                res.writeHead(400); res.end('Missing target URL'); return;
              }
              let targetUrl: URL;
              try { targetUrl = new URL(body.target); } catch {
                res.writeHead(400); res.end('Invalid target URL'); return;
              }
              if (targetUrl.protocol !== 'http:' && targetUrl.protocol !== 'https:') {
                res.writeHead(400); res.end('Only http(s) targets allowed'); return;
              }
              if (targetUrl.hostname === 'localhost' || targetUrl.hostname === '127.0.0.1' || targetUrl.hostname === '::1' || targetUrl.hostname === '169.254.169.254') {
                res.writeHead(403); res.end('Target blocked'); return;
              }
              const sessionId = crypto.randomUUID();
              res.writeHead(201, {'Content-Type': 'application/json', 'Cache-Control': 'no-store'});
              res.end(JSON.stringify({ session: sessionId }));
            } catch {
              res.writeHead(500); res.end('Proxy error');
            }
          });
          return;
        }

        const target = url.searchParams.get('url');
        if (!target) {
          res.writeHead(400, {'Cache-Control': 'no-store'});
          res.end('Missing url parameter');
          return;
        }

        let targetUrl: URL;
        try { targetUrl = new URL(target); } catch {
          res.writeHead(400, {'Cache-Control': 'no-store'});
          res.end('Invalid target URL');
          return;
        }
        if (targetUrl.protocol !== 'http:' && targetUrl.protocol !== 'https:') {
          res.writeHead(400, {'Cache-Control': 'no-store'});
          res.end('Only http(s) targets allowed');
          return;
        }

        try {
          const targetResp = await fetch(targetUrl.href, {
            headers: { 'User-Agent': req.headers['user-agent'] ?? 'VLC/3.0.20 LibVLC/3.0.20' },
            redirect: 'manual',
          });
          if ([301,302,303,307,308].includes(targetResp.status)) {
            res.writeHead(502, {'Cache-Control': 'no-store'});
            res.end('Redirects not allowed');
            return;
          }
          const respHeaders: Record<string, string> = {
            'Cache-Control': 'no-store',
            'Access-Control-Allow-Origin': '*',
            'X-Content-Type-Options': 'nosniff',
          };
          const ct = targetResp.headers.get('content-type');
          if (ct) respHeaders['Content-Type'] = ct;
          const cl = targetResp.headers.get('content-length');
          if (cl) respHeaders['Content-Length'] = cl;
          const cr = targetResp.headers.get('content-range');
          if (cr) respHeaders['Content-Range'] = cr;

          res.writeHead(targetResp.status, respHeaders);
          if (targetResp.body) {
            const reader = targetResp.body.getReader();
            const pump = async () => {
              while (true) {
                const { done, value } = await reader.read();
                if (done) { res.end(); return; }
                res.write(value);
              }
            };
            pump().catch(() => { try { res.end(); } catch { /* already closed */ } });
          } else {
            res.end();
          }
        } catch (err: any) {
          res.writeHead(502, {'Cache-Control': 'no-store'});
          res.end(err.message ?? 'Proxy error');
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
    exclude: [...configDefaults.exclude, 'src/test/e2e/**', 'src/test/visual/**'],
  },
})
