// Fixture for core-extension-route-literals.rb --self-test. Exactly 11 of the
// literals below are extension routes; the rest must not be flagged. Not
// compiled: the JSX lines exist only to exercise the comment stripper.
// '/system/in/a/comment' — comments are stripped
/* '/billing/in/a/block/comment' */

// MUST flag (8)
export const a = '/system/platform/volumes';
export const b = "/business/plans";
export const c = `/api/v1/system/node_instance_peers/${1}`;
export const d = '/plans';
export const e = '/billing?tab=invoices';
export const f = '/marketplace#top';
export const g = '/mcp/hosting/servers';
export const h = '/system';

// MUST flag (3): a '//' that is not a comment must not hide a later literal
// - an apostrophe in JSX text closes at end of line, not at the next quote
export const j1 = <p>Don't panic</p>;
export const j2 = '//cdn.example.com/docs'; export const j3 = '/billing/x';
// - an unmatched apostrophe earlier on the same line: '//' after ':' is a URL
export const k1 = <p>Won't</p>; export const k2 = 'https://x.io'; export const k3 = '/plans';
// - a '//' inside a regex literal
export const r1 = /^https?:\/\//.test(k2) ? '/business/y' : '';

// must NOT flag
export const n1 = '/systemic';
export const n2 = '/app/system/providers';
export const n3 = '/billings';
export const n4 = '/mcp/hostingx';
export const n5 = 'system/relative';
export const n6 = '/ai/goals/1/plans';
export const n7 = '/admin/marketplace';
