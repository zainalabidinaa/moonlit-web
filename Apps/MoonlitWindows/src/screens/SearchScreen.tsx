export function SearchScreen({ onClose }: { onClose: () => void }) {
  return (
    <div className="fixed inset-0 z-50 bg-moonlit-bg flex flex-col">
      <div className="p-4 pt-24 flex items-center gap-4">
        <button onClick={onClose} className="text-white/50 hover:text-white">Close</button>
        <input
          autoFocus
          placeholder="Search..."
          className="flex-1 bg-moonlit-surface border border-white/10 rounded-lg px-4 py-2 text-white placeholder:text-white/30 outline-none"
        />
      </div>
      <div className="flex-1 p-8 text-white/30">Search results appear here</div>
    </div>
  );
}
