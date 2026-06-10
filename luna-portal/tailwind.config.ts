import type { Config } from 'tailwindcss';

export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        bg: '#f2f6fc',
        surface: '#ffffff',
        accent: '#6d28d9',
        'accent-light': '#ede9fe',
        border: '#e2e8f0',
        text: '#0f172a',
        muted: '#64748b',
      },
    },
  },
  plugins: [],
} satisfies Config;
