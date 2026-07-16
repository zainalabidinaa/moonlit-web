import { isDesktop } from './index';

export interface MoonlitDeepLink {
  action: string;
  params: Record<string, string>;
}

export function parseMoonlitUrl(raw: string): MoonlitDeepLink | null {
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return null;
  }
  if (url.protocol !== 'moonlit:') return null;
  const action = url.host || url.pathname.replace(/^\/+/, '');
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
