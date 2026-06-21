export const config = { runtime: 'edge' };

export default async function handler(req: Request) {
  const params = new URL(req.url).searchParams;
  const baseUrl = params.get('url');
  const type = params.get('type');
  const id = params.get('id');
  const extrasJson = params.get('extras');

  if (!baseUrl || !type || !id) {
    return new Response('Missing url, type, or id', { status: 400 });
  }

  let upstreamUrl: string;
  if (extrasJson) {
    try {
      const extras = JSON.parse(extrasJson) as Record<string, string>;
      const extraParts = Object.entries(extras)
        .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
        .join('&');
      upstreamUrl = `${baseUrl}/catalog/${type}/${id}/${extraParts}.json`;
    } catch {
      upstreamUrl = `${baseUrl}/catalog/${type}/${id}.json`;
    }
  } else {
    upstreamUrl = `${baseUrl}/catalog/${type}/${id}.json`;
  }

  const res = await fetch(upstreamUrl);
  if (!res.ok) return new Response('Upstream error', { status: res.status });

  const data = await res.text();
  return new Response(data, {
    headers: {
      'Content-Type': 'application/json',
      'Cache-Control': 'public, s-maxage=300, stale-while-revalidate=600',
      'Access-Control-Allow-Origin': '*',
    },
  });
}
