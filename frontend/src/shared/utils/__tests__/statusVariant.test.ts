import { statusVariant, severityVariant, STATUS_VARIANTS, SEVERITY_VARIANTS } from '@/shared/utils/statusVariant';

// One status/severity -> Badge variant mapping, replacing the per-page
// getStatusColor / getSeverityColor copies (plan §3).
//
// EXHAUSTIVE: the expected tables below are written out independently of the
// module's own tables, and must cover its whole vocabulary — adding, dropping
// or moving a status fails here until the table is updated deliberately.
//
// The in-progress split: anything still WORKING (running, building,
// deploying, provisioning, indexing, ...) is info; warning is for states that
// need attention (degraded, pending approval, paused, retrying, stale, ...).
const EXPECTED_STATUS: Record<string, string> = {
  active: 'success', completed: 'success', complete: 'success', succeeded: 'success', success: 'success',
  passed: 'success', healthy: 'success', connected: 'success', approved: 'success', published: 'success',
  indexed: 'success', compliant: 'success', achieved: 'success', resolved: 'success', enabled: 'success',
  online: 'success', ready: 'success', verified: 'success', available: 'success',

  running: 'info', in_progress: 'info', analyzing: 'info', queued: 'info', scheduled: 'info',
  processing: 'info', syncing: 'info', building: 'info', deploying: 'info', provisioning: 'info',
  preparing: 'info', connecting: 'info', indexing: 'info',

  pending: 'warning', pending_review: 'warning', pending_approval: 'warning', degraded: 'warning',
  warning: 'warning', suspended: 'warning', paused: 'warning', stale: 'warning', retrying: 'warning',

  failed: 'danger', failure: 'danger', error: 'danger', rejected: 'danger', revoked: 'danger',
  unhealthy: 'danger', timeout: 'danger', timed_out: 'danger', disconnected: 'danger', offline: 'danger',
  expired: 'danger', abandoned: 'danger', non_compliant: 'danger', blocked: 'danger',

  inactive: 'default', archived: 'default', draft: 'default', cancelled: 'default', canceled: 'default',
  disabled: 'default', unknown: 'default', none: 'default', skipped: 'default',
};

const EXPECTED_SEVERITY: Record<string, string> = {
  critical: 'danger', high: 'danger', severe: 'danger',
  medium: 'warning', moderate: 'warning',
  low: 'info', info: 'info', informational: 'info',
  none: 'default', unknown: 'default',
};

describe('statusVariant', () => {
  it('covers exactly the module vocabulary', () => {
    expect(Object.values(STATUS_VARIANTS).flat().sort()).toEqual(Object.keys(EXPECTED_STATUS).sort());
  });

  it.each(Object.entries(EXPECTED_STATUS))('maps %s to %s', (status, variant) => {
    expect(statusVariant(status)).toBe(variant);
  });

  it('normalises case, spaces and hyphens', () => {
    expect(statusVariant('In Progress')).toBe('info');
    expect(statusVariant('non-compliant')).toBe('danger');
    expect(statusVariant('  COMPLETED ')).toBe('success');
  });

  it('maps an unknown, empty or missing status to default', () => {
    expect(statusVariant('frobnicating')).toBe('default');
    expect(statusVariant('')).toBe('default');
    expect(statusVariant(null)).toBe('default');
    expect(statusVariant(undefined)).toBe('default');
  });

  it('lists each status once', () => {
    const all = Object.values(STATUS_VARIANTS).flat();
    expect(all.filter((s, i) => all.indexOf(s) !== i)).toEqual([]);
  });
});

describe('severityVariant', () => {
  it('covers exactly the module vocabulary', () => {
    expect(Object.values(SEVERITY_VARIANTS).flat().sort()).toEqual(Object.keys(EXPECTED_SEVERITY).sort());
  });

  it.each(Object.entries(EXPECTED_SEVERITY))('maps %s to %s', (severity, variant) => {
    expect(severityVariant(severity)).toBe(variant);
  });

  it('normalises case and maps an unknown or missing severity to default', () => {
    expect(severityVariant('HIGH')).toBe('danger');
    expect(severityVariant('severe-ish')).toBe('default');
    expect(severityVariant(undefined)).toBe('default');
  });

  it('lists each severity once', () => {
    const all = Object.values(SEVERITY_VARIANTS).flat();
    expect(all.filter((s, i) => all.indexOf(s) !== i)).toEqual([]);
  });
});
