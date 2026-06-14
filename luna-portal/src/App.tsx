import { BrowserRouter, Routes, Route } from 'react-router-dom';
import { AuthProvider } from './context/AuthContext';
import { PublicRoute, UserRoute, AdminRoute } from './components/layout/RouteGuards';
import LandingPage from './routes/public/LandingPage';
import PricingPage from './routes/public/PricingPage';
import LoginPage from './routes/public/LoginPage';
import SignupPage from './routes/public/SignupPage';
import ProfilesPage from './routes/user/ProfilesPage';
import AddonsPage from './routes/user/AddonsPage';
import BillingPage from './routes/user/BillingPage';
import CatalogPage from './routes/admin/CatalogPage';
import UsersPage from './routes/admin/UsersPage';
import InvitesPage from './routes/admin/InvitesPage';

export default function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <Routes>
          {/* Public */}
          <Route path="/" element={<LandingPage />} />
          <Route path="/pricing" element={<PublicRoute><PricingPage /></PublicRoute>} />
          <Route path="/login" element={<PublicRoute><LoginPage /></PublicRoute>} />
          <Route path="/signup" element={<PublicRoute><SignupPage /></PublicRoute>} />

          {/* User */}
          <Route path="/profiles" element={<UserRoute><ProfilesPage /></UserRoute>} />
          <Route path="/addons" element={<UserRoute><AddonsPage /></UserRoute>} />
          <Route path="/billing" element={<UserRoute><BillingPage /></UserRoute>} />

          {/* Admin */}
          <Route path="/admin/catalog" element={<AdminRoute><CatalogPage /></AdminRoute>} />
          <Route path="/admin/users" element={<AdminRoute><UsersPage /></AdminRoute>} />
          <Route path="/admin/invites" element={<AdminRoute><InvitesPage /></AdminRoute>} />

          <Route path="*" element={<div className="min-h-screen bg-bg flex items-center justify-center"><p className="text-muted">Page not found</p></div>} />
        </Routes>
      </AuthProvider>
    </BrowserRouter>
  );
}
