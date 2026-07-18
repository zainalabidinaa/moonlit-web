const oklchToColor = (L: number, C: number, h: number): [number, number, number] => {
  const hRad = h * Math.PI / 180;
  const a = C * Math.cos(hRad);
  const b = C * Math.sin(hRad);

  const l_ = L + 0.3963377774 * a + 0.2158037573 * b;
  const m_ = L - 0.1055613458 * a - 0.0638541728 * b;
  const s_ = L - 0.0894841775 * a - 1.2914855480 * b;

  const l3 = l_ * l_ * l_;
  const m3 = m_ * m_ * m_;
  const s3 = s_ * s_ * s_;

  const rLin = 4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3;
  const gLin = -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3;
  const bLin = -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3;

  const srgb = (c: number) => {
    const v = Math.max(0, Math.min(1, c));
    if (v <= 0.0031308) return 12.92 * v;
    return 1.055 * Math.pow(v, 1 / 2.4) - 0.055;
  };

  return [srgb(rLin), srgb(gLin), srgb(bLin)];
};

const toCss = (rgb: [number, number, number]) =>
  `rgb(${Math.round(rgb[0] * 255)}, ${Math.round(rgb[1] * 255)}, ${Math.round(rgb[2] * 255)})`;

const toCssOklch = (L: number, C: number, h: number) => toCss(oklchToColor(L, C, h));

const normalizeGenre = (name: string) => name.toLowerCase().replace(/[^a-z]/g, '');

interface GenreColors {
  from: string;
  to: string;
  ink: string;
}

export function genre(name: string): GenreColors {
  switch (normalizeGenre(name)) {
    case 'action':       return { from: toCssOklch(0.40, 0.18, 25), to: toCssOklch(0.18, 0.10, 20), ink: toCssOklch(0.96, 0.02, 25) };
    case 'adventure':    return { from: toCssOklch(0.45, 0.14, 145), to: toCssOklch(0.20, 0.10, 155), ink: toCssOklch(0.96, 0.02, 145) };
    case 'animation':    return { from: toCssOklch(0.50, 0.16, 200), to: toCssOklch(0.20, 0.10, 195), ink: toCssOklch(0.96, 0.02, 200) };
    case 'comedy':       return { from: toCssOklch(0.55, 0.16, 75), to: toCssOklch(0.22, 0.08, 60), ink: toCssOklch(0.96, 0.02, 80) };
    case 'crime':        return { from: toCssOklch(0.32, 0.10, 50), to: toCssOklch(0.14, 0.04, 30), ink: toCssOklch(0.95, 0.04, 60) };
    case 'documentary':  return { from: toCssOklch(0.36, 0.10, 145), to: toCssOklch(0.18, 0.06, 150), ink: toCssOklch(0.96, 0.02, 145) };
    case 'drama':        return { from: toCssOklch(0.36, 0.12, 240), to: toCssOklch(0.18, 0.06, 230), ink: toCssOklch(0.96, 0.02, 240) };
    case 'family':       return { from: toCssOklch(0.50, 0.13, 100), to: toCssOklch(0.20, 0.08, 110), ink: toCssOklch(0.96, 0.02, 100) };
    case 'fantasy':      return { from: toCssOklch(0.42, 0.14, 320), to: toCssOklch(0.18, 0.08, 305), ink: toCssOklch(0.96, 0.02, 320) };
    case 'history':      return { from: toCssOklch(0.42, 0.10, 70), to: toCssOklch(0.16, 0.05, 55), ink: toCssOklch(0.95, 0.04, 75) };
    case 'horror':       return { from: toCssOklch(0.30, 0.10, 15), to: toCssOklch(0.10, 0.04, 20), ink: toCssOklch(0.94, 0.02, 20) };
    case 'music':        return { from: toCssOklch(0.46, 0.18, 320), to: toCssOklch(0.18, 0.10, 305), ink: toCssOklch(0.96, 0.02, 320) };
    case 'mystery':      return { from: toCssOklch(0.32, 0.10, 95), to: toCssOklch(0.14, 0.06, 80), ink: toCssOklch(0.95, 0.04, 90) };
    case 'romance':      return { from: toCssOklch(0.45, 0.15, 0), to: toCssOklch(0.20, 0.08, 350), ink: toCssOklch(0.96, 0.02, 0) };
    case 'scifi':        return { from: toCssOklch(0.38, 0.16, 285), to: toCssOklch(0.18, 0.10, 280), ink: toCssOklch(0.96, 0.02, 285) };
    case 'thriller':     return { from: toCssOklch(0.32, 0.10, 200), to: toCssOklch(0.14, 0.04, 220), ink: toCssOklch(0.96, 0.02, 220) };
    case 'war':          return { from: toCssOklch(0.32, 0.06, 70), to: toCssOklch(0.14, 0.04, 60), ink: toCssOklch(0.95, 0.02, 75) };
    case 'western':      return { from: toCssOklch(0.45, 0.12, 55), to: toCssOklch(0.18, 0.08, 35), ink: toCssOklch(0.96, 0.04, 60) };
    default:             return { from: toCssOklch(0.36, 0.12, 240), to: toCssOklch(0.18, 0.06, 230), ink: toCssOklch(0.96, 0.02, 240) };
  }
}

export function languageColors(hue: number) {
  const from = toCssOklch(0.42, 0.13, hue);
  const to = toCssOklch(0.17, 0.07, hue);
  const ink = toCssOklch(0.96, 0.02, hue);
  return { from, to, ink };
}
