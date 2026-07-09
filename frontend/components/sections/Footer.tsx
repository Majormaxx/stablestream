import Image from "next/image";

export function Footer() {
  return (
    <footer className="border-t border-brand-500/12 px-6 py-[40px_24px_32px] text-center">
      <div className="flex items-center justify-center gap-3 mb-4">
        <Image src="/logo.svg" alt="StableStream" width={28} height={28}/>
        <span className="font-bold text-text-primary">Stable<span className="text-brand-400">Stream</span></span>
      </div>
      <p className="text-text-muted text-[0.8rem] tracking-[0.5px]">
        Deployed on Unichain Sepolia · Powered by Reactive Network
      </p>
      <div className="mt-5">
        <a
          href="https://x.com/HQstablestream"
          target="_blank"
          rel="noopener noreferrer"
          className="inline-flex items-center gap-2 px-5 py-2 rounded-[8px] text-[0.85rem] font-medium no-underline transition-all duration-150"
          style={{
            background: "linear-gradient(135deg, rgba(0,102,255,0.12), rgba(0,170,255,0.08))",
            border: "1px solid rgba(0,102,255,0.2)",
            color: "#00AAFF",
          }}
          onMouseOver={e => { e.currentTarget.style.background = "linear-gradient(135deg, rgba(0,102,255,0.2), rgba(0,170,255,0.12))"; e.currentTarget.style.borderColor = "rgba(0,102,255,0.4)" }}
          onMouseOut={e => { e.currentTarget.style.background = "linear-gradient(135deg, rgba(0,102,255,0.12), rgba(0,170,255,0.08))"; e.currentTarget.style.borderColor = "rgba(0,102,255,0.2)" }}
        >
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
            <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" fill="#00AAFF"/>
          </svg>
          @HQstablestream
        </a>
      </div>
    </footer>
  );
}
