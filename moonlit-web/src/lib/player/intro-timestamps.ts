interface IntroTimestamps {
  start: number;
  end: number;
}

const PUBLICMETA_URL = 'https://publicmeta.info/api/v1/intro';

export async function fetchIntroTimestamps(
  imdbId: string,
  season?: number,
  episode?: number,
): Promise<IntroTimestamps | null> {
  if (!imdbId) return null;

  try {
    const params = new URLSearchParams({ imdbId });
    if (season !== undefined) params.set('season', String(season));
    if (episode !== undefined) params.set('episode', String(episode));

    const res = await fetch(`${PUBLICMETA_URL}?${params}`, {
      signal: AbortSignal.timeout(5000),
    });

    if (!res.ok) return null;

    const data = await res.json();
    if (data && typeof data.introStart === 'number' && typeof data.introEnd === 'number') {
      return { start: data.introStart, end: data.introEnd };
    }

    return null;
  } catch {
    return null;
  }
}
