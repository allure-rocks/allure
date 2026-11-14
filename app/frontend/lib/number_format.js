// Locale-aware number display (DESIGN.md §3.5), the browser twin of the
// server's `format_decimal`: « 4 381 » and « 12,5 » on a French page, "4,381"
// and "12.5" on an English one. The locale is the page's own `<html lang>`.
const formatters = new Map();

export function formatNumber(value, digits = 0) {
  const locale = document.documentElement.lang || undefined;
  const key = `${locale}:${digits}`;
  if (!formatters.has(key)) {
    formatters.set(key, new Intl.NumberFormat(locale, { minimumFractionDigits: digits, maximumFractionDigits: digits }));
  }
  return formatters.get(key).format(value);
}
