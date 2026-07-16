import { useEffect } from 'react';
import { useAuth } from '@/app/AuthProvider';
import { useNavigate } from '@tanstack/react-router';

export default function IndexPage() {
  const { user, currentProfile, isLoading } = useAuth();
  const navigate = useNavigate();

  useEffect(() => {
    if (isLoading) return;
    if (!user) navigate({ to: '/auth', replace: true });
    else if (!currentProfile) navigate({ to: '/profiles', replace: true });
    else navigate({ to: '/home', replace: true });
  }, [user, currentProfile, isLoading, navigate]);

  return (
    <div className="flex items-center justify-center min-h-screen">
      <div className="w-7 h-7 rounded-full border-2 border-white/[0.14] border-t-white animate-spin-arc" />
    </div>
  );
}
