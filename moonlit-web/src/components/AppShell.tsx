import { ReactNode } from 'react';
import { Link, useRouterState, useNavigate } from '@tanstack/react-router';
import { useAuth } from '@/app/AuthProvider';
import { ProfileAvatar } from '@/components/ProfileAvatar';

export function AppShell({ children }: { children: ReactNode }) {
  const pathname = useRouterState({ select: s => s.location.pathname });
  const { currentProfile } = useAuth();
  const navigate = useNavigate();

  const tabs = [
    { href: '/home',    label: 'Home' },
    { href: '/search',  label: 'Search' },
    { href: '/library', label: 'Library' },
  ];

  const activePath = pathname === '/' ? '/home' : pathname;

  return (
    <div className="relative min-h-screen">
      {/* Floating pill nav — matches Mac PillNavBar */}
      <nav className="fixed top-4 left-1/2 -translate-x-1/2 z-50 flex items-center gap-0.5 px-2.5 py-2 rounded-full glass-capsule">
        {/* Brand wordmark */}
        <span className="brand-wordmark text-[14px] px-2 select-none">MOONLIT</span>

        <div className="w-px h-5 bg-white/10 mx-1" />

        {/* Tab buttons */}
        {tabs.map(({ href, label }) => {
          const active = activePath === href || (href === '/home' && activePath.startsWith('/browse'));
          return (
            <Link key={href} to={href} className={`pill-tab ${active ? 'active' : ''}`}>
              {active && (
                <div className="absolute inset-0 rounded-full bg-white/10 border border-white/[0.12]" />
              )}
              <span className="relative z-10">{label}</span>
            </Link>
          );
        })}

        <div className="w-px h-5 bg-white/10 mx-1" />

        {/* Settings */}
        <Link to="/settings" className={`pill-tab ${activePath === '/settings' ? 'active' : ''}`}>
          {activePath === '/settings' && (
            <div className="absolute inset-0 rounded-full bg-white/10 border border-white/[0.12]" />
          )}
          <span className="relative z-10">Settings</span>
        </Link>

        {/* Profile */}
        {currentProfile && (
          <>
            <div className="w-px h-5 bg-white/10 mx-1.5" />
            <button
              onClick={() => navigate({ to: '/profiles' })}
              className="flex items-center gap-2 pl-1 pr-3 py-1 rounded-full hover:bg-white/8 transition-colors group"
              aria-label="Switch profile"
            >
              <ProfileAvatar profile={currentProfile} size={30} className="ring-2 ring-white/20 group-hover:ring-white/35 transition-all" />
              <span className="text-[12.5px] font-semibold text-white/70 group-hover:text-white transition-colors leading-none">
                {currentProfile.name}
              </span>
            </button>
          </>
        )}
      </nav>

      {/* Content area */}
      <main className="min-h-screen">
        {children}
      </main>
    </div>
  );
}
