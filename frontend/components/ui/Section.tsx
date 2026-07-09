type SectionProps = {
  id?: string;
  eyebrow?: string;
  heading: string;
  subheading?: string;
  children: React.ReactNode;
  className?: string;
};

export function Section({ id, eyebrow, heading, subheading, children, className = "" }: SectionProps) {
  return (
    <section id={id} className={`px-6 py-28 ${className}`}>
      <div className="max-w-6xl mx-auto">
        <div className="text-center mb-16">
          {eyebrow && (
            <p className="text-brand-400 font-semibold text-xs tracking-[2px] mb-3">
              {eyebrow}
            </p>
          )}
          <h2 className="font-black tracking-tight text-[clamp(2rem,4vw,3rem)] -tracking-[1px]">
            {heading}
          </h2>
          {subheading && (
            <p className="text-text-muted mt-3 max-w-[480px] mx-auto leading-[1.7] text-sm">
              {subheading}
            </p>
          )}
        </div>
        {children}
      </div>
    </section>
  );
}
