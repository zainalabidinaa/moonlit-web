import React, { Suspense } from 'react';
import { createRouter, createRootRoute, createRoute, Outlet } from '@tanstack/react-router';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { AuthProvider, useAuth } from '@/app/AuthProvider';
import { PlayerProvider } from '@/app/PlayerProvider';
import { PlayerOverlay } from '@/components/PlayerOverlay';
import { AppShell } from '@/components/AppShell';

export const queryClient = new QueryClient({
  defaultOptions: { queries: { staleTime: 5 * 60 * 1000, retry: 1 } },
});

function Spinner() {
  return <div className="flex items-center justify-center min-h-screen"><div className="w-7 h-7 rounded-full border-2 border-white/[0.14] border-t-white animate-spin-arc"/></div>;
}

function lazily(importFn: () => Promise<{ default: React.ComponentType }>) {
  const Lazy = React.lazy(importFn);
  return function Route() { return <Suspense fallback={<Spinner/>}><Lazy/></Suspense>; };
}

function ProtectedLayout() {
  const { user, guestMode, currentProfile, isLoading } = useAuth();
  if (isLoading) return <Spinner/>;
  if (guestMode) return <AppShell><Outlet/></AppShell>;
  if (!user) { window.location.replace('/auth'); return null; }
  if (!currentProfile) { window.location.replace('/profiles'); return null; }
  return <AppShell><Outlet/></AppShell>;
}

const rootRoute = createRootRoute({
  component: () => (
    <QueryClientProvider client={queryClient}>
      <AuthProvider>
        <PlayerProvider>
          <Outlet/>
          <PlayerOverlay/>
        </PlayerProvider>
      </AuthProvider>
    </QueryClientProvider>
  ),
});

const indexRoute = createRoute({ getParentRoute: () => rootRoute, path: '/', component: lazily(() => import('@/routes/index')) });
const authRoute = createRoute({ getParentRoute: () => rootRoute, path: '/auth', component: lazily(() => import('@/routes/auth')) });
const activateRoute = createRoute({ getParentRoute: () => rootRoute, path: '/activate', validateSearch: (s: Record<string,unknown>) => ({ code: s.code ? String(s.code) : undefined as string|undefined }), component: lazily(() => import('@/routes/activate')) });
const profilesRoute = createRoute({ getParentRoute: () => rootRoute, path: '/profiles', component: lazily(() => import('@/routes/profiles')) });

const protectedLayout = createRoute({ getParentRoute: () => rootRoute, id: 'protected', component: ProtectedLayout });

const homeRoute = createRoute({ getParentRoute: () => protectedLayout, path: '/home', component: lazily(() => import('@/routes/home')) });
const browseRoute = createRoute({ getParentRoute: () => protectedLayout, path: '/browse/$type/$id', component: lazily(() => import('@/routes/browse')) });
const watchRoute = createRoute({ getParentRoute: () => protectedLayout, path: '/watch/$type/$id', validateSearch: (s: Record<string,unknown>) => ({ url: String(s.url??''), cid: String(s.cid??''), title: String(s.title??''), logo: s.logo ? String(s.logo) : undefined, pos: s.pos !== undefined ? Number(s.pos) : undefined }), component: lazily(() => import('@/routes/watch')) });
const libraryRoute = createRoute({ getParentRoute: () => protectedLayout, path: '/library', component: lazily(() => import('@/routes/library')) });
const searchRoute = createRoute({ getParentRoute: () => protectedLayout, path: '/search', component: lazily(() => import('@/routes/search')) });
const settingsRoute = createRoute({ getParentRoute: () => protectedLayout, path: '/settings', component: lazily(() => import('@/routes/settings')) });
const collectionsRoute = createRoute({ getParentRoute: () => protectedLayout, path: '/collections/$folderId', component: lazily(() => import('@/routes/collections')) });
const adminRoute = createRoute({ getParentRoute: () => protectedLayout, path: '/admin', component: lazily(() => import('@/routes/admin')) });

const routeTree = rootRoute.addChildren([indexRoute, authRoute, activateRoute, profilesRoute, protectedLayout.addChildren([homeRoute, browseRoute, watchRoute, libraryRoute, searchRoute, settingsRoute, collectionsRoute, adminRoute])]);

export const router = createRouter({ routeTree });
declare module '@tanstack/react-router' { interface Register { router: typeof router; } }
