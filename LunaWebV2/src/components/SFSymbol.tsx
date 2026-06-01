interface SFSymbolProps {
  name: string;
  size?: number;
  className?: string;
  opacity?: number;
}

export function SFSymbol({ name, size = 20, className = '', opacity = 1 }: SFSymbolProps) {
  return (
    <img
      src={`/sf-symbols/${name}.png`}
      alt={name}
      width={size}
      height={size}
      className={className}
      style={{ opacity }}
      draggable={false}
    />
  );
}
