type BadgeVariant = 'default' | 'success' | 'warning' | 'danger' | 'purple';

const variants: Record<BadgeVariant, string> = {
  default: 'bg-border text-muted',
  success: 'bg-green-100 text-green-700',
  warning: 'bg-amber-100 text-amber-700',
  danger: 'bg-red-100 text-red-600',
  purple: 'bg-accent-light text-accent',
};

export function Badge({ children, variant = 'default' }: { children: React.ReactNode; variant?: BadgeVariant }) {
  return (
    <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${variants[variant]}`}>
      {children}
    </span>
  );
}
