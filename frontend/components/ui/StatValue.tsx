import { Skeleton } from "./Skeleton";

type StatValueProps = {
  loading?: boolean;
  error?: boolean;
  value?: string;
  errorLabel?: string;
  skeletonWidth?: string;
};

export function StatValue({ loading, error, value, errorLabel = "Failed to load", skeletonWidth }: StatValueProps) {
  if (loading) return <Skeleton width={skeletonWidth} />;
  if (error) return <span className="text-error-400" role="alert">{errorLabel}</span>;
  return <span>{value ?? "—"}</span>;
}
