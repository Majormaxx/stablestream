#!/usr/bin/env python3
"""Serves the StableStream logo SVG on http://localhost:8765/logo.svg"""
import http.server, socketserver

SVG = b"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 420 120" width="420" height="120">
  <defs>
    <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#0a0a0f"/>
      <stop offset="100%" style="stop-color:#0d1117"/>
    </linearGradient>
    <linearGradient id="stream" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" style="stop-color:#7c3aed"/>
      <stop offset="50%" style="stop-color:#06b6d4"/>
      <stop offset="100%" style="stop-color:#10b981"/>
    </linearGradient>
    <linearGradient id="icon" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#7c3aed"/>
      <stop offset="100%" style="stop-color:#06b6d4"/>
    </linearGradient>
    <filter id="glow">
      <feGaussianBlur stdDeviation="2.5" result="blur"/>
      <feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
    <clipPath id="round"><rect width="420" height="120" rx="16"/></clipPath>
  </defs>

  <!-- Background -->
  <rect width="420" height="120" rx="16" fill="url(#bg)"/>
  <rect width="420" height="120" rx="16" fill="none" stroke="url(#stream)" stroke-width="1.5" opacity="0.4"/>

  <!-- Icon: stacked liquidity bars with flow arrow -->
  <g transform="translate(22, 20)" filter="url(#glow)">
    <!-- Bars representing liquidity range -->
    <rect x="0"  y="30" width="10" height="50" rx="3" fill="url(#icon)" opacity="0.4"/>
    <rect x="14" y="18" width="10" height="62" rx="3" fill="url(#icon)" opacity="0.6"/>
    <rect x="28" y="8"  width="10" height="72" rx="3" fill="url(#icon)" opacity="0.9"/>
    <rect x="42" y="18" width="10" height="62" rx="3" fill="url(#icon)" opacity="0.6"/>
    <rect x="56" y="30" width="10" height="50" rx="3" fill="url(#icon)" opacity="0.4"/>
    <!-- Flow arrow underneath -->
    <path d="M 0 88 Q 33 100 66 88" stroke="url(#stream)" stroke-width="2.5" fill="none" stroke-linecap="round"/>
    <polygon points="62,83 70,88 62,93" fill="#06b6d4"/>
  </g>

  <!-- Wordmark -->
  <text x="112" y="58" font-family="'Inter','Segoe UI',system-ui,sans-serif"
        font-size="34" font-weight="700" letter-spacing="-1"
        fill="url(#stream)">StableStream</text>

  <!-- Tagline -->
  <text x="113" y="82" font-family="'Inter','Segoe UI',system-ui,sans-serif"
        font-size="13" font-weight="400" letter-spacing="0.5"
        fill="#94a3b8">Idle liquidity, automated.</text>

  <!-- Reactive Network badge -->
  <g transform="translate(113, 92)">
    <rect width="110" height="18" rx="4" fill="#7c3aed" opacity="0.15"/>
    <rect width="110" height="18" rx="4" fill="none" stroke="#7c3aed" stroke-width="0.8" opacity="0.5"/>
    <circle cx="10" cy="9" r="3.5" fill="#7c3aed"/>
    <text x="19" y="13" font-family="'Inter','Segoe UI',system-ui,sans-serif"
          font-size="9.5" font-weight="500" fill="#a78bfa" letter-spacing="0.3">Reactive Network</text>
  </g>

  <!-- Unichain badge -->
  <g transform="translate(232, 92)">
    <rect width="78" height="18" rx="4" fill="#06b6d4" opacity="0.12"/>
    <rect width="78" height="18" rx="4" fill="none" stroke="#06b6d4" stroke-width="0.8" opacity="0.4"/>
    <circle cx="10" cy="9" r="3.5" fill="#06b6d4"/>
    <text x="19" y="13" font-family="'Inter','Segoe UI',system-ui,sans-serif"
          font-size="9.5" font-weight="500" fill="#67e8f9" letter-spacing="0.3">Unichain v4</text>
  </g>
</svg>"""

HTML = b"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<title>StableStream Logo</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    background: #0a0a0f;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    min-height: 100vh;
    font-family: 'Inter', system-ui, sans-serif;
    gap: 32px;
  }
  h1 { color: #94a3b8; font-size: 13px; letter-spacing: 2px; text-transform: uppercase; }
  .card {
    background: #0d1117;
    border: 1px solid rgba(124,58,237,0.25);
    border-radius: 20px;
    padding: 48px 56px;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 28px;
  }
  .preview { display: flex; gap: 24px; align-items: center; flex-wrap: wrap; justify-content: center; }
  .bg-white { background: #fff; padding: 20px 28px; border-radius: 12px; }
  label { color: #475569; font-size: 11px; letter-spacing: 1px; text-align: center; margin-top: 4px; }
  .actions { display: flex; gap: 12px; }
  a.btn {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 11px 22px;
    border-radius: 10px;
    font-size: 14px;
    font-weight: 600;
    text-decoration: none;
    cursor: pointer;
    transition: opacity 0.15s;
  }
  a.btn:hover { opacity: 0.85; }
  .btn-svg {
    background: linear-gradient(135deg, #7c3aed, #06b6d4);
    color: #fff;
  }
  .btn-png {
    background: #1e293b;
    color: #94a3b8;
    border: 1px solid #334155;
  }
  canvas { display: none; }
</style>
</head>
<body>
<h1>StableStream &mdash; Logo</h1>
<div class="card">
  <div class="preview">
    <div>
      <div id="dark-preview"></div>
      <label>Dark background</label>
    </div>
    <div>
      <div class="bg-white" id="light-preview"></div>
      <label>Light background</label>
    </div>
  </div>
  <div class="actions">
    <a class="btn btn-svg" id="dl-svg" download="stablestream-logo.svg" href="/logo.svg">
      &#8659; Download SVG
    </a>
    <a class="btn btn-png" id="dl-png" href="#" download="stablestream-logo.png">
      &#8659; Download PNG
    </a>
  </div>
</div>
<canvas id="cvs"></canvas>
<script>
  const svgUrl = '/logo.svg';

  // Inject SVG into both previews
  fetch(svgUrl).then(r => r.text()).then(svg => {
    document.getElementById('dark-preview').innerHTML = svg;
    document.getElementById('light-preview').innerHTML = svg;
  });

  // PNG export via canvas
  document.getElementById('dl-png').addEventListener('click', function(e) {
    e.preventDefault();
    const img = new Image();
    const blob = new Blob([document.getElementById('dark-preview').innerHTML], {type:'image/svg+xml'});
    const url = URL.createObjectURL(blob);
    img.onload = () => {
      const scale = 3;
      const cvs = document.getElementById('cvs');
      cvs.width = 420 * scale;
      cvs.height = 120 * scale;
      const ctx = cvs.getContext('2d');
      ctx.scale(scale, scale);
      ctx.drawImage(img, 0, 0);
      URL.revokeObjectURL(url);
      const link = document.createElement('a');
      link.download = 'stablestream-logo.png';
      link.href = cvs.toDataURL('image/png');
      link.click();
    };
    img.src = url;
  });
</script>
</body>
</html>"""

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/logo.svg":
            self.send_response(200)
            self.send_header("Content-Type", "image/svg+xml")
            self.send_header("Content-Length", str(len(SVG)))
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            self.wfile.write(SVG)
        elif self.path in ("/", "/index.html"):
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(HTML)))
            self.end_headers()
            self.wfile.write(HTML)
        else:
            self.send_response(404); self.end_headers()
    def log_message(self, *_): pass

PORT = 8765
with socketserver.TCPServer(("", PORT), Handler) as httpd:
    print(f"Logo ready → http://localhost:{PORT}/logo.svg")
    print("Right-click the image in your browser and Save As to download.")
    print("Ctrl+C to stop.")
    httpd.serve_forever()
