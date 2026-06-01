import Image from 'next/image';

interface SFSymbolProps {
  name: string;
  size?: number;
  className?: string;
  opacity?: number;
}

/**
 * Renders an SF Symbol PNG from /public/sf-symbols/{name}.png
 * All symbols are white on transparent — works on dark backgrounds.
 * Use `opacity` (0-1) to dim inactive states.
 */
export function SFSymbol({ name, size = 20, className = '', opacity = 1 }: SFSymbolProps) {
  return (
    <Image
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
