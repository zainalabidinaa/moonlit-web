import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { AuthProvider } from '@/app/AuthProvider';
import { PlayerProvider } from '@/app/PlayerProvider';
import { SessionGate } from '@/shell/SessionGate';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 5 * 60 * 1000,
      retry: 1,
      refetchOnWindowFocus: false,
    },
  },
});

export function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <AuthProvider>
        <PlayerProvider>
          <SessionGate />
        </PlayerProvider>
      </AuthProvider>
    </QueryClientProvider>
  );
}
