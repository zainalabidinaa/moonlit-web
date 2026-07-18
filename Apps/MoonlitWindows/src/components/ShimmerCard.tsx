export default function ShimmerCard({ className = '' }: { className?: string }) {
  return (
    <div
      className={`shimmer rounded-ml-lg flex-shrink-0 ${className}`}
      style={{ width: 154, height: 231 }}
      aria-hidden="true"
    />
  );
}
