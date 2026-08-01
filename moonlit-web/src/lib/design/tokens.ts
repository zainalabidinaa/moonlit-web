export const colorTokens = {
  background: '#0D0D0D',
  surface: '#1A1A1A',
  surfaceElevated: '#242424',
  surfaceContainer: '#222222',
  textPrimary: '#FFFFFF',
  textSecondary: 'rgba(255, 255, 255, 0.70)',
  textTertiary: 'rgba(255, 255, 255, 0.50)',
  outline: 'rgba(255, 255, 255, 0.08)',
  accent: '#FFFFFF',
  accentForeground: '#0D0D0D',
  selection: '#D4AF37',
  selectionForeground: '#241C05',
  ratingGold: '#D4AF37',
} as const;

export const typographyTokens = {
  displayLg: { size: 40, weight: 700 },
  titleLg: { size: 28, weight: 600 },
  titleMd: { size: 22, weight: 600 },
  titleSm: { size: 18, weight: 600 },
  bodyLg: { size: 16, weight: 400 },
  bodyMd: { size: 14, weight: 400 },
  bodySm: { size: 13, weight: 400 },
  labelLg: { size: 14, weight: 600 },
  labelMd: { size: 12, weight: 600 },
  labelSm: { size: 11, weight: 600 },
  labelXs: { size: 10, weight: 700 },
} as const;

export const glassTokens = {
  fill: 'rgba(26, 26, 26, 0.72)',
  fillClear: 'rgba(255, 255, 255, 0.10)',
  border: 'rgba(255, 255, 255, 0.16)',
  blur: 24,
  shadow: '0 4px 12px rgba(0, 0, 0, 0.30)',
} as const;

export const focusTokens = {
  ring: 'rgba(255, 255, 255, 0.90)',
  background: 'rgba(255, 255, 255, 0.12)',
  width: 2,
  offset: 3,
} as const;

export const spacingTokens = {
  1: 4,
  2: 8,
  3: 12,
  4: 16,
  5: 20,
  6: 24,
  7: 28,
  8: 32,
  11: 44,
  16: 64,
} as const;

export const motionTokens = {
  fast: 0.15,
  controls: 0.18,
  standard: 0.25,
  cardSpring: { response: 0.3, dampingFraction: 0.78 },
  rowSpring: { response: 0.42, dampingFraction: 0.82 },
  heroManualSpring: { response: 0.42, dampingFraction: 0.82 },
  heroAutomaticSpring: { response: 0.5, dampingFraction: 0.82 },
  heroCrossfade: 0.6,
  ambientColor: 0.9,
} as const;

export const designTokens = {
  color: colorTokens,
  typography: typographyTokens,
  glass: glassTokens,
  focus: focusTokens,
  spacing: spacingTokens,
  motion: motionTokens,
} as const;
