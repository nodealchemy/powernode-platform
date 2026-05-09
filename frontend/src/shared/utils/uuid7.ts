/**
 * Browser-side UUIDv7 generator.
 *
 * Mirrors the platform's `UUID7.generate` (uuid7 gem) used server-side for
 * persistent primary-key fallbacks. Browser builds don't have the gem so we
 * generate v7 ids inline when the client needs to allocate an id before the
 * server has created the row (lazy-conversation-creation flow).
 *
 * Layout (RFC 9562):
 *   48 bits: unix timestamp ms
 *   4 bits:  version (7)
 *   12 bits: random
 *   2 bits:  variant (10)
 *   62 bits: random
 */
export function uuid7(): string {
  const buf = new Uint8Array(16);
  crypto.getRandomValues(buf);

  const ts = BigInt(Date.now());
  buf[0] = Number((ts >> 40n) & 0xffn);
  buf[1] = Number((ts >> 32n) & 0xffn);
  buf[2] = Number((ts >> 24n) & 0xffn);
  buf[3] = Number((ts >> 16n) & 0xffn);
  buf[4] = Number((ts >> 8n) & 0xffn);
  buf[5] = Number(ts & 0xffn);

  buf[6] = (buf[6] & 0x0f) | 0x70;
  buf[8] = (buf[8] & 0x3f) | 0x80;

  const hex = Array.from(buf, (b) => b.toString(16).padStart(2, '0')).join('');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20, 32)}`;
}
