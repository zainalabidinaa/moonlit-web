export function DetailScreen({ type, id }: { type: string; id: string }) {
  return <div className="p-8 pt-24 text-white/50">Detail — {type}/{id}</div>;
}
