export function LanguageHubScreen({ iso, name }: { iso: string; name: string }) {
  return <div className="p-8 pt-24 text-white/50">Language Hub — {name} ({iso})</div>;
}
