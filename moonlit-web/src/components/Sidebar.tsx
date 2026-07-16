import { Link, useRouterState, useNavigate } from '@tanstack/react-router';
import { useAuth } from '@/app/AuthProvider';
import { ReactNode, useEffect } from 'react';
import { motion } from 'framer-motion';
import { SFSymbol } from '@/components/SFSymbol';
import { ProfileAvatar } from '@/components/ProfileAvatar';
import { SPRING } from '@/lib/design/motion';
import { isDesktop } from '@/lib/platform';

const navItems = [
  { href: '/home',    label: 'Home',    symbol: 'house.fill' },
  { href: '/search',  label: 'Search',  symbol: 'magnifyingglass' },
  { href: '/library', label: 'Library', symbol: 'book.fill' },
];

const allRoutes = [...navItems.map(n => n.href), '/settings'];

export function Sidebar({ children }: { children: ReactNode }) {
  const pathname = useRouterState({ select: s => s.location.pathname });
  const { currentProfile, selectProfile } = useAuth();
  const navigate = useNavigate();

  const activePath = pathname === '/' ? '/home' : pathname;

  // Desktop Ctrl+1-8 shortcuts
  useEffect(() => {
    if (!isDesktop()) return;
    function handleKey(e: KeyboardEvent) {
      if (e.ctrlKey && !e.metaKey && !e.altKey) {
        const idx = parseInt(e.key, 10);
        if (idx >= 1 && idx <= 8) {
          e.preventDefault();
          const routeIdx = (idx - 1) % allRoutes.length;
          navigate({ to: allRoutes[routeIdx] });
        }
      }
    }
    window.addEventListener('keydown', handleKey);
    return () => window.removeEventListener('keydown', handleKey);
  }, [navigate]);

  return (
    <div className="relative min-h-screen">
      {/* Floating pill navbar */}
      <nav className="fixed top-4 left-1/2 -translate-x-1/2 z-50 flex items-center gap-0.5 px-2.5 py-2 glass-liquid-capsule">

        {/* Brand wordmark */}
        <span className="brand-wordmark text-[14px] tracking-[2px] px-2 select-none">MOONLIT</span>

        <div className="w-px h-5 bg-white/10 mx-1" />

        {/* Nav links + settings */}
        {[...navItems, { href: '/settings', label: 'Settings', symbol: 'gear' }].map(({ href, label, symbol }) => {
          const active = activePath === href;
          return (
            <Link
              key={href}
              to={href}
              className="relative flex items-center gap-1.5 px-3.5 py-1.5 rounded-full text-[12.5px] font-semibold transition-colors duration-200"
              style={{ color: active ? '#FFFFFF' : undefined }}
            >
              {active && (
                <motion.div
                  layoutId="nav-active-pill"
                  transition={SPRING.nav}
                  className="absolute inset-0 rounded-full bg-white/10 border border-white/[0.12]"
                />
              )}
              <span className="relative z-10 flex items-center gap-1.5">
                <SFSymbol name={symbol} size={12.5} opacity={active ? 1 : 0.65} />
                <span className={active ? 'text-white' : 'text-white/65 group-hover:text-white'}>
                  {label}
                </span>
              </span>
            </Link>
          );
        })}

        {/* Separator + Profile */}
        {currentProfile && (
          <>
            <div className="w-px h-5 bg-white/10 mx-1.5" />
            <button
              onClick={() => { selectProfile(null as any); navigate({ to: '/profiles' }); }}
              className="flex items-center gap-2 pl-1 pr-3 py-1 rounded-full hover:bg-white/8 transition-colors group"
              aria-label="Switch profile"
              title={`Signed in as ${currentProfile.name}`}
            >
              <ProfileAvatar
                profile={currentProfile}
                size={30}
                className="ring-2 ring-white/20 group-hover:ring-white/35 transition-all"
              />
              <span className="text-[12.5px] font-semibold text-white/70 group-hover:text-white transition-colors leading-none">
                {currentProfile.name}
              </span>
            </button>
          </>
        )}
      </nav>

      {/* Page content — top padding clears the floating nav */}
      <main className="min-h-screen pt-16">
        {children}
      </main>
    </div>
  );
}
