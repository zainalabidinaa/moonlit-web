'use client';

import { useAuth } from './AuthProvider';
import { useRouter } from 'next/navigation';
import { useEffect } from 'react';

export default function Page() {
  const { user, currentProfile, isLoading } = useAuth();
  const router = useRouter();

  useEffect(() => {
    if (isLoading) return;
    if (!user) {
      router.replace('/auth');
    } else if (!currentProfile) {
      router.replace('/profiles');
    } else {
      router.replace('/home');
    }
  }, [user, currentProfile, isLoading, router]);

  return (
    <div className="flex items-center justify-center min-h-screen">
      <div className="animate-spin rounded-full h-8 w-8 border-2 border-luna-accent border-t-transparent" />
    </div>
  );
}
