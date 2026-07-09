import fs from "fs";
import path from "path";
import { Metadata } from "next";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";

export const metadata: Metadata = {
  title: "Integration Guide",
  description:
    "Add idle-capital yield routing to your Uniswap v4 hook using IdleCapitalYieldModule — ~20 lines of Solidity.",
};

function extractHeadings(md: string): { level: number; text: string; id: string }[] {
  const headings: { level: number; text: string; id: string }[] = [];
  const lines = md.split("\n");
  for (const line of lines) {
    const m = line.match(/^(#{1,3})\s+(.+)$/);
    if (m) {
      const text = m[2].trim();
      const id = text.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "");
      headings.push({ level: m[1].length, text, id });
    }
  }
  return headings;
}

export default function IntegrationGuidePage() {
  const mdPath = path.join(process.cwd(), "..", "docs", "INTEGRATION_GUIDE.md");
  const content = fs.readFileSync(mdPath, "utf-8");
  const headings = extractHeadings(content);

  return (
    <div className="min-h-screen bg-ink text-paper">
      <a href="/" className="fixed top-4 left-4 z-50 rounded-[var(--radius-control)] px-4 py-2 text-sm font-semibold text-ink no-underline"
        style={{ background: "linear-gradient(135deg, #E8A33D, #D4892A)" }}>
        ← Back to StableStream
      </a>
      <div className="max-w-4xl mx-auto px-6 py-20">
        <div className="flex gap-10">
          {/* Sidebar TOC */}
          <aside className="hidden lg:block w-56 flex-shrink-0">
            <nav className="sticky top-24 space-y-2" aria-label="Page sections">
              <div className="font-mono text-[0.65rem] tracking-[2px] text-slate uppercase mb-4">On this page</div>
              {headings.map((h) => (
                <a
                  key={h.id}
                  href={`#${h.id}`}
                  className={`block text-sm no-underline transition-colors hover:text-paper ${
                    h.level === 1 ? "font-semibold text-paper" : "text-slate"
                  } ${h.level === 3 ? "pl-4" : ""}`}
                >
                  {h.text}
                </a>
              ))}
            </nav>
          </aside>

          {/* Main content */}
          <article className="flex-1 min-w-0 prose-custom">
            <ReactMarkdown
              remarkPlugins={[remarkGfm]}
              components={{
                h1: ({ children, ...props }) => {
                  const id = String(children).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "");
                  return (
                    <h1 id={id} className="font-black text-[clamp(1.8rem,3vw,2.8rem)] -tracking-[1px] mt-0 mb-6 font-display text-paper" {...props}>
                      {children}
                    </h1>
                  );
                },
                h2: ({ children, ...props }) => {
                  const id = String(children).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "");
                  return (
                    <h2 id={id} className="font-bold text-[1.4rem] -tracking-[0.5px] mt-10 mb-3 font-display text-paper" {...props}>
                      {children}
                    </h2>
                  );
                },
                h3: ({ children, ...props }) => {
                  const id = String(children).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "");
                  return (
                    <h3 id={id} className="font-semibold text-[1.1rem] mt-8 mb-2 font-display text-paper" {...props}>
                      {children}
                    </h3>
                  );
                },
                p: ({ children, ...props }) => (
                  <p className="text-slate leading-[1.8] mb-4 text-[0.95rem]" {...props}>{children}</p>
                ),
                code: ({ className, children, ...props }) => {
                  const isInline = !className;
                  if (isInline) {
                    return (
                      <code className="text-signal font-mono text-[0.85rem] bg-channel/60 px-1.5 py-0.5 rounded-[4px]" {...props}>
                        {children}
                      </code>
                    );
                  }
                  return (
                    <pre className="bg-ink/90 border border-rail rounded-[var(--radius-panel)] p-5 overflow-x-auto mb-6">
                      <code className="text-[0.82rem] font-mono text-paper leading-[1.7]" {...props}>
                        {children}
                      </code>
                    </pre>
                  );
                },
                pre: ({ children }) => <>{children}</>,
                a: ({ href, children, ...props }) => (
                  <a href={href} className="text-signal underline hover:opacity-80 transition-opacity" target={href?.startsWith("http") ? "_blank" : undefined} rel={href?.startsWith("http") ? "noopener noreferrer" : undefined} {...props}>
                    {children}
                  </a>
                ),
                ul: ({ children }) => (
                  <ul className="text-slate leading-[1.8] mb-4 pl-5 space-y-1 list-disc">{children}</ul>
                ),
                ol: ({ children }) => (
                  <ol className="text-slate leading-[1.8] mb-4 pl-5 space-y-1 list-decimal">{children}</ol>
                ),
                li: ({ children }) => <li className="text-[0.95rem]">{children}</li>,
                strong: ({ children }) => <strong className="font-semibold text-paper">{children}</strong>,
                hr: () => <hr className="border-rail my-8" />,
              }}
            >
              {content}
            </ReactMarkdown>

            <div className="mt-16 pt-8 border-t border-rail text-center">
              <a
                href="https://github.com/Majormaxx/stablestream/blob/main/docs/INTEGRATION_GUIDE.md"
                target="_blank"
                rel="noopener noreferrer"
                className="text-slate text-[0.85rem] hover:text-paper transition-colors no-underline"
              >
                Edit on GitHub ↗
              </a>
            </div>
          </article>
        </div>
      </div>
    </div>
  );
}
