import math, sys, json

def svg(p):
    """p: palette dict"""
    cx, cy = 494, 486          # iris centre
    R = 126                    # iris radius (clipped by the lids)
    almond = "M180 506 C 300 352, 650 330, 800 472 C 660 624, 320 632, 180 506 Z"
    ticks = []
    for i in range(12):
        a = math.radians(i * 30)
        r1, r2 = (R - 30, R - 12) if i % 3 == 0 else (R - 24, R - 12)
        w = 9 if i % 3 == 0 else 5
        ticks.append(f'<line x1="{cx + r1*math.sin(a):.1f}" y1="{cy - r1*math.cos(a):.1f}" x2="{cx + r2*math.sin(a):.1f}" y2="{cy - r2*math.cos(a):.1f}" stroke-width="{w}"/>')
    def hand(deg, length):
        a = math.radians(deg)
        return f"{cx + length*math.sin(a):.1f},{cy - length*math.cos(a):.1f}"
    check = f'{hand(300, 64)} {cx},{cy} {hand(60, 100)}'
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
<defs>
  <radialGradient id="bg" cx="50%" cy="36%" r="78%">
    <stop offset="0" stop-color="{p['bg'][0]}"/><stop offset="0.6" stop-color="{p['bg'][1]}"/><stop offset="1" stop-color="{p['bg'][2]}"/>
  </radialGradient>
  <linearGradient id="metal" gradientUnits="userSpaceOnUse" x1="200" y1="230" x2="840" y2="850">
    <stop offset="0" stop-color="{p['metal'][0]}"/><stop offset="0.5" stop-color="{p['metal'][1]}"/><stop offset="1" stop-color="{p['metal'][2]}"/>
  </linearGradient>
  <radialGradient id="iris" gradientUnits="userSpaceOnUse" cx="{cx-34}" cy="{cy-40}" r="{R*1.25}">
    <stop offset="0" stop-color="{p['iris'][0]}"/><stop offset="0.55" stop-color="{p['iris'][1]}"/><stop offset="1" stop-color="{p['iris'][2]}"/>
  </radialGradient>
  <radialGradient id="sclera" gradientUnits="userSpaceOnUse" cx="{cx}" cy="{cy-30}" r="330">
    <stop offset="0" stop-color="{p['sclera'][0]}"/><stop offset="1" stop-color="{p['sclera'][1]}"/>
  </radialGradient>
  <clipPath id="eye"><path d="{almond}"/></clipPath>
  <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
    <feDropShadow dx="0" dy="12" stdDeviation="18" flood-color="#000" flood-opacity="{p.get('shadow', 0.42)}"/>
  </filter>
  <filter id="inner" x="-10%" y="-10%" width="120%" height="120%">
    <feDropShadow dx="0" dy="10" stdDeviation="10" flood-color="#000" flood-opacity="0.35"/>
  </filter>
</defs>
<rect width="1024" height="1024" fill="url(#bg)"/>
<g transform="translate(-22 2)">
  <!-- eyeball: sclera, then the iris tucked under both lids -->
  <g clip-path="url(#eye)">
    <path d="{almond}" fill="url(#sclera)"/>
    <g filter="url(#inner)">
      <circle cx="{cx}" cy="{cy}" r="{R}" fill="url(#iris)"/>
    </g>
    <circle cx="{cx}" cy="{cy}" r="{R-4}" fill="none" stroke="{p['ink']}" stroke-opacity="0.35" stroke-width="7"/>
    <g stroke="{p['ink']}" stroke-opacity="0.55" stroke-linecap="round">{''.join(ticks)}</g>
    <!-- soft shading so the iris reads as round -->
    <circle cx="{cx}" cy="{cy}" r="{R}" fill="none" stroke="#000" stroke-opacity="0.18" stroke-width="22" transform="translate(6 10)"/>
  </g>
  <!-- pupil with clock hands growing out of it -->
  <circle cx="{cx}" cy="{cy}" r="27" fill="{p['ink']}"/>
  <polyline points="{check}" fill="none" stroke="{p['ink']}" stroke-width="18" stroke-linecap="round" stroke-linejoin="round"/>
  <!-- catchlight -->
  <ellipse cx="{cx+50}" cy="{cy+34}" rx="13" ry="9" fill="#FFFFFF" fill-opacity="0.85" transform="rotate(-25 {cx+50} {cy+34})"/>
  <circle cx="{cx+72}" cy="{cy+50}" r="4.5" fill="#FFFFFF" fill-opacity="0.6"/>
  <!-- lids, brow and markings on top -->
  <g filter="url(#shadow)">
    <path d="M176 352 C 330 246, 660 232, 858 296 C 878 302, 876 330, 856 328 C 660 280, 360 296, 196 384 C 176 394, 162 362, 176 352 Z" fill="url(#metal)"/>
    <g fill="none" stroke="url(#metal)" stroke-linejoin="round" stroke-linecap="round">
      <path d="M180 506 C 300 352, 650 330, 800 472 L 892 472" stroke-width="50"/>
      <path d="M180 506 C 320 632, 660 624, 800 472" stroke-width="36"/>
      <path d="M590 608 C 616 690, 678 754, 770 764 C 850 772, 884 704, 842 670 C 806 640, 760 670, 782 706" stroke-width="42"/>
    </g>
    <path d="M404 580 L 466 580 L 436 812 C 433 838, 393 838, 392 812 Z" fill="url(#metal)"/>
  </g>
</g>
</svg>'''

PALETTES = json.load(open('palettes.json'))
for name in sys.argv[1:]:
    open(f'{name}.svg', 'w').write(svg(PALETTES[name]))
