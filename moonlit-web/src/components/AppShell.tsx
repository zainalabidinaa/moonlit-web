import { type ReactNode, useEffect, useState } from 'react';
import { Link, useNavigate, useRouterState } from '@tanstack/react-router';

import { useAuth } from '@/app/AuthProvider';
import { ProfileAvatar } from '@/components/ProfileAvatar';

interface AppShellProps {
  children: ReactNode;
}

const primaryNavItems = [
  { href: '/home', label: 'Home' },
  { href: '/movies', label: 'Movies' },
  { href: '/series', label: 'Series' },
  { href: '/genre/Action', label: 'Genres' },
  { href: '/live', label: 'Live TV' },
  { href: '/watchlist', label: 'Watchlist' },
] as const;

function activePrimaryPath(pathname: string): string | null {
  if (pathname === '/' || pathname === '/home') return '/home';
  if (pathname === '/library' || pathname.startsWith('/watchlist')) return '/watchlist';
  if (pathname.startsWith('/movies')) return '/movies';
  if (pathname.startsWith('/series')) return '/series';
  if (pathname.startsWith('/genre/')) return '/genre/Action';
  if (pathname.startsWith('/live')) return '/live';
  if (pathname.startsWith('/browse/movie/')) return '/movies';
  if (pathname.startsWith('/browse/series/')) return '/series';
  return null;
}

export function AppShell({ children }: AppShellProps) {
  const pathname = useRouterState({ select: state => state.location.pathname });
  const { currentProfile, selectProfile } = useAuth();
  const navigate = useNavigate();
  const [scrolled, setScrolled] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);

  useEffect(() => {
    const handleScroll = () => setScrolled(window.scrollY > 48);
    handleScroll();
    window.addEventListener('scroll', handleScroll, { passive: true });
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  useEffect(() => {
    if (!menuOpen) return;
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setMenuOpen(false);
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [menuOpen]);

  const activePath = activePrimaryPath(pathname);
  const headerOverArtwork = pathname === '/home'
    || pathname === '/movies'
    || pathname === '/series'
    || pathname.startsWith('/browse/');

  const navigationLinks = primaryNavItems.map(({ href, label }) => {
    const active = activePath === href;
    return (
      <Link
        key={href}
        to={href}
        aria-current={active ? 'page' : undefined}
        onClick={() => setMenuOpen(false)}
        className={`header-nav-link ${active ? 'active' : ''}`}
      >
        {label}
      </Link>
    );
  });

  return (
    <div className="relative min-h-screen bg-moonlit-bg">
      <a href="#main-content" className="skip-link">Skip to content</a>
      <header className={`app-navbar ${scrolled ? 'app-navbar-scrolled' : ''}`}>
        <div className="flex min-w-0 flex-1 items-center gap-5 xl:gap-8">
          <Link
            to="/home"
            aria-label="Moonlit home"
            className="flex shrink-0 items-center gap-2.5 no-underline"
          >
            <img
              src="/moonlit-icon.png"
              alt="Moonlit"
              className="h-8 w-8 rounded-[8px] object-cover shadow-ml-glass"
            />
            <span className="brand-wordmark font-brand text-[16px] text-white sm:text-[18px]">MOONLIT</span>
          </Link>

          <nav aria-label="Primary" className="hidden items-center lg:flex">
            {navigationLinks}
          </nav>
        </div>

        <div className="hidden items-center gap-1 lg:flex">
          <Link
            to="/search"
            aria-current={pathname === '/search' ? 'page' : undefined}
            className={`header-nav-link ${pathname === '/search' ? 'active' : ''}`}
          >
            Search
          </Link>
          <Link
            to="/settings"
            aria-current={pathname === '/settings' ? 'page' : undefined}
            className={`header-nav-link ${pathname === '/settings' ? 'active' : ''}`}
          >
            Settings
          </Link>

          {currentProfile && (
            <button
              type="button"
              onClick={() => { selectProfile(null); navigate({ to: '/profiles' }); }}
              className="ml-2 flex min-h-11 items-center gap-2 rounded-ml-ctl px-2 transition-colors hover:bg-white/10"
              aria-label="Switch profile"
              title={`Signed in as ${currentProfile.name}`}
            >
              <ProfileAvatar
                profile={currentProfile}
                size={30}
                className="rounded-ml-sm ring-1 ring-white/20 transition-all hover:ring-white/35"
              />
              <svg aria-hidden="true" className="h-3 w-3 text-white/60" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                <path d="M6 9l6 6 6-6" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </button>
          )}
        </div>

        <button
          type="button"
          aria-label={`${menuOpen ? 'Close' : 'Open'} navigation menu`}
          aria-expanded={menuOpen}
          aria-controls="mobile-navigation"
          onClick={() => setMenuOpen(open => !open)}
          className="ml-3 flex h-11 w-11 shrink-0 items-center justify-center rounded-ml-ctl text-white transition-colors hover:bg-white/10 lg:hidden"
        >
          {menuOpen ? (
            <svg aria-hidden="true" viewBox="0 0 24 24" className="h-5 w-5" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
              <path d="M6 6l12 12M18 6L6 18" />
            </svg>
          ) : (
            <svg aria-hidden="true" viewBox="0 0 24 24" className="h-5 w-5" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
              <path d="M4 7h16M4 12h16M4 17h16" />
            </svg>
          )}
        </button>
      </header>

      {menuOpen && (
        <nav
          id="mobile-navigation"
          aria-label="Mobile"
          className="glass-panel fixed inset-x-3 top-[60px] z-40 flex flex-col gap-1 rounded-ml-lg p-2 lg:hidden"
        >
          {navigationLinks}
          <div className="my-1 h-px bg-white/10" />
          <Link to="/search" onClick={() => setMenuOpen(false)} className={`header-nav-link ${pathname === '/search' ? 'active' : ''}`}>Search</Link>
          <Link to="/settings" onClick={() => setMenuOpen(false)} className={`header-nav-link ${pathname === '/settings' ? 'active' : ''}`}>Settings</Link>
          {currentProfile && (
            <button
              type="button"
              onClick={() => { selectProfile(null); navigate({ to: '/profiles' }); }}
              className="header-nav-link flex min-h-11 items-center gap-3 text-left"
            >
              <ProfileAvatar profile={currentProfile} size={28} className="rounded-ml-sm" />
              Switch profile
            </button>
          )}
        </nav>
      )}

      <main id="main-content" tabIndex={-1} className={`min-h-screen ${headerOverArtwork ? '' : 'pt-14'}`}>{children}</main>
    </div>
  );
}
