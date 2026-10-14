const INR = new Intl.NumberFormat('en-IN', { maximumFractionDigits: 0 });

const LAKH = 100000;
const CRORE = 10000000;

export function rupees(n) {
  if (!isFinite(n)) return '—';
  return '₹' + INR.format(Math.round(n));
}

export function compactRupees(n) {
  if (!isFinite(n)) return '—';
  const abs = Math.abs(n);
  const sign = n < 0 ? '-' : '';

  if (abs >= CRORE) return `${sign}₹${(abs / CRORE).toFixed(2)} Cr`;
  if (abs >= LAKH) return `${sign}₹${(abs / LAKH).toFixed(1)} L`;
  return `${sign}₹${INR.format(Math.round(abs))}`;
}

export function compactNumber(n) {
  if (!isFinite(n)) return '—';
  const abs = Math.abs(n);
  const sign = n < 0 ? '-' : '';

  if (abs >= CRORE) {
    const v = abs / CRORE;
    return `${sign}${v % 1 === 0 ? v : v.toFixed(1)} Cr`;
  }
  if (abs >= LAKH) {
    const v = abs / LAKH;
    return `${sign}${v % 1 === 0 ? v : v.toFixed(1)} L`;
  }
  return `${sign}${INR.format(Math.round(abs))}`;
}

export function percent(n, digits = 1) {
  if (!isFinite(n)) return '—';
  return `${n.toFixed(digits)}%`;
}

export function ratioAsPercent(n) {
  if (!isFinite(n)) return '—';
  return `${Math.round(n * 100)}%`;
}

export function signedPercent(n, digits = 0) {
  if (!isFinite(n)) return '—';
  const v = Number(Math.abs(n).toFixed(digits));
  if (v === 0) return '0%';
  return `${n < 0 ? '−' : '+'}${v.toFixed(digits)}%`;
}
