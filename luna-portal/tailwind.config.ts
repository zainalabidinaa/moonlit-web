import type { Config } from 'tailwindcss';

export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        bg: '#0d0604',
        bg2: '#140b07',
        surface: '#1a110b',
        'surface-2': '#221710',
        accent: '#fa824d',
        'accent-2': '#ff6a2b',
        'accent-light': '#2a1206',
        cyan: '#34e6c8',
        magenta: '#ff4dd2',
        orange: '#ff8a3d',
        border: '#2c211b',
        'border-strong': '#3a2c23',
        text: '#f7ede6',
        muted: '#c4a090',
        faint: '#8a6f5f',
      },
      fontFamily: {
        display: ['"Bricolage Grotesque"', 'sans-serif'],
        body: ['"Funnel Display"', 'sans-serif'],
        mono: ['"JetBrains Mono"', 'monospace'],
      },
      boxShadow: {
        glow: '0 0 22px rgba(250,130,77,.55)',
        'glow-lg': '0 0 50px -20px rgba(250,130,77,.55)',
      },
    },
  },
  plugins: [],
} satisfies Config;
