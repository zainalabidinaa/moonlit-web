import { expect, test, type Page } from '@playwright/test';

const fixture = (name: string) => `/src/test/fixtures/player-media/${name}`;

async function loadHtmlAdapter(page: Page, input: {
  method: 'native' | 'hls-mse' | 'mpeg-ts';
  url: string;
  sourceType: 'video' | 'hls' | 'mpeg-ts';
  isLive?: boolean;
  expectEnded?: boolean;
  subtitles?: Array<{ id: string; lang: string; name: string; url: string }>;
}) {
  return page.evaluate(async request => {
    const adapterModule = '/src/lib/player/adapters/html-video.ts';
    const { HtmlVideoAdapter } = await import(/* @vite-ignore */ adapterModule) as typeof import('../../lib/player/adapters/html-video');
    const root = document.createElement('div');
    const video = document.createElement('video');
    video.muted = true;
    root.append(video);
    document.body.append(root);
    const adapter = new HtmlVideoAdapter(video, root);
    const states: Array<{ phase: string; duration: number; hasVideo: boolean | null; error: string | null }> = [];
    adapter.subscribe(state => states.push({ phase: state.phase, duration: state.duration, hasVideo: state.hasVideo, error: state.error }));
    const waitFor = async (predicate: () => boolean, timeout = 12_000) => {
      const started = performance.now();
      while (!predicate()) {
        if (performance.now() - started > timeout) throw new Error(`Timed out. Last state: ${JSON.stringify(states.at(-1))}`);
        await new Promise(resolve => setTimeout(resolve, 25));
      }
    };
    await adapter.load({
      attempt: {
        id: `${request.method}:fixture`,
        adapter: 'html-video',
        method: request.method,
        url: request.url,
        sourceType: request.sourceType,
        isLive: request.isLive ?? false,
        reason: 'Playwright encoded fixture',
      },
      position: 0,
      tracks: { audioId: null, subtitleId: null, audioLanguage: null, subtitleLanguage: 'en' },
      subtitles: request.subtitles ?? [],
      signal: new AbortController().signal,
    });
    await waitFor(() => states.some(state => state.phase === 'ready' || state.phase === 'playing'));
    const ready = states.find(state => state.phase === 'ready' || state.phase === 'playing');
    const preview = request.method === 'native' ? await adapter.requestSeekPreview(1) : null;
    if (request.subtitles?.length) adapter.selectSubtitleTrack(request.subtitles[0].id);
    const subtitle = Array.from(video.textTracks).find(track => track.mode === 'showing');
    await video.play();
    if (request.expectEnded ?? true) {
      video.currentTime = Math.max(0, video.duration - 0.25);
      await waitFor(() => states.some(state => state.phase === 'ended'));
    } else {
      await waitFor(() => video.currentTime > 0.05);
    }
    const result = {
      ready,
      ended: states.some(state => state.phase === 'ended'),
      preview,
      subtitle: subtitle ? { label: subtitle.label, language: subtitle.language, mode: subtitle.mode } : null,
      videoWidth: video.videoWidth,
      videoHeight: video.videoHeight,
      currentTime: video.currentTime,
    };
    await adapter.destroy();
    root.remove();
    return result;
  }, input);
}

test.beforeEach(async ({ page }) => {
  await page.goto('/');
});

test('decodes MP4 through HtmlVideoAdapter with readiness, subtitles, preview, and ended', async ({ page }) => {
  const result = await loadHtmlAdapter(page, {
    method: 'native',
    url: fixture('sample-av.mp4'),
    sourceType: 'video',
    subtitles: [{ id: 'fixture-en', lang: 'en', name: 'English fixture', url: fixture('sample.vtt') }],
  });

  expect(result.ready).toMatchObject({ hasVideo: true, duration: 2 });
  expect(result.videoWidth).toBe(320);
  expect(result.videoHeight).toBe(180);
  expect(result.subtitle).toMatchObject({ label: 'English fixture', language: 'en', mode: 'showing' });
  expect(result.preview?.imageUrl).toMatch(/^data:image\/jpeg;base64,/);
  expect(result.ended).toBe(true);
});

test('loads finite HLS manifest and MPEG-TS segments through HLS.js', async ({ page }) => {
  const result = await loadHtmlAdapter(page, {
    method: 'hls-mse',
    url: fixture('sample.m3u8'),
    sourceType: 'hls',
  });

  expect(result.ready).toMatchObject({ hasVideo: true, duration: 2 });
  expect(result.ended).toBe(true);
});

test('switches from a dead source to the encoded MP4 through PlayerSession fallback', async ({ page }) => {
  const result = await page.evaluate(async urls => {
    const adapterModule = '/src/lib/player/adapters/html-video.ts';
    const sessionModule = '/src/lib/player/session.ts';
    const { HtmlVideoAdapter } = await import(/* @vite-ignore */ adapterModule) as typeof import('../../lib/player/adapters/html-video');
    const { PlayerSession } = await import(/* @vite-ignore */ sessionModule) as typeof import('../../lib/player/session');
    const root = document.createElement('div');
    const video = document.createElement('video');
    video.muted = true;
    root.append(video);
    document.body.append(root);
    const plan = {
      outcome: 'play-here' as const,
      label: 'Fixture fallback',
      detail: 'Dead then encoded',
      stream: { url: urls.dead },
      attempts: [urls.dead, urls.healthy].map((url, index) => ({
        id: `native:${index}`,
        adapter: 'html-video' as const,
        method: 'native' as const,
        url,
        sourceType: 'video' as const,
        isLive: false,
        reason: index === 0 ? 'dead' : 'healthy',
      })),
    };
    const session = new PlayerSession(plan, {
      startupTimeoutMs: 4_000,
      createAdapter: () => new HtmlVideoAdapter(video, root),
    });
    let state = session.getState();
    session.subscribe(next => { state = next; });
    void session.start({
      position: 0,
      tracks: { audioId: null, subtitleId: 'off', audioLanguage: null, subtitleLanguage: null },
      subtitles: [],
    });
    const started = performance.now();
    while (!(state.attemptIndex === 1 && (state.phase === 'ready' || state.phase === 'playing'))) {
      if (performance.now() - started > 12_000) throw new Error(`Fallback timed out: ${JSON.stringify(state)}`);
      await new Promise(resolve => setTimeout(resolve, 25));
    }
    const result = { attemptIndex: state.attemptIndex, fallbackReason: state.fallbackReason, hasVideo: state.adapterState?.hasVideo };
    await session.destroy();
    root.remove();
    return result;
  }, { dead: fixture('missing.mp4'), healthy: fixture('sample-av.mp4') });

  expect(result).toMatchObject({ attemptIndex: 1, hasVideo: true });
  expect(result.fallbackReason).toBeTruthy();
});

test('decodes a continuous MPEG-TS stream through mpegts.js', async ({ page }) => {
  const capabilities = await page.evaluate(() => ({
    mediaSource: typeof MediaSource !== 'undefined',
  }));
  test.skip(!capabilities.mediaSource, 'MSE is unavailable in this browser');

  const result = await loadHtmlAdapter(page, {
    method: 'mpeg-ts',
    url: new URL(fixture('sample-av.mpegts'), page.url()).href,
    sourceType: 'mpeg-ts',
    isLive: true,
    expectEnded: false,
  });

  expect(result.ready?.hasVideo, JSON.stringify(result)).toBe(true);
  expect(result.videoWidth).toBe(320);
  expect(result.videoHeight).toBe(180);
  expect(result.currentTime).toBeGreaterThan(0.05);
});

test('remuxes and decodes MKV through MediabunnyAdapter', async ({ page }) => {
  const mediaSource = await page.evaluate(() => typeof MediaSource !== 'undefined');
  test.skip(!mediaSource, 'MSE is unavailable in this browser');

  const result = await page.evaluate(async url => {
    const adapterModule = '/src/lib/player/adapters/mediabunny.ts';
    const { MediabunnyAdapter } = await import(/* @vite-ignore */ adapterModule) as typeof import('../../lib/player/adapters/mediabunny');
    const root = document.createElement('div');
    const video = document.createElement('video');
    video.muted = true;
    root.append(video);
    document.body.append(root);
    const adapter = new MediabunnyAdapter(video, root);
    const states: Array<{ phase: string; error: string | null; hasVideo: boolean | null }> = [];
    adapter.subscribe(state => states.push({ phase: state.phase, error: state.error, hasVideo: state.hasVideo }));
    await adapter.load({
      attempt: {
        id: 'mediabunny:fixture', adapter: 'mediabunny', method: 'mediabunny-remux',
        url, sourceType: 'mkv', isLive: false, reason: 'Playwright encoded fixture',
      },
      position: 0,
      tracks: { audioId: null, subtitleId: null, audioLanguage: null, subtitleLanguage: null },
      subtitles: [],
      signal: new AbortController().signal,
    });
    const started = performance.now();
    while (!states.some(state => state.phase === 'ready' || state.phase === 'playing' || state.phase === 'error')) {
      if (performance.now() - started > 15_000) throw new Error(`Mediabunny timed out: ${JSON.stringify(states.at(-1))}`);
      await new Promise(resolve => setTimeout(resolve, 25));
    }
    const terminal = states.at(-1);
    if (terminal?.phase !== 'error') {
      await video.play();
      while (video.currentTime <= 0.05) {
        if (performance.now() - started > 15_000) throw new Error('Mediabunny did not advance playback');
        await new Promise(resolve => setTimeout(resolve, 25));
      }
    }
    const result = { terminal, width: video.videoWidth, height: video.videoHeight, currentTime: video.currentTime };
    await adapter.destroy();
    root.remove();
    return result;
  }, fixture('sample-av.mkv'));

  expect(result.terminal?.phase).not.toBe('error');
  expect(result.terminal?.hasVideo).toBe(true);
  expect(result.width).toBe(320);
  expect(result.height).toBe(180);
  expect(result.currentTime).toBeGreaterThan(0.05);
});

test('decodes MKV through WebCodecsAdapter when the APIs are available', async ({ page }) => {
  const webCodecs = await page.evaluate(() => typeof VideoDecoder !== 'undefined' && typeof AudioDecoder !== 'undefined');
  test.skip(!webCodecs, 'WebCodecs video/audio APIs are unavailable in this browser');

  const result = await page.evaluate(async url => {
    const adapterModule = '/src/lib/player/adapters/webcodecs.ts';
    const { WebCodecsAdapter } = await import(/* @vite-ignore */ adapterModule) as typeof import('../../lib/player/adapters/webcodecs');
    const root = document.createElement('div');
    const canvas = document.createElement('canvas');
    root.append(canvas);
    document.body.append(root);
    const adapter = new WebCodecsAdapter(canvas, root);
    const states: Array<{ phase: string; error: string | null; position: number; hasVideo: boolean | null }> = [];
    adapter.subscribe(state => states.push({ phase: state.phase, error: state.error, position: state.position, hasVideo: state.hasVideo }));
    await adapter.load({
      attempt: {
        id: 'webcodecs:fixture', adapter: 'webcodecs', method: 'webcodecs',
        url, sourceType: 'mkv', isLive: false, reason: 'Playwright encoded fixture',
      },
      position: 0,
      tracks: { audioId: null, subtitleId: null, audioLanguage: null, subtitleLanguage: null },
      subtitles: [],
      signal: new AbortController().signal,
    });
    const started = performance.now();
    while (!states.some(state => state.phase === 'playing' || state.phase === 'ended' || state.phase === 'error')) {
      if (performance.now() - started > 15_000) throw new Error(`WebCodecs timed out: ${JSON.stringify(states.at(-1))}`);
      await new Promise(resolve => setTimeout(resolve, 25));
    }
    while (!states.some(state => state.position > 0 || state.phase === 'ended' || state.phase === 'error')) {
      if (performance.now() - started > 15_000) throw new Error(`WebCodecs did not render: ${JSON.stringify(states.at(-1))}`);
      await new Promise(resolve => setTimeout(resolve, 25));
    }
    const result = { state: states.at(-1), width: canvas.width, height: canvas.height };
    await adapter.destroy();
    root.remove();
    return result;
  }, new URL(fixture('sample-av.mkv'), page.url()).href);

  expect(result.state?.phase, result.state?.error ?? 'WebCodecs entered error state').not.toBe('error');
  expect(result.state?.hasVideo).toBe(true);
  expect(result.state?.position).toBeGreaterThan(0);
  expect(result.width).toBe(320);
  expect(result.height).toBe(180);
  test.info().annotations.push({
    type: 'coverage',
    description: 'Native MPV remains manual-only in Tauri/libmpv environments.',
  });
});
