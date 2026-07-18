export function GenreHubScreen({ genre, mediaKind }: { genre: string; mediaKind: 'movie' | 'series' }) {
  return <div className="p-8 pt-24 text-white/50">Genre Hub — {genre} ({mediaKind})</div>;
}
