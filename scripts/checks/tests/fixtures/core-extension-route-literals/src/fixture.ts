// Fixture for core-extension-route-literals.rb --self-test. Exactly 8 of the
// literals below are extension routes; the rest must not be flagged.
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

// must NOT flag
export const n1 = '/systemic';
export const n2 = '/app/system/providers';
export const n3 = '/billings';
export const n4 = '/mcp/hostingx';
export const n5 = 'system/relative';
export const n6 = '/ai/goals/1/plans';
export const n7 = '/admin/marketplace';
