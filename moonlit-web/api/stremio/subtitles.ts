export const config = { runtime: 'edge' };

export default async function handler(req: Request) {
  const params = new URL(req.url).searchParams;
  const baseUrl = params.get('url');
  const type = params.get('type');
  const id = params.get('id');

  if (!baseUrl || !type || !id) {
    return new Response('Missing url, type, or id', { status: 400 });
  }

  const res = await fetch(`${baseUrl}/subtitles/${type}/${id}.json`);
  if (!res.ok) return new Response('Upstream error', { status: res.status });

  const data = await res.text();
  return new Response(data, {
    headers: {
      'Content-Type': 'application/json',
      'Cache-Control': 'public, s-maxage=1800, stale-while-revalidate=3600',
      'Access-Control-Allow-Origin': '*',
    },
  });
}
