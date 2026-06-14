import { useNavigate } from 'react-router-dom';
import { Button } from '../../components/ui/Button';
import { Card } from '../../components/ui/Card';
import { Navbar } from '../../components/layout/Navbar';

const plans = [
  {
    id: 'friends_family',
    name: 'Friends & Family',
    price: null,
    description: 'Personal invitation only. Full access, zero setup.',
    features: ['All content, ready to watch', 'Managed for you', 'Up to 5 profiles', 'Invite code required'],
    cta: 'Request Access',
    ctaTo: '/signup?tab=invite',
    highlight: false,
  },
  {
    id: 'premium',
    name: 'Premium',
    price: '$9.99',
    description: 'Everything set up and ready to go. Just sign in and watch.',
    features: ['Full catalog access', 'Pre-configured', 'Up to 5 profiles', 'HD streaming'],
    cta: 'Get Started',
    ctaTo: '/signup?plan=premium',
    highlight: true,
  },
  {
    id: 'premium_plus',
    name: 'Premium+',
    price: '$14.99',
    description: 'All of Premium, plus you control your own add-ons and sources.',
    features: ['Everything in Premium', 'Self-managed add-ons', 'Custom sources', 'Priority support'],
    cta: 'Get Started',
    ctaTo: '/signup?plan=premium_plus',
    highlight: false,
  },
];

export default function PricingPage() {
  const navigate = useNavigate();

  return (
    <div className="min-h-screen bg-bg">
      <Navbar />
      <div className="max-w-5xl mx-auto px-6 py-20">
        <div className="text-center mb-14">
          <h1 className="text-4xl font-bold text-text tracking-tight mb-3">Simple, honest pricing</h1>
          <p className="text-muted text-lg">Pick the plan that fits how you watch.</p>
        </div>

        <div className="grid md:grid-cols-3 gap-6">
          {plans.map(plan => (
            <Card
              key={plan.id}
              className={`p-6 flex flex-col gap-5 ${plan.highlight ? 'ring-2 ring-accent shadow-lg' : ''}`}
            >
              {plan.highlight && (
                <span className="self-start text-xs font-semibold bg-accent-light text-accent px-2.5 py-1 rounded-full">Most Popular</span>
              )}
              <div>
                <h2 className="text-lg font-semibold text-text">{plan.name}</h2>
                {plan.price ? (
                  <p className="text-3xl font-bold text-text mt-1">{plan.price}<span className="text-sm font-normal text-muted">/mo</span></p>
                ) : (
                  <p className="text-sm text-muted mt-1">By invitation</p>
                )}
                <p className="text-sm text-muted mt-2">{plan.description}</p>
              </div>
              <ul className="flex flex-col gap-2 flex-1">
                {plan.features.map(f => (
                  <li key={f} className="flex items-center gap-2 text-sm text-text">
                    <span className="text-accent">&#10003;</span> {f}
                  </li>
                ))}
              </ul>
              <Button
                variant={plan.highlight ? 'primary' : 'secondary'}
                className="w-full"
                onClick={() => navigate(plan.ctaTo)}
              >
                {plan.cta}
              </Button>
            </Card>
          ))}
        </div>
      </div>
    </div>
  );
}
