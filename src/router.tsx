import React, { Suspense } from 'react';
import {
  createRouter,
  createRootRoute,
  createRoute,
  Outlet,
} from '@tanstack/react-router';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { AuthProvider, useAuth } from '@/app/AuthProvider';

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 5 * 60 * 1000,
      retry: 1,
    },
  },
});

function Spinner() {
  return (
    <div className="flex items-center justify-center min-h-screen">
      <div className="animate-spin rounded-full h-6 w-6 border-2 border-luna-accent border-t-transparent" />
    </div>
  );
}

function lazily(importFn: () => Promise<{ default: React.ComponentType }>) {
  const Lazy = React.lazy(importFn);
  return function Route() {
    return (
      <Suspense fallback={<Spinner />}>
        <Lazy />
      </Suspense>
    );
  };
}

// Auth guard layout — wraps all protected routes
function AuthGuard() {
  const { user, currentProfile, isLoading } = useAuth();

  if (isLoading) return <Spinner />;
  if (!user) { window.location.replace('/auth'); return null; }
  if (!currentProfile) { window.location.replace('/profiles'); return null; }

  return <Outlet />;
}

// ── Route tree ──────────────────────────────────────────────────────────────

const rootRoute = createRootRoute({
  component: () => (
    <QueryClientProvider client={queryClient}>
      <AuthProvider>
        <Outlet />
      </AuthProvider>
    </QueryClientProvider>
  ),
});

// Public
const indexRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/',
  component: lazily(() => import('@/routes/index')),
});

const authRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/auth',
  component: lazily(() => import('@/routes/auth')),
});

const profilesRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/profiles',
  component: lazily(() => import('@/routes/profiles')),
});

// Protected layout (pathless route — wraps children with auth guard)
const protectedLayout = createRoute({
  getParentRoute: () => rootRoute,
  id: 'protected',
  component: AuthGuard,
});

const homeRoute = createRoute({
  getParentRoute: () => protectedLayout,
  path: '/home',
  component: lazily(() => import('@/routes/home')),
});

const browseRoute = createRoute({
  getParentRoute: () => protectedLayout,
  path: '/browse/$type/$id',
  component: lazily(() => import('@/routes/browse')),
});

const watchRoute = createRoute({
  getParentRoute: () => protectedLayout,
  path: '/watch/$type/$id',
  validateSearch: (search: Record<string, unknown>) => ({
    url: String(search.url ?? ''),
    cid: String(search.cid ?? ''),
    title: String(search.title ?? ''),
    pos: search.pos !== undefined ? Number(search.pos) : undefined as number | undefined,
  }),
  component: lazily(() => import('@/routes/watch')),
});

const libraryRoute = createRoute({
  getParentRoute: () => protectedLayout,
  path: '/library',
  component: lazily(() => import('@/routes/library')),
});

const searchRoute = createRoute({
  getParentRoute: () => protectedLayout,
  path: '/search',
  component: lazily(() => import('@/routes/search')),
});

const settingsRoute = createRoute({
  getParentRoute: () => protectedLayout,
  path: '/settings',
  component: lazily(() => import('@/routes/settings')),
});

const collectionsRoute = createRoute({
  getParentRoute: () => protectedLayout,
  path: '/collections/$folderId',
  component: lazily(() => import('@/routes/collections')),
});

const routeTree = rootRoute.addChildren([
  indexRoute,
  authRoute,
  profilesRoute,
  protectedLayout.addChildren([
    homeRoute,
    browseRoute,
    watchRoute,
    libraryRoute,
    searchRoute,
    settingsRoute,
    collectionsRoute,
  ]),
]);

export const router = createRouter({ routeTree });

declare module '@tanstack/react-router' {
  interface Register {
    router: typeof router;
  }
}
