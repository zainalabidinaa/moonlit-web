/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{js,ts,jsx,tsx}"],
  theme: {
    extend: {
      fontFamily: {
        sans: ['Inter', 'system-ui', 'sans-serif'],
        brand: ['Montserrat', 'Inter', 'system-ui', 'sans-serif'],
      },
      colors: {
        moonlit: {
          bg: '#141414',
          surface: '#1f1f1f',
          elevated: '#2a2a2a',
          border: 'rgba(255,255,255,0.10)',
          accent: '#e50914',
          'accent-dim': 'rgba(229,9,20,0.70)',
          'accent-glow': 'rgba(229,9,20,0.12)',
          gold: '#D4AF37',
          secondary: '#D4AF37',
          text: '#FFFFFF',
          'text-secondary': '#b3b3b3',
          'text-tertiary': '#808080',
          muted: '#808080',
        },
        player: {
          canvas: '#111213',
          surface: '#191B1C',
          elevated: '#252628',
          raised: '#323335',
          edge: 'rgba(60,61,63,0.55)',
          ink: '#F4F5F7',
          'ink-muted': '#A3A5A6',
        },
      },
      borderRadius: {
        'ml-sm': '4px',
        'ml-ctl': '6px',
        'ml-card': '4px',
        'ml-lg': '8px',
      },
      boxShadow: {
        'ml-lift': '0 10px 16px rgba(0,0,0,0.40)',
        'ml-panel': '0 14px 30px rgba(0,0,0,0.80)',
        'ml-glass': '0 4px 12px rgba(0,0,0,0.30)',
        'ml-hero-text': '0 3px 8px rgba(0,0,0,0.55)',
      },
      keyframes: {
        'fade-in': { from: { opacity: '0' }, to: { opacity: '1' } },
        'slide-up': { from: { transform: 'translateY(100%)' }, to: { transform: 'translateY(0)' } },
        'slide-down': { from: { transform: 'translateY(0)' }, to: { transform: 'translateY(100%)' } },
        'scale-in': { from: { opacity: '0', transform: 'scale(0.95)' }, to: { opacity: '1', transform: 'scale(1)' } },
        shimmer: {
          from: { backgroundPosition: '-200% 0' },
          to: { backgroundPosition: '200% 0' },
        },
        'spin-arc': { to: { transform: 'rotate(360deg)' } },
      },
      animation: {
        'fade-in': 'fade-in 0.4s ease-in-out',
        'slide-up': 'slide-up 0.3s ease-out',
        'slide-down': 'slide-down 0.2s ease-in',
        'scale-in': 'scale-in 0.3s ease-out',
        shimmer: 'shimmer 1.5s linear infinite',
        'spin-arc': 'spin-arc 0.7s linear infinite',
      },
    }
  },
  plugins: []
}
