// ── SVG icon set (refined minimal, 24×24 viewBox) ─────

const ICON = {
  pin: `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 21s7-4.5 7-11a7 7 0 1 0-14 0c0 6.5 7 11 7 11z"/><circle cx="12" cy="10" r="2.5"/></svg>`,
  globe: `<svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.5 2.8 4 6 4 9s-1.5 6.2-4 9M12 3c-2.5 2.8-4 6-4 9s1.5 6.2 4 9"/></svg>`,
  rain: `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M8 17v3M12 15v5M16 17v3"/><path d="M6 11a6 6 0 0 1 11-2 5 5 0 0 1 1 9.9H6z"/></svg>`,
  wind: `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M4 8h11a3 3 0 1 0-3-3M4 16h13a3 3 0 1 1-3 3M4 12h15"/></svg>`,
  sun: `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>`,
  alert: `<svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" aria-hidden="true"><path d="M12 9v4M12 17h.01"/><path d="M10.3 4.2 1.8 18.1A2 2 0 0 0 3.5 21h17a2 2 0 0 0 1.7-2.9L13.7 4.2a2 2 0 0 0-3.4 0z"/></svg>`,
};

function weatherIcon(code, size = 48) {
  const c = code ?? 0;
  let inner;
  if (c <= 1) {
    inner = `<circle cx="12" cy="12" r="4" fill="currentColor" opacity=".9"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" stroke="currentColor" stroke-width="1.75" stroke-linecap="round"/>`;
  } else if (c === 2) {
    inner = `<path d="M7 16h11a4 4 0 0 0 0-8 5 5 0 0 0-9.7 1.5A3.5 3.5 0 0 0 7 16z" fill="currentColor" opacity=".15" stroke="currentColor" stroke-width="1.75" stroke-linejoin="round"/>`;
  } else if (c === 3) {
    inner = `<path d="M6 16h12a4 4 0 0 0 0-8 5.5 5.5 0 0 0-10.8 1.2A3.5 3.5 0 0 0 6 16z" fill="currentColor" opacity=".2" stroke="currentColor" stroke-width="1.75"/>`;
  } else if (c === 45 || c === 48) {
    inner = `<path d="M4 16h16" stroke="currentColor" stroke-width="1.75" stroke-linecap="round"/><path d="M6 13h12M8 10h8" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" opacity=".5"/>`;
  } else if (c >= 51 && c <= 67) {
    inner = `<path d="M8 17v3M12 15v5M16 17v3" stroke="currentColor" stroke-width="1.75" stroke-linecap="round"/><path d="M6 11a5 5 0 0 1 9.5-1.8A4 4 0 0 1 18 13H6z" fill="currentColor" opacity=".15" stroke="currentColor" stroke-width="1.75"/>`;
  } else if ((c >= 71 && c <= 77) || c === 85 || c === 86) {
    inner = `<path d="M12 4v12M9 7l3-3 3 3M8 19h8" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"/>`;
  } else if (c >= 95) {
    inner = `<path d="M13 3L5 14h7l-1 7 9-12h-7l1-6z" fill="currentColor" opacity=".85"/>`;
  } else {
    inner = `<path d="M8 17v3M12 15v5M16 17v3" stroke="currentColor" stroke-width="1.75" stroke-linecap="round"/><path d="M6 11a5 5 0 0 1 9.5-1.8A4 4 0 0 1 18 13H6z" fill="currentColor" opacity=".15" stroke="currentColor" stroke-width="1.75"/>`;
  }
  return `<svg class="w-icon" width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" aria-hidden="true">${inner}</svg>`;
}
