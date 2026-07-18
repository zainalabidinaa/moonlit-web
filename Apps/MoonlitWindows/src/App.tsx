import { AuthProvider } from '@/app/AuthProvider';
import { PlayerProvider } from '@/app/PlayerProvider';
import { SessionGate } from '@/shell/SessionGate';

export function App() {
  return (
    <AuthProvider>
      <PlayerProvider>
        <SessionGate />
      </PlayerProvider>
    </AuthProvider>
  );
}
