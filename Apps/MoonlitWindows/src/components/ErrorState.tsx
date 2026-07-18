import { AlertTriangle } from 'lucide-react';
import EmptyState from './EmptyState';

interface ErrorStateProps {
  title: string;
  message?: string;
  onRetry?: () => void;
}

export default function ErrorState({ title, message, onRetry }: ErrorStateProps) {
  return (
    <EmptyState
      icon={<AlertTriangle size={22} />}
      title={title}
      message={message}
      action={onRetry ? { label: 'Retry', onClick: onRetry } : undefined}
    />
  );
}
