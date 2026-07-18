import { isDesktop } from './index';

/** A parsed Moonlit deep link with an action and query parameters. */
export interface MoonlitDeepLink {
  action: string;
  params: Record<string, string>;
}

/** Parse a moonlit:// URL; returns null for non-moonlit, malformed, or opaque URLs. */
export function parseMoonlitUrl(raw: string): MoonlitDeepLink | null {
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return null;
  }
  if (url.protocol !== 'moonlit:') return null;
  // moonlit://action → URL parses the action as host.
  // Host-only (no pathname fallback) to stay aligned with the Rust parser
  // in src-tauri/src/deeplink.rs, which is the source of truth.
  const action = url.host;
  if (!action) return null;
  const params: Record<string, string> = {};
  url.searchParams.forEach((value, key) => {
    params[key] = value;
  });
  return { action, params };
}

export async function onDeepLink(
  handler: (link: MoonlitDeepLink) => void,
): Promise<() => void> {
  if (!isDesktop()) return () => {};
  const { onOpenUrl } = await import('@tauri-apps/plugin-deep-link');
  const unlisten = await onOpenUrl((urls) => {
    for (const raw of urls) {
      const link = parseMoonlitUrl(raw);
      if (link) handler(link);
    }
  });
  return unlisten;
}
