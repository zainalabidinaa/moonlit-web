import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './src/test/e2e',
  testMatch: /player-media\.spec\.ts/,
  timeout: 30_000,
  fullyParallel: false,
  retries: process.env.CI ? 1 : 0,
  reporter: 'line',
  use: {
    ...devices['Desktop Chrome'],
    baseURL: 'http://127.0.0.1:4178',
    launchOptions: { args: ['--autoplay-policy=no-user-gesture-required'] },
  },
  webServer: {
    command: 'npm run dev -- --host 127.0.0.1 --port 4178',
    url: 'http://127.0.0.1:4178',
    reuseExistingServer: !process.env.CI,
  },
});
