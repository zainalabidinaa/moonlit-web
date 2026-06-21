export const config = { runtime: 'edge' };

// Convert SRT subtitle format to WebVTT.
// SRT uses commas in timestamps (00:00:01,000 --> 00:00:04,000) and has
// a numeric sequence line before each cue. VTT needs a WEBVTT header and
// dots instead of commas. Browsers and Vidstack silently drop SRT content
// even when served with text/vtt content-type.
function srtToVtt(srt: string): string {
  return (
    'WEBVTT\n\n' +
    srt
      // Normalize Windows line endings
      .replace(/\r\n/g, '\n')
      .replace(/\r/g, '\n')
      // Remove sequence numbers (lines that are purely digits)
      .replace(/^\d+\n/gm, '')
      // Convert SRT timestamp commas → VTT dots
      .replace(/(\d{2}:\d{2}:\d{2}),(\d{3})/g, '$1.$2')
      .trim()
  );
}

export default async function handler(req: Request) {
  const url = new URL(req.url).searchParams.get('url');
  if (!url) return new Response('Missing url param', { status: 400 });

  const res = await fetch(url, { headers: { 'Accept-Encoding': 'identity' } });
  if (!res.ok) return new Response('Upstream error', { status: res.status });

  let text = await res.text();

  // Auto-convert SRT to WebVTT if the content doesn't start with the WEBVTT header
  const trimmed = text.trimStart();
  if (!trimmed.startsWith('WEBVTT')) {
    text = srtToVtt(text);
  }

  return new Response(text, {
    headers: {
      'Content-Type': 'text/vtt; charset=utf-8',
      'Access-Control-Allow-Origin': '*',
      'Cache-Control': 'public, s-maxage=3600',
    },
  });
}
