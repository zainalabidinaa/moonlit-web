const PREFLIGHT_TIMEOUT_MS = 3000;
const PREFLIGHT_BYTES = 4095;

interface PreflightResult {
  reachable: boolean;
  status?: number;
  error?: string;
}

export async function preflightUrl(url: string): Promise<PreflightResult> {
  if (!url) return { reachable: false, error: 'No URL provided' };

  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), PREFLIGHT_TIMEOUT_MS);

    const res = await fetch(url, {
      method: 'GET',
      headers: { Range: `bytes=0-${PREFLIGHT_BYTES}` },
      signal: controller.signal,
    });

    clearTimeout(timer);

    // Accept 206 (Partial Content), 200 (OK), 416 (Range Not Satisfiable)
    if (res.status === 401 || res.status === 403 || res.status === 429) {
      return { reachable: false, status: res.status, error: `Auth error (${res.status})` };
    }

    if (!res.ok && res.status !== 416) {
      return { reachable: false, status: res.status, error: `HTTP ${res.status}` };
    }

    // Check content-type — reject HTML responses (likely auth pages / dead proxies)
    const contentType = res.headers.get('content-type') || '';
    if (contentType.includes('text/html')) {
      return { reachable: false, status: res.status, error: 'HTML response — likely dead or auth-gated proxy' };
    }

    // Check for JSON error bodies from debrid services
    if (contentType.includes('application/json')) {
      try {
        const text = await res.clone().text();
        const lower = text.toLowerCase();
        if (lower.includes('not cached') || lower.includes('downloading') ||
            lower.includes('access denied') || lower.includes('invalid token') ||
            lower.includes('error')) {
          return { reachable: false, status: res.status, error: 'Debrid service error' };
        }
      } catch {}
    }

    return { reachable: true, status: res.status };
  } catch (err: any) {
    if (err.name === 'AbortError') {
      return { reachable: false, error: 'Request timed out' };
    }
    return { reachable: false, error: err.message || 'Network error' };
  }
}

export async function findReachableUrl(urls: string[]): Promise<{ url: string } | null> {
  const results = await Promise.allSettled(urls.map(u => preflightUrl(u)));
  for (let i = 0; i < results.length; i++) {
    const r = results[i];
    if (r.status === 'fulfilled' && r.value.reachable) {
      return { url: urls[i] };
    }
  }
  return null;
}
