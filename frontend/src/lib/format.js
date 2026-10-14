/*
 * format.js — turning raw rupee amounts into something a person can read.
 *
 * WHERE THIS FITS: a leaf utility module. Every component that prints a
 * number imports from here, so that "₹1.13 Cr" looks identical in a stat tile,
 * a chart axis and a table cell.
 *
 * Indian number formatting is not the same as Western formatting, and getting
 * it wrong makes a calculator feel foreign immediately:
 *
 *   - digits group as 12,34,56,789 (lakh/crore), not 123,456,789
 *   - large amounts are spoken in lakh (10^5) and crore (10^7), not millions
 *
 * The backend always sends plain rupees. All of the lakh/crore conversion
 * lives here, on the display side, so the arithmetic never has to deal with
 * mixed units.
 */

const INR = new Intl.NumberFormat('en-IN', { maximumFractionDigits: 0 });

const LAKH = 100000;
const CRORE = 10000000;

/**
 * Full precision with Indian digit grouping: 1,13,24,567 → "₹1,13,24,567".
 * Used in tables and tooltips, where the exact figure is the point.
 */
export function rupees(n) {
  if (!isFinite(n)) return '—';
  return '₹' + INR.format(Math.round(n));
}

/**
 * Compact, for headlines and axis ticks: "₹1.13 Cr", "₹45.2 L", "₹30,000".
 *
 * Crore gets two decimals and lakh gets one, which is roughly how people
 * actually say these numbers out loud — "one point one three crore",
 * "forty-five lakh".
 */
export function compactRupees(n) {
  if (!isFinite(n)) return '—';
  const abs = Math.abs(n);
  const sign = n < 0 ? '-' : '';

  if (abs >= CRORE) return `${sign}₹${(abs / CRORE).toFixed(2)} Cr`;
  if (abs >= LAKH) return `${sign}₹${(abs / LAKH).toFixed(1)} L`;
  return `${sign}₹${INR.format(Math.round(abs))}`;
}

/**
 * The same, minus the currency symbol — for axis ticks, where repeating "₹"
 * on every gridline is noise once the axis title has said it.
 */
export function compactNumber(n) {
  if (!isFinite(n)) return '—';
  const abs = Math.abs(n);
  const sign = n < 0 ? '-' : '';

  if (abs >= CRORE) {
    const v = abs / CRORE;
    // Drop the decimal on whole crores so an axis reads 2, 4, 6 Cr rather
    // than 2.0, 4.0, 6.0 Cr.
    return `${sign}${v % 1 === 0 ? v : v.toFixed(1)} Cr`;
  }
  if (abs >= LAKH) {
    const v = abs / LAKH;
    return `${sign}${v % 1 === 0 ? v : v.toFixed(1)} L`;
  }
  return `${sign}${INR.format(Math.round(abs))}`;
}

/** Percentages, to one decimal: 3.0421… → "3.0%". */
export function percent(n, digits = 1) {
  if (!isFinite(n)) return '—';
  return `${n.toFixed(digits)}%`;
}

/** A funded ratio of 1.0684 → "107%". */
export function ratioAsPercent(n) {
  if (!isFinite(n)) return '—';
  return `${Math.round(n * 100)}%`;
}

/** A signed percentage with a true minus sign: -28.4 → "−28%", 3.2 → "+3%". */
export function signedPercent(n, digits = 0) {
  if (!isFinite(n)) return '—';
  const v = Number(Math.abs(n).toFixed(digits));
  if (v === 0) return '0%';
  return `${n < 0 ? '−' : '+'}${v.toFixed(digits)}%`;
}
