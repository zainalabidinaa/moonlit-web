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
          bg: '#0D0D0D', surface: '#1A1A1A', elevated: '#242424',
          border: 'rgba(255,255,255,0.08)', accent: '#FFFFFF',
          'accent-dim': 'rgba(255,255,255,0.70)', 'accent-glow': 'rgba(255,255,255,0.12)',
          gold: '#D4AF37', secondary: '#D4AF37', text: '#FFFFFF',
          'text-secondary': 'rgba(255,255,255,0.70)', 'text-tertiary': 'rgba(255,255,255,0.50)',
          muted: 'rgba(255,255,255,0.50)',
        },
        player: {
          canvas: '#111213', surface: '#191B1C', elevated: '#252628',
          raised: '#323335', edge: 'rgba(60,61,63,0.55)',
          ink: '#F4F5F7', 'ink-muted': '#A3A5A6',
        },
      },
      borderRadius: {
        'ml-sm': '6px', 'ml-ctl': '10px', 'ml-card': '14px', 'ml-lg': '18px',
      },
      boxShadow: {
        'ml-card': '0 8px 30px rgba(0,0,0,0.50)',
        'ml-panel': '0 14px 30px rgba(0,0,0,0.80)',
        'ml-glass': '0 4px 12px rgba(0,0,0,0.30)',
      },
      backdropBlur: { xs: '2px' },
      keyframes: {
        'fade-in': { from: { opacity: '0' }, to: { opacity: '1' } },
        shimmer: { from: { backgroundPosition: '-200% 0' }, to: { backgroundPosition: '200% 0' } },
        'spin-arc': { to: { transform: 'rotate(360deg)' } },
      },
      animation: {
        'fade-in': 'fade-in 0.5s ease-in-out',
        shimmer: 'shimmer 1.5s linear infinite',
        'spin-arc': 'spin-arc 0.7s linear infinite',
      },
    }
  },
  plugins: []
}
