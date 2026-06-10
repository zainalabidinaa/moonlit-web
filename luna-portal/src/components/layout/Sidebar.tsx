import { NavLink } from 'react-router-dom';
import { useAuth } from '../../context/AuthContext';

const userLinks = [
  { to: '/profiles', label: 'Profiles' },
  { to: '/addons', label: 'Add-ons' },
  { to: '/billing', label: 'Billing' },
];

const adminLinks = [
  { to: '/admin/catalog', label: 'Catalog' },
  { to: '/admin/users', label: 'Users' },
  { to: '/admin/invites', label: 'Invites' },
];

export function Sidebar() {
  const { role } = useAuth();

  const links = role === 'admin' ? [...adminLinks, ...userLinks] : userLinks;

  return (
    <aside className="w-48 bg-surface border-r border-border flex flex-col py-6 gap-1 shrink-0">
      {links.map(({ to, label }) => (
        <NavLink
          key={to}
          to={to}
          className={({ isActive }) =>
            `mx-2 px-3 py-2 rounded-lg text-sm transition-colors ${isActive ? 'bg-accent-light text-accent font-medium' : 'text-muted hover:text-text hover:bg-border'}`
          }
        >
          {label}
        </NavLink>
      ))}
    </aside>
  );
}
