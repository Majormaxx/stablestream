type CardProps = React.ComponentPropsWithoutRef<"div"> & {
  hover?: boolean;
  accent?: boolean;
};

export function Card({ children, hover = false, accent = false, className = "", ...rest }: CardProps) {
  return (
    <div
      className={[
        "rounded-2xl border border-brand-500/20 bg-bg-card/80 p-6",
        accent && "bg-gradient-to-br from-bg-card/90 to-bg-deep/90",
        hover && "transition-all duration-250 hover:-translate-y-1.5 hover:shadow-[0_24px_64px_rgba(0,102,255,0.18)] hover:border-brand-400/40",
        className,
      ].filter(Boolean).join(" ")}
      {...rest}
    >
      {children}
    </div>
  );
}
