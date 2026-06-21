/**
 * Streaming media proxy — passes Range requests through to the upstream URL.
 * Needed so web-demuxer can fetch MKV files from cross-origin sources that
 * don't set CORS headers.
 */
export const config = { runtime: 'edge' };

export default async function handler(req: Request) {
  const url = new URL(req.url).searchParams.get('url');
  if (!url) return new Response('Missing url param', { status: 400 });

  const headers: HeadersInit = {};
  const range = req.headers.get('range');
  if (range) headers['Range'] = range;

  const upstream = await fetch(url, { headers });

  const responseHeaders = new Headers();
  responseHeaders.set('Access-Control-Allow-Origin', '*');
  responseHeaders.set('Access-Control-Allow-Headers', 'Range');
  responseHeaders.set('Access-Control-Expose-Headers', 'Content-Range, Content-Length, Accept-Ranges');

  for (const key of ['Content-Type', 'Content-Length', 'Content-Range', 'Accept-Ranges']) {
    const val = upstream.headers.get(key);
    if (val) responseHeaders.set(key, val);
  }

  return new Response(upstream.body, {
    status: upstream.status,
    headers: responseHeaders,
  });
}
