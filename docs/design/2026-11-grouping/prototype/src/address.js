// Addresses are mutable endpoints; the device's stable id is kept separately.
export function normalizeDeviceAddress(value) {
  let host = value.trim();
  if (!host || /[\s/?#@\\]/.test(host)) return null;
  if (host.startsWith("[") && host.endsWith("]")) host = host.slice(1, -1);
  if (host.includes(":")) {
    try {
      return new URL(`http://[${host}]/`).hostname.slice(1, -1).toLowerCase();
    } catch {
      return null;
    }
  }
  if (/^[\d.]+$/.test(host)) {
    const octets = host.split(".");
    return octets.length === 4 &&
      octets.every((part) => /^\d{1,3}$/.test(part) && Number(part) <= 255)
      ? octets.map(Number).join(".")
      : null;
  }
  if (host.endsWith(".")) host = host.slice(0, -1);
  if (host.length > 253) return null;
  return host
    .split(".")
    .every((part) =>
      /^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$/.test(part),
    )
    ? host.toLowerCase()
    : null;
}
