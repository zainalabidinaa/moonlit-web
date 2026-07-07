const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const url = new URL(req.url);
    const addonUrl = url.searchParams.get('url');
    const type = url.searchParams.get('type');
    const id = url.searchParams.get('id');
    const extrasJson = url.searchParams.get('extras');

    if (!addonUrl || !type || !id) {
      return new Response('Missing url, type, or id', {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'text/plain' },
      });
    }

    let upstream: string;
    if (extrasJson) {
      try {
        const extras = JSON.parse(extrasJson) as Record<string, string>;
        const extraParts = Object.entries(extras)
          .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
          .join('&');
        upstream = `${addonUrl}/catalog/${type}/${id}/${extraParts}.json`;
      } catch {
        upstream = `${addonUrl}/catalog/${type}/${id}.json`;
      }
    } else {
      upstream = `${addonUrl}/catalog/${type}/${id}.json`;
    }

    const res = await fetch(upstream);
    if (!res.ok) {
      return new Response(`Upstream error: ${res.status}`, {
        status: 502,
        headers: { ...corsHeaders, 'Content-Type': 'text/plain' },
      });
    }

    const data = await res.text();
    return new Response(data, {
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json',
        'Cache-Control': 'public, s-maxage=300, stale-while-revalidate=600',
      },
    });
  } catch (err: any) {
    return new Response(err.message ?? 'Internal error', {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'text/plain' },
    });
  }
});
