import { InputHTMLAttributes, forwardRef } from 'react';

interface InputProps extends InputHTMLAttributes<HTMLInputElement> {
  label?: string;
  error?: string;
}

export const Input = forwardRef<HTMLInputElement, InputProps>(
  ({ label, error, className = '', id, ...rest }, ref) => (
    <div className="flex flex-col gap-1">
      {label && <label htmlFor={id} className="text-sm font-medium text-text">{label}</label>}
      <input
        id={id}
        ref={ref}
        className={`w-full px-3 py-2 rounded-lg border text-sm transition-colors outline-none
          ${error ? 'border-red-400 focus:border-red-500' : 'border-border focus:border-accent'}
          bg-surface text-text placeholder:text-muted ${className}`}
        {...rest}
      />
      {error && <p className="text-xs text-red-500">{error}</p>}
    </div>
  )
);
Input.displayName = 'Input';
