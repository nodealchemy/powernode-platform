// Git Providers Feature - shared constants

/**
 * Vendor brand background colors for git providers.
 *
 * These are fixed brand hexes (intentionally NOT theme-tokenized — a vendor's
 * brand color is constant across light/dark). Single source of truth: consume
 * this map instead of inlining the literals so a hex fix or a new provider
 * lands in exactly one place.
 */
export const GIT_PROVIDER_BRAND_BG: Record<string, string> = {
  github: 'bg-[#24292f]',
  gitlab: 'bg-[#FC6D26]',
  gitea: 'bg-[#609926]',
  bitbucket: 'bg-[#0052CC]',
};
