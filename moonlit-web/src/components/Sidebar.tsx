import { Link, useRouterState, useNavigate } from '@tanstack/react-router';
import { useAuth } from '@/app/AuthProvider';
import { ReactNode } from 'react';
import { SFSymbol } from '@/components/SFSymbol';

const navItems = [
  { href: '/home',    label: 'Home',    symbol: 'house.fill' },
  { href: '/search',  label: 'Search',  symbol: 'magnifyingglass' },
  { href: '/library', label: 'Library', symbol: 'book.fill' },
];

const adminItems = [
  { href: '/admin', label: 'Admin', symbol: 'person.fill' },
];

// Deterministic pastel gradient from a string seed (used when no avatar_color set)
function avatarGradient(seed: string): string {
  let h = 0;
  for (let i = 0; i < seed.length; i++) h = (h * 31 + seed.charCodeAt(i)) & 0xffffffff;
  const hue = Math.abs(h) % 360;
  return `linear-gradient(135deg, hsl(${hue},65%,52%), hsl(${(hue + 40) % 360},70%,42%))`;
}

export function Sidebar({ children }: { children: ReactNode }) {
  const pathname = useRouterState({ select: s => s.location.pathname });
  const { currentProfile, selectProfile } = useAuth();
  const navigate = useNavigate();
  const isAdmin = currentProfile?.role === 'admin';

  return (
    <div className="relative min-h-screen">
      {/* Floating pill navbar */}
      <nav className="fixed top-4 left-1/2 -translate-x-1/2 z-50 flex items-center gap-0.5 px-2 py-2 rounded-full shadow-xl shadow-black/50"
        style={{ background: 'rgba(18,18,22,0.80)', backdropFilter: 'blur(24px) saturate(1.6)', border: '1px solid rgba(255,255,255,0.09)' }}>

        {/* Nav links */}
        {navItems.map(({ href, label, symbol }) => {
          const active = pathname === href || (href === '/home' && pathname === '/');
          return (
            <Link
              key={href}
              to={href}
              className={`flex items-center gap-1.5 px-4 py-1.5 rounded-full text-[13px] font-medium transition-all duration-200 ${
                active
                  ? 'bg-moonlit-accent/90 text-white shadow-[0_0_12px_rgba(139,92,246,0.45)]'
                  : 'text-white/50 hover:text-white hover:bg-white/8'
              }`}
            >
              <SFSymbol name={symbol} size={13} opacity={active ? 1 : 0.55} />
              <span>{label}</span>
            </Link>
          );
        })}

        {/* Settings link */}
        <Link
          to="/settings"
          className={`flex items-center gap-1.5 px-4 py-1.5 rounded-full text-[13px] font-medium transition-all duration-200 ${
            pathname === '/settings'
              ? 'bg-moonlit-accent/90 text-white shadow-[0_0_12px_rgba(139,92,246,0.45)]'
              : 'text-white/50 hover:text-white hover:bg-white/8'
          }`}
        >
          <SFSymbol name="gear" size={13} opacity={pathname === '/settings' ? 1 : 0.55} />
          <span>Settings</span>
        </Link>

        {isAdmin && adminItems.map(({ href, label, symbol }) => (
          <Link
            key={href}
            to={href}
            className={`flex items-center gap-1.5 px-4 py-1.5 rounded-full text-[13px] font-medium transition-all duration-200 ${
              pathname === href
                ? 'bg-moonlit-accent/90 text-white shadow-[0_0_12px_rgba(139,92,246,0.45)]'
                : 'text-white/50 hover:text-white hover:bg-white/8'
            }`}
          >
            <SFSymbol name={symbol} size={13} opacity={pathname === href ? 1 : 0.55} />
            <span>{label}</span>
          </Link>
        ))}

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
              {/* Avatar circle */}
              <div
                className="w-7 h-7 rounded-full flex items-center justify-center text-[11px] font-black text-white select-none ring-2 ring-white/20 group-hover:ring-white/35 transition-all"
                style={{ background: currentProfile.avatar_color ? currentProfile.avatar_color : avatarGradient(currentProfile.name) }}
              >
                {currentProfile.name[0].toUpperCase()}
              </div>
              <span className="text-[13px] font-medium text-white/70 group-hover:text-white transition-colors leading-none">
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
