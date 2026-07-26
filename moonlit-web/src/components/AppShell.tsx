import { ReactNode, useEffect, useState } from 'react';
import { Link, useRouterState, useNavigate } from '@tanstack/react-router';
import { useAuth } from '@/app/AuthProvider';
import { ProfileAvatar } from '@/components/ProfileAvatar';

interface AppShellProps {
  children: ReactNode;
}

const navItems = [
  { href: '/home',    label: 'Home' },
  { href: '/search',  label: 'Search' },
  { href: '/library', label: 'Library' },
];

export function AppShell({ children }: AppShellProps) {
  const pathname = useRouterState({ select: s => s.location.pathname });
  const { currentProfile, selectProfile } = useAuth();
  const navigate = useNavigate();

  const [scrolled, setScrolled] = useState(false);

  useEffect(() => {
    const handleScroll = () => setScrolled(window.scrollY > 48);
    window.addEventListener('scroll', handleScroll, { passive: true });
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  const activePath = pathname === '/' ? '/home' : pathname;

  return (
    <div className="relative min-h-screen bg-[#141414]">
      {/* Fixed header */}
      <header
        className={`fixed top-0 left-0 right-0 z-50 h-[56px] flex items-center px-6 transition-colors duration-300 ${
          scrolled ? 'bg-[#141414]' : 'bg-transparent'
        }`}
      >
        {/* Left: brand + nav */}
        <div className="flex items-center gap-8 flex-1">
          <Link to="/home" className="brand-wordmark text-[18px] text-[#e50914] select-none no-underline">
            MOONLIT
          </Link>

          <nav className="flex items-center gap-0">
            {navItems.map(({ href, label }) => {
              const active = activePath === href;
              return (
                <Link
                  key={href}
                  to={href}
                  className={`header-nav-link ${active ? 'active' : ''}`}
                >
                  {label}
                </Link>
              );
            })}
          </nav>
        </div>

        {/* Right: actions + profile */}
        <div className="flex items-center gap-5">
          <Link
            to="/settings"
            className={`header-nav-link ${activePath === '/settings' ? 'active' : ''}`}
          >
            Settings
          </Link>

          {currentProfile && (
            <button
              onClick={() => { selectProfile(null as any); navigate({ to: '/profiles' }); }}
              className="flex items-center gap-2 pl-1 pr-2 py-1 rounded hover:bg-white/10 transition-colors group"
              aria-label="Switch profile"
              title={`Signed in as ${currentProfile.name}`}
            >
              <ProfileAvatar
                profile={currentProfile}
                size={28}
                className="rounded-sm ring-1 ring-white/20 group-hover:ring-white/35 transition-all"
              />
              <svg className="w-3 h-3 text-white/60 group-hover:text-white transition-colors" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                <path d="M6 9l6 6 6-6" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </button>
          )}
        </div>
      </header>

      {/* Page content — top padding clears the fixed header */}
      <main className="min-h-screen pt-[56px]">
        {children}
      </main>
    </div>
  );
}
