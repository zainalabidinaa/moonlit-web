/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{js,ts,jsx,tsx}"],
  theme: {
    extend: {
      fontFamily: { sans: ['Inter', 'system-ui', 'sans-serif'] },
      colors: {
        luna: {
          bg: '#080808',
          surface: '#111111',
          elevated: '#1c1c1e',
          border: '#2a2a2a',
          accent: '#c084fc',
          secondary: '#818cf8',
          text: '#fafafa',
          muted: '#71717a',
        }
      },
      backdropBlur: { xs: '2px' }
    }
  },
  plugins: []
}

