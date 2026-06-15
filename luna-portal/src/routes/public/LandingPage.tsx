import { useNavigate } from 'react-router-dom';
import { Navbar } from '../../components/layout/Navbar';
import { Button } from '../../components/ui/Button';

const chips = ['4K • HDR', 'Multi-profile', 'Curated collections', 'iOS · Mac · Web'];

const vibes = [
  { name: 'Cinema', desc: 'Hand-picked films, franchise stacks & 4K showcases.', seed: 'coll-movies', glow: 'rgba(250,130,77,.5)' },
  { name: 'Series', desc: 'Trending shows, bingeable seasons, continue-watching that follows you.', seed: 'coll-tv', glow: 'rgba(52,230,200,.45)' },
  { name: 'Live & UK TV', desc: 'Channels, sports and curated live rows built by your admin.', seed: 'coll-live', glow: 'rgba(255,77,210,.45)' },
];

const stats = [
  { n: '∞', l: 'Collections per account' },
  { n: '6', l: 'Profiles included' },
  { n: '0', l: 'Ads, ever' },
];

const plans = [
  {
    name: 'Premium', price: '$9.99', unit: '/mo', highlight: false,
    features: ['2 simultaneous streams', 'Up to 6 profiles', 'Full curated catalog', 'iOS · Mac · Web'],
    cta: 'Choose Premium', to: '/signup?plan=premium',
  },
  {
    name: 'Premium+', price: '$14.99', unit: '/mo', highlight: true,
    features: ['4 simultaneous streams in 4K HDR', 'Unlimited profiles', 'Personal addon slots', 'Priority stream warm-up', 'Early access features'],
    cta: 'Choose Premium+', to: '/signup?plan=premium_plus',
  },
  {
    name: 'Friends & Family', price: 'Invite', unit: 'only', highlight: false,
    features: ['Granted by an admin', 'Shared household catalog', 'Personal profile & library', 'No billing'],
    cta: 'Have a code?', to: '/signup?tab=invite',
  },
];

function Marquee({ items }: { items: string[] }) {
  const row = (
    <span className="flex items-center gap-12">
      {items.map((t) => (
        <span key={t} className="flex items-center gap-12">
          {t}
          <span className="text-accent">●</span>
        </span>
      ))}
    </span>
  );
  return (
    <div className="overflow-hidden border-y border-border bg-bg2 py-3.5">
      <div className="flex w-max gap-12 whitespace-nowrap font-display text-[15px] font-extrabold tracking-wide text-faint animate-marquee">
        {row}
        {row}
      </div>
    </div>
  );
}

export default function LandingPage() {
  const navigate = useNavigate();

  return (
    <div className="min-h-screen bg-bg">
      <Navbar />

      {/* HERO */}
      <section className="mx-auto max-w-7xl px-5 pb-8 pt-16">
        <div className="grid items-center gap-8 lg:grid-cols-[1.05fr_.95fr]">
          <div>
            <p className="mb-4 font-mono text-[11px] uppercase tracking-[0.28em] text-accent">
              Your own private streaming universe
            </p>
            <h1 className="font-display text-[clamp(48px,7vw,104px)] font-extrabold uppercase leading-[1.02]">
              Every screen.<br />
              One <span className="text-accent" style={{ textShadow: '0 0 40px var(--accent-glow)' }}>Nightarc.</span>
            </h1>
            <p className="mt-5 max-w-md text-[17px] text-muted">
              A members-only streaming platform built on the Stremio engine — curated collections,
              gorgeous artwork, and your whole household on every device.
            </p>
            <div className="mt-7 flex flex-wrap gap-3">
              <Button size="lg" className="rounded-full" onClick={() => navigate('/pricing')}>Get Nightarc →</Button>
              <Button variant="ghost" size="lg" className="rounded-full" onClick={() => navigate('/login')}>Sign in</Button>
            </div>
            <div className="mt-7 flex flex-wrap gap-2.5">
              {chips.map((c) => (
                <span key={c} className="rounded-full border border-border bg-surface px-3.5 py-1.5 font-mono text-xs tracking-wide text-muted">
                  {c}
                </span>
              ))}
            </div>
          </div>

          <div className="relative h-[400px] overflow-hidden rounded-3xl border border-border shadow-2xl lg:h-[480px]">
            <img src="https://picsum.photos/seed/lunahero88/900/1000" alt="" className="h-full w-full object-cover" />
            <div
              className="absolute inset-0"
              style={{ background: 'linear-gradient(160deg,rgba(250,130,77,.14),transparent 40%),linear-gradient(0deg,rgba(13,6,4,.88),transparent 55%)' }}
            />
            <div className="absolute inset-x-4 bottom-4 flex items-center gap-3.5 rounded-2xl border border-border bg-bg2/70 p-4 backdrop-blur-md">
              <span className="h-16 w-12 flex-none rounded-lg shadow-glow" style={{ background: 'linear-gradient(160deg,#fa824d,#ff6a2b)' }} />
              <div>
                <div className="font-display text-lg font-extrabold">Tonight on Nightarc</div>
                <div className="font-mono text-xs text-muted">12 collections · 480 titles synced</div>
              </div>
            </div>
          </div>
        </div>
      </section>

      <Marquee items={['Streaming', 'Collections', '4K HDR', 'Multi-profile', 'No ads', 'Cross-device']} />

      {/* VIBES */}
      <section className="mx-auto max-w-7xl px-5 py-24">
        <div className="text-center">
          <p className="mb-3.5 font-mono text-[11px] uppercase tracking-[0.28em] text-accent">The collection</p>
          <h2 className="font-display text-[clamp(32px,5vw,60px)] font-extrabold uppercase">Three ways to watch</h2>
        </div>
        <div className="mt-12 grid gap-5 md:grid-cols-3">
          {vibes.map((v) => (
            <div key={v.name} className="overflow-hidden rounded-2xl border border-border bg-surface transition-transform hover:-translate-y-1.5">
              <div className="relative flex h-[300px] items-end p-5" style={{ boxShadow: `inset 0 0 80px -30px ${v.glow}` }}>
                <img src={`https://picsum.photos/seed/${v.seed}/600/700`} alt="" className="absolute inset-0 h-full w-full object-cover" />
                <div className="absolute inset-0" style={{ background: 'linear-gradient(0deg,rgba(13,6,4,.95),transparent 60%)' }} />
              </div>
              <div className="p-5">
                <h3 className="font-display text-lg font-extrabold">{v.name}</h3>
                <p className="mt-1 text-sm text-muted">{v.desc}</p>
              </div>
            </div>
          ))}
        </div>
      </section>

      <div className="px-5 pb-8 text-center">
        <div className="text-stroke font-display text-[clamp(60px,12vw,150px)] font-extrabold uppercase leading-[.9] opacity-60">
          NIGHTARC
        </div>
      </div>

      {/* STATS */}
      <section className="mx-auto max-w-7xl px-5 pb-24">
        <div className="text-center">
          <p className="mb-3.5 font-mono text-[11px] uppercase tracking-[0.28em] text-accent">By the numbers</p>
          <h2 className="font-display text-[clamp(32px,5vw,60px)] font-extrabold uppercase">Built for households</h2>
        </div>
        <div className="mt-11 grid gap-4.5 gap-5 md:grid-cols-3">
          {stats.map((s) => (
            <div key={s.l} className="rounded-2xl border border-border bg-surface px-6 py-9 text-center">
              <div className="font-display text-5xl font-extrabold text-accent" style={{ textShadow: '0 0 30px var(--accent-glow)' }}>{s.n}</div>
              <div className="mt-1.5 font-mono text-[11px] uppercase tracking-widest text-muted">{s.l}</div>
            </div>
          ))}
        </div>
      </section>

      <Marquee items={['Moon so bright', 'Watch anything', 'Invite your people']} />

      {/* PRICING TEASER */}
      <section className="mx-auto max-w-7xl px-5 py-24 text-center">
        <p className="mb-3.5 font-mono text-[11px] uppercase tracking-[0.28em] text-accent">Choose your moon</p>
        <h2 className="font-display text-[clamp(32px,5vw,60px)] font-extrabold uppercase">Pick your plan</h2>
        <div className="mt-12 grid gap-5 text-left md:grid-cols-3">
          {plans.map((p) => (
            <div
              key={p.name}
              className={`relative rounded-2xl border bg-surface p-7 ${p.highlight ? 'border-accent shadow-glow-lg' : 'border-border'}`}
            >
              {p.highlight && (
                <span className="absolute -top-3 left-1/2 -translate-x-1/2 rounded-full bg-accent px-3 py-1 font-mono text-[10px] font-bold uppercase tracking-widest text-[#2a1206]">
                  Most popular
                </span>
              )}
              <div className="font-mono text-[11px] uppercase tracking-widest text-muted">{p.name}</div>
              <div className="mb-0.5 mt-2.5 font-display text-[46px] font-extrabold leading-none">
                {p.price}<span className="text-[15px] font-normal text-muted">{p.unit}</span>
              </div>
              <ul className="my-6 flex flex-col gap-3">
                {p.features.map((f) => (
                  <li key={f} className="flex items-start gap-2.5 text-sm text-muted">
                    <span className="mt-0.5 text-accent">✓</span>{f}
                  </li>
                ))}
              </ul>
              <Button
                variant={p.highlight ? 'primary' : 'ghost'}
                className="w-full rounded-full"
                onClick={() => navigate(p.to)}
              >
                {p.cta}
              </Button>
            </div>
          ))}
        </div>
      </section>

      {/* FOOTER */}
      <footer className="border-t border-border py-14 text-center">
        <div className="font-display text-4xl font-extrabold tracking-tight">NIGHTARC</div>
        <div className="mt-4 flex flex-wrap justify-center gap-6 text-sm text-muted">
          <a href="#">About</a><a href="#">Catalog</a>
          <a href="#" onClick={(e) => { e.preventDefault(); navigate('/pricing'); }}>Pricing</a>
          <a href="#">Support</a><a href="#">Status</a>
        </div>
        <p className="mt-4 font-mono text-xs text-faint">© 2026 Nightarc · A private Stremio-powered platform</p>
      </footer>
    </div>
  );
}
