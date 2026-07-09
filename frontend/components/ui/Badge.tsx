import { ReactNode } from "react";

type BadgeProps = {
  children: ReactNode;
  color?: string;
  pulse?: boolean;
  className?: string;
};

export function Badge({ children, color = "#00AAFF", pulse = false, className = "" }: BadgeProps) {
  return (
    <div
      className={`inline-flex items-center gap-2 px-4 py-2 rounded-full text-xs font-semibold tracking-[1px] ${className}`}
      style={{
        border: `1px solid ${color}4D`,
        background: `${color}14`,
        color,
      }}
    >
      {pulse && (
        <span
          className="inline-block rounded-full stream-pulse"
          style={{ width: 6, height: 6, background: "#00D4FF", display: "inline-block" }}
        />
      )}
      {children}
    </div>
  );
}
