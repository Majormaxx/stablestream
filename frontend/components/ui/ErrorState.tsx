type ErrorStateProps = {
  message: string;
  onRetry?: () => void;
};

export function ErrorState({ message, onRetry }: ErrorStateProps) {
  return (
    <div
      role="alert"
      className="rounded-xl border border-error-400/20 bg-error-400/6 px-[18px] py-[14px] text-[0.82rem] text-error-400 flex items-center justify-between gap-4"
    >
      <span>{message}</span>
      {onRetry && (
        <button
          onClick={onRetry}
          className="rounded-md border border-error-400/30 px-3 py-1.5 text-xs font-semibold hover:bg-error-400/10 transition-colors"
        >
          Retry
        </button>
      )}
    </div>
  );
}
