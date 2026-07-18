interface ProfileAvatarProps {
  src?: string;
  name: string;
  size?: number;
  showBadge?: boolean;
}

function initials(name: string): string {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((p) => p[0].toUpperCase())
    .join('');
}

export default function ProfileAvatar({ src, name, size = 30, showBadge }: ProfileAvatarProps) {
  return (
    <div className="relative inline-flex flex-shrink-0" style={{ width: size, height: size }}>
      {src ? (
        <img
          src={src}
          alt={name}
          className="w-full h-full rounded-full object-cover ring-2 ring-white/20"
        />
      ) : (
        <div
          className="w-full h-full rounded-full ring-2 ring-white/20 bg-moonlit-elevated flex items-center justify-center text-white/70 font-semibold"
          style={{ fontSize: size * 0.38 }}
        >
          {initials(name)}
        </div>
      )}
      {showBadge && (
        <span className="absolute -bottom-1 -right-1 w-3 h-3 bg-moonlit-gold rounded-full ring-2 ring-moonlit-bg" />
      )}
    </div>
  );
}
