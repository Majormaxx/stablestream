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
        <span key="c" className="text-slate italic">{line}</span>
      );
    } else if (isImport) {
      const parts = line.split(/(["';])/g);
      tokens = parts.map((p, j) => {
        if (p.startsWith(".") || p.startsWith("@")) return <span key={j} className="text-current">{p}</span>;
        if (p === "import" || p === "from") return <span key={j} className="text-signal font-semibold">{p}</span>;
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
          tokens.push(<span key={key++} className="text-signal font-semibold">{kwMatch[0]}</span>);
          remaining = remaining.slice(idx + kwMatch[0].length);
        } else if (typeMatch && typeMatch.index !== undefined) {
          const idx = typeMatch.index;
          if (idx > 0) { tokens.push(<span key={key++}>{remaining.slice(0, idx)}</span>); }
          tokens.push(<span key={key++} className="text-current">{typeMatch[0]}</span>);
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
  label?: React.ReactNode;
  caption?: React.ReactNode;
};

export function CodeBlock({ code, language = "solidity", label, caption }: CodeBlockProps) {
  return (
    <div className="rounded-xl border border-rail bg-ink/90 overflow-hidden">
      {(language || label) && (
        <div className="px-5 py-2.5 border-b border-rail/60 text-[0.7rem] text-slate font-semibold tracking-wider uppercase">
          {label ?? language}
        </div>
      )}
      <pre className="p-5 overflow-x-auto text-[0.8rem] leading-[1.6] font-mono text-paper">
        <code>{tokenize(code)}</code>
      </pre>
      {caption && (
        <div className="px-5 py-2.5 border-t border-rail/60 text-[0.75rem] text-slate leading-[1.6]">
          {caption}
        </div>
      )}
    </div>
  );
}
