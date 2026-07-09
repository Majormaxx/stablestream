type SkeletonProps = {
  width?: string;
  height?: string;
  rounded?: string;
  className?: string;
};

export function Skeleton({ width = "5rem", height = "2rem", rounded = "6px", className = "" }: SkeletonProps) {
  return (
    <span
      aria-hidden="true"
      className={`inline-block align-middle bg-gradient-to-r from-brand-500/12 via-brand-400/18 to-brand-500/12 bg-[length:200%_100%] animate-[shimmer_1.5s_infinite] ${className}`}
      style={{ width, height, borderRadius: rounded }}
    />
  );
}
