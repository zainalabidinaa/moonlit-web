import { HTMLAttributes } from 'react';

export function Card({ children, className = '', ...rest }: HTMLAttributes<HTMLDivElement>) {
  return (
    <div className={`bg-surface rounded-2xl border border-border shadow-sm ${className}`} {...rest}>
      {children}
    </div>
  );
}
