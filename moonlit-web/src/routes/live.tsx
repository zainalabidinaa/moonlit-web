import { Link } from '@tanstack/react-router';

export default function LivePage() {
  return (
    <div className="mx-auto min-h-[calc(100vh-56px)] max-w-[1600px] px-4 pb-16 pt-10 sm:px-6 md:px-14">
      <p className="type-label mb-2 text-moonlit-text-tertiary">Watch now</p>
      <h1 className="type-title-lg text-white">Live TV</h1>
      <section className="glass-panel mt-10 max-w-xl rounded-ml-lg p-6" aria-labelledby="live-empty-title">
        <h2 id="live-empty-title" className="type-title-sm text-white">No live source connected</h2>
        <p className="mt-2 text-sm leading-6 text-moonlit-text-secondary">
          Live sources are profile-specific and never bundled with Moonlit.
        </p>
        <Link to="/settings" className="mt-5 inline-flex min-h-11 items-center rounded-ml-ctl bg-white px-5 text-sm font-semibold text-black">
          Open settings
        </Link>
      </section>
    </div>
  );
}
