'use client';
import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useAdminAuth } from '../components/AdminAuthProvider';

export default function RootPage() {
  const { user, isLoading } = useAdminAuth();
  const router = useRouter();
  useEffect(() => {
    if (isLoading) return;
    router.replace(user ? '/dashboard' : '/login');
  }, [user, isLoading]);
  return (
    <div className="flex items-center justify-center min-h-screen bg-luna-bg">
      <div className="animate-spin rounded-full h-6 w-6 border-2 border-luna-accent border-t-transparent" />
    </div>
  );
}
