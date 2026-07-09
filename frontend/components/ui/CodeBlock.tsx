import { ReactNode } from "react";

const SOL_KEYWORDS = /\b(contract|constructor|is|function|returns|public|external|internal|private|view|pure|override|abstract|import|pragma|solidity)\b/g;
const SOL_TYPES = /\b(address|uint256|int24|bytes32|bytes|bool)\b/g;
const SOL_COMMENTS = /\/\/.*$/gm;

function tokenize(code: string): ReactNode[] {
  const lines = code.split("\n");
  return lines.map((line, i) => {
    const isComment = line.trimStart().startsWith("//");
    const isImport = line.trimStart().startsWith("import");
    let tokens: ReactNode[] = [];

    if (isComment) {
      tokens.push(
        <span key="c" className="text-text-muted italic">{line}</span>
      );
    } else if (isImport) {
      const parts = line.split(/(["';])/g);
      tokens = parts.map((p, j) => {
        if (p.startsWith(".") || p.startsWith("@")) return <span key={j} className="text-green-400">{p}</span>;
        if (p === "import" || p === "from") return <span key={j} className="text-brand-400 font-semibold">{p}</span>;
        return <span key={j}>{p}</span>;
      });
    } else {
      let remaining = line;
      let key = 0;
      while (remaining.length > 0) {
        const kwMatch = remaining.match(SOL_KEYWORDS);
        const typeMatch = remaining.match(SOL_TYPES);

        if (kwMatch && kwMatch.index !== undefined) {
          const idx = kwMatch.index;
          if (idx > 0) { tokens.push(<span key={key++}>{remaining.slice(0, idx)}</span>); }
          tokens.push(<span key={key++} className="text-brand-400 font-semibold">{kwMatch[0]}</span>);
          remaining = remaining.slice(idx + kwMatch[0].length);
        } else if (typeMatch && typeMatch.index !== undefined) {
          const idx = typeMatch.index;
          if (idx > 0) { tokens.push(<span key={key++}>{remaining.slice(0, idx)}</span>); }
          tokens.push(<span key={key++} className="text-cyan-400">{typeMatch[0]}</span>);
          remaining = remaining.slice(idx + typeMatch[0].length);
        } else {
          tokens.push(<span key={key++}>{remaining}</span>);
          remaining = "";
        }
      }
    }

    return (
      <span key={i} className="block">
        {tokens}
        {i < lines.length - 1 ? "\n" : ""}
      </span>
    );
  });
}

type CodeBlockProps = {
  code: string;
  language?: string;
  caption?: React.ReactNode;
};

export function CodeBlock({ code, language = "solidity", caption }: CodeBlockProps) {
  return (
    <div className="rounded-xl border border-brand-500/15 bg-bg-deep/90 overflow-hidden">
      {language && (
        <div className="px-5 py-2 border-b border-brand-500/10 text-[0.7rem] text-text-muted font-semibold tracking-wider uppercase">
          {language}
        </div>
      )}
      <pre className="p-5 overflow-x-auto text-[0.8rem] leading-[1.6] font-mono text-text-primary">
        <code>{tokenize(code)}</code>
      </pre>
      {caption && (
        <div className="px-5 py-2.5 border-t border-brand-500/10 text-[0.75rem] text-text-muted">
          {caption}
        </div>
      )}
    </div>
  );
}
