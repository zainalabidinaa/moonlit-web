import { useState } from 'react';
import { useAuth } from '../../context/AuthContext';
import { AppShell } from '../../components/layout/AppShell';
import { Card } from '../../components/ui/Card';
import { Button } from '../../components/ui/Button';
import { Badge } from '../../components/ui/Badge';
import type { UserRole } from '../../types';

const PLAN_LABELS: Record<UserRole, string> = {
  admin: 'Admin',
  friends_family: 'Friends & Family',
  premium: 'Premium',
  premium_plus: 'Premium+',
};

export default function BillingPage() {
  const { role, session } = useAuth();
  const [loading, setLoading] = useState(false);

  const isBilledPlan = role === 'premium' || role === 'premium_plus';

  async function openCustomerPortal() {
    if (!session) return;
    setLoading(true);
    const res = await fetch(`${import.meta.env.VITE_SUPABASE_FUNCTIONS_URL}/create-checkout-session`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${session.access_token}` },
      body: JSON.stringify({ action: 'portal' }),
    });
    const { url } = await res.json();
    if (url) window.location.href = url;
    setLoading(false);
  }

  return (
    <AppShell>
      <div className="max-w-lg mx-auto">
        <h1 className="text-2xl font-bold text-text mb-6">Billing</h1>

        <Card className="p-6 flex flex-col gap-4">
          <div className="flex items-center justify-between">
            <p className="text-sm font-medium text-text">Current Plan</p>
            <Badge variant="purple">{role ? PLAN_LABELS[role] : '—'}</Badge>
          </div>

          {role === 'friends_family' && (
            <p className="text-sm text-muted">Your access was granted by invitation. No billing required.</p>
          )}

          {role === 'admin' && (
            <p className="text-sm text-muted">You manage this Luna instance. No subscription required.</p>
          )}

          {isBilledPlan && (
            <div className="border-t border-border pt-4">
              <p className="text-xs text-muted mb-3">Manage your subscription, update payment method, or cancel through the billing portal.</p>
              <Button onClick={openCustomerPortal} loading={loading} variant="secondary">
                Manage Billing
              </Button>
            </div>
          )}
        </Card>
      </div>
    </AppShell>
  );
}
