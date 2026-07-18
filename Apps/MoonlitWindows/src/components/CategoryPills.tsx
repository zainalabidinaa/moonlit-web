interface CategoryPillsProps {
  categories: { id: string; label: string }[];
  selected: string | null;
  onSelect: (id: string) => void;
  label?: string;
  horizontal?: boolean;
}

export default function CategoryPills({
  categories,
  selected,
  onSelect,
  label,
  horizontal = true,
}: CategoryPillsProps) {
  const pills = (
    <div
      className={`flex gap-2 ${horizontal ? 'flex-row overflow-x-auto scrollbar-hide fade-mask-r' : 'flex-wrap'}`}
    >
      {categories.map((cat) => (
        <button
          key={cat.id}
          type="button"
          onClick={() => onSelect(cat.id)}
          className={`category-pill ${selected === cat.id ? 'category-pill-active' : 'category-pill-idle'}`}
        >
          {cat.label}
        </button>
      ))}
    </div>
  );

  if (label) {
    return (
      <div className="flex flex-col gap-[11px]">
        <h2 className="text-[22px] font-bold text-white">{label}</h2>
        {pills}
      </div>
    );
  }

  return pills;
}
