/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{js,ts,jsx,tsx}"],
  theme: {
    extend: {
      fontFamily: { sans: ['Inter', 'system-ui', 'sans-serif'] },
      colors: {
        moonlit: {
          bg: '#080808',
          surface: '#111111',
          elevated: '#1c1c1e',
          border: '#2a2a2a',
          accent: '#FF8A35',
          'accent-dim': '#E07620',
          'accent-glow': 'rgba(255,138,53,0.3)',
          secondary: '#D4A843',
          text: '#fafafa',
          muted: '#71717a',
        }
      },
      backdropBlur: { xs: '2px' },
      keyframes: {
        'fade-in': { from: { opacity: '0' }, to: { opacity: '1' } },
        'breathing-pulse': {
          '0%, 100%': { transform: 'scale(1)', opacity: '1' },
          '50%': { transform: 'scale(1.04)', opacity: '0.85' },
        },
        'slide-up': { from: { transform: 'translateY(100%)' }, to: { transform: 'translateY(0)' } },
        'slide-down': { from: { transform: 'translateY(0)' }, to: { transform: 'translateY(100%)' } },
        'scale-in': { from: { opacity: '0', transform: 'scale(0.95)' }, to: { opacity: '1', transform: 'scale(1)' } },
      },
      animation: {
        'fade-in': 'fade-in 0.4s ease-in-out',
        'breathing-pulse': 'breathing-pulse 2s ease-in-out infinite',
        'slide-up': 'slide-up 0.3s ease-out',
        'slide-down': 'slide-down 0.2s ease-in',
        'scale-in': 'scale-in 0.3s ease-out',
      },
    }
  },
  plugins: []
}

