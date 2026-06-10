import { Link, useNavigate } from 'react-router-dom';
import { useAuth } from '../../context/AuthContext';
import { supabase } from '../../lib/supabase';
import { Button } from '../ui/Button';

export function Navbar() {
  const { session, role } = useAuth();
  const navigate = useNavigate();

  async function handleSignOut() {
    await supabase.auth.signOut();
    navigate('/pricing');
  }

  return (
    <nav className="h-14 bg-surface border-b border-border flex items-center px-6 gap-4">
      <Link to="/" className="text-lg font-bold text-text tracking-tight">Luna</Link>
      <div className="flex-1" />
      {session ? (
        <>
          {role === 'admin' && (
            <Link to="/admin/catalog" className="text-sm text-muted hover:text-text transition-colors">Admin</Link>
          )}
          <Link to="/profiles" className="text-sm text-muted hover:text-text transition-colors">Profiles</Link>
          <Button variant="ghost" size="sm" onClick={handleSignOut}>Sign out</Button>
        </>
      ) : (
        <>
          <Link to="/pricing" className="text-sm text-muted hover:text-text transition-colors">Pricing</Link>
          <Button size="sm" onClick={() => navigate('/login')}>Sign in</Button>
        </>
      )}
    </nav>
  );
}
