import { Link, NavLink, useNavigate } from 'react-router-dom';
import { useAuth } from '../../context/AuthContext';
import { supabase } from '../../lib/supabase';
import { Button } from '../ui/Button';

const linkBase =
  'relative whitespace-nowrap rounded-full px-3.5 py-2 text-sm font-medium font-body transition-colors';

function navClass({ isActive }: { isActive: boolean }) {
  return `${linkBase} ${isActive ? 'text-accent' : 'text-muted hover:text-text'}`;
}

/** Underline shown under the active link. */
function ActiveBar({ show }: { show: boolean }) {
  if (!show) return null;
  return (
    <span className="pointer-events-none absolute inset-x-3.5 bottom-0.5 h-0.5 rounded bg-accent shadow-glow" />
  );
}

export function Navbar() {
  const { session, role } = useAuth();
  const navigate = useNavigate();
  const isAdmin = role === 'admin';

  async function handleSignOut() {
    await supabase.auth.signOut();
    navigate('/');
  }

  return (
    <header className="sticky top-0 z-50 border-b border-border bg-bg/75 backdrop-blur-xl">
      <div className="mx-auto flex max-w-7xl items-center gap-5 px-5 py-3.5">
        <Link to="/" className="flex flex-none items-center gap-2 font-display text-xl font-extrabold tracking-tight">
          <span
            className="h-5 w-5 rounded-full shadow-glow"
            style={{ background: 'radial-gradient(circle at 32% 30%, #fa824d, #ff6a2b 60%, #8a3500)' }}
          />
          NIGHTARC
        </Link>

        <nav className="mx-auto flex items-center gap-0.5 overflow-x-auto [scrollbar-width:none]">
          <NavLink to="/" end className={navClass}>
            {({ isActive }) => (<>Home<ActiveBar show={isActive} /></>)}
          </NavLink>
          <NavLink to="/catalog" className={navClass}>
            {({ isActive }) => (<>Catalog<ActiveBar show={isActive} /></>)}
          </NavLink>
          {!session && (
            <NavLink to="/pricing" className={navClass}>
              {({ isActive }) => (<>Pricing<ActiveBar show={isActive} /></>)}
            </NavLink>
          )}
          {session && (
            <>
              <NavLink to="/profiles" className={navClass}>
                {({ isActive }) => (<>Profiles<ActiveBar show={isActive} /></>)}
              </NavLink>
              <NavLink to="/addons" className={navClass}>
                {({ isActive }) => (<>Addons<ActiveBar show={isActive} /></>)}
              </NavLink>
              <NavLink to="/billing" className={navClass}>
                {({ isActive }) => (<>Billing<ActiveBar show={isActive} /></>)}
              </NavLink>
            </>
          )}
          {isAdmin && (
            <>
              <span className="mx-2 h-4 w-px flex-none bg-border" />
              <NavLink to="/admin/catalog" className={navClass}>
                {({ isActive }) => (<>Collections<ActiveBar show={isActive} /></>)}
              </NavLink>
              <NavLink to="/admin/templates" className={navClass}>
                {({ isActive }) => (<>Templates<ActiveBar show={isActive} /></>)}
              </NavLink>
              <NavLink to="/admin/users" className={navClass}>
                {({ isActive }) => (<>Users<ActiveBar show={isActive} /></>)}
              </NavLink>
              <NavLink to="/admin/invites" className={navClass}>
                {({ isActive }) => (<>Invites<ActiveBar show={isActive} /></>)}
              </NavLink>
            </>
          )}
        </nav>

        <div className="flex flex-none items-center gap-3">
          {isAdmin && (
            <span className="hidden items-center gap-2 rounded-full border border-accent/40 px-3 py-1.5 font-mono text-[10px] uppercase tracking-widest text-accent sm:flex">
              <span className="h-2 w-2 rounded-full bg-accent shadow-glow" />
              Admin
            </span>
          )}
          {session ? (
            <Button variant="ghost" size="sm" onClick={handleSignOut}>Sign out</Button>
          ) : (
            <>
              <Button variant="ghost" size="sm" onClick={() => navigate('/login')}>Sign in</Button>
              <Button size="sm" onClick={() => navigate('/pricing')}>Get Nightarc</Button>
            </>
          )}
        </div>
      </div>
    </header>
  );
}
