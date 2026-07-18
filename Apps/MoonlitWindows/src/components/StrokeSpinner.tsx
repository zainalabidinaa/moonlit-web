export default function StrokeSpinner({ size = 28 }: { size?: number }) {
  const lineWidth = Math.max(2, size * 0.1);
  const radius = (size - lineWidth) / 2;
  const circumference = 2 * Math.PI * radius;
  const arcLength = circumference * 0.25;

  return (
    <svg
      width={size}
      height={size}
      viewBox={`0 0 ${size} ${size}`}
      className="animate-spin-arc"
      role="img"
      aria-label="Loading"
    >
      <circle
        cx={size / 2}
        cy={size / 2}
        r={radius}
        fill="none"
        stroke="white"
        strokeWidth={lineWidth}
        opacity={0.14}
      />
      <circle
        cx={size / 2}
        cy={size / 2}
        r={radius}
        fill="none"
        stroke="white"
        strokeWidth={lineWidth}
        strokeLinecap="round"
        strokeDasharray={`${arcLength} ${circumference - arcLength}`}
      />
    </svg>
  );
}
