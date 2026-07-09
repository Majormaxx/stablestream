type CardProps = React.ComponentPropsWithoutRef<"div"> & {
  hover?: boolean;
  accent?: boolean;
};

export function Card({ children, hover = false, accent = false, className = "", ...rest }: CardProps) {
  return (
    <div
      className={[
        "rounded-[var(--radius-panel)] border border-rail/60 bg-channel/80 p-6",
        accent && "bg-gradient-to-br from-channel/90 to-ink/90",
        hover && "transition-all duration-250 hover:-translate-y-1.5 hover:shadow-[0_24px_64px_rgba(232,163,61,0.12)] hover:border-signal/40",
        className,
      ].filter(Boolean).join(" ")}
      {...rest}
    >
      {children}
    </div>
  );
}
