import { getHttpMethodColor, getStatusColor, getPriorityColor } from './nodeColorUtils';

const SUCCESS = 'text-theme-success-fg bg-theme-success-fg/20';
const INFO = 'text-theme-info-fg bg-theme-info-fg/20';
const WARNING = 'text-theme-warning-fg bg-theme-warning-fg/20';
const DANGER = 'text-theme-danger-fg bg-theme-danger-fg/20';
const TERTIARY = 'text-theme-tertiary bg-theme-background-secondary/20';
const NEUTRAL = 'text-theme-secondary bg-theme-surface/20';

describe('getHttpMethodColor', () => {
  it('maps methods (case-insensitive) and shares PUT/PATCH', () => {
    expect(getHttpMethodColor('GET')).toBe(SUCCESS);
    expect(getHttpMethodColor('get')).toBe(SUCCESS);
    expect(getHttpMethodColor('POST')).toBe(INFO);
    expect(getHttpMethodColor('PUT')).toBe(WARNING);
    expect(getHttpMethodColor('PATCH')).toBe(WARNING);
    expect(getHttpMethodColor('DELETE')).toBe(DANGER);
  });

  it('defaults to info for unknown/undefined methods', () => {
    expect(getHttpMethodColor('HEAD')).toBe(INFO);
    expect(getHttpMethodColor(undefined)).toBe(INFO);
  });
});

describe('getStatusColor (node)', () => {
  it('groups synonyms to one class (case-insensitive)', () => {
    ['published', 'active', 'success', 'completed', 'ACTIVE'].forEach((s) =>
      expect(getStatusColor(s)).toBe(SUCCESS)
    );
    ['draft', 'pending', 'waiting'].forEach((s) => expect(getStatusColor(s)).toBe(WARNING));
    ['archived', 'inactive', 'skipped'].forEach((s) => expect(getStatusColor(s)).toBe(TERTIARY));
    ['error', 'failed', 'rejected'].forEach((s) => expect(getStatusColor(s)).toBe(DANGER));
    ['running', 'processing'].forEach((s) => expect(getStatusColor(s)).toBe(INFO));
  });

  it('defaults to neutral for unknown/undefined status', () => {
    expect(getStatusColor('whatever')).toBe(NEUTRAL);
    expect(getStatusColor(undefined)).toBe(NEUTRAL);
  });
});

describe('getPriorityColor', () => {
  it('maps named priorities (case-insensitive) and numeric 1/2/3', () => {
    ['high', 'critical', 'urgent', 'HIGH'].forEach((p) => expect(getPriorityColor(p)).toBe(DANGER));
    expect(getPriorityColor(1)).toBe(DANGER);

    ['medium', 'normal'].forEach((p) => expect(getPriorityColor(p)).toBe(WARNING));
    expect(getPriorityColor(2)).toBe(WARNING);

    expect(getPriorityColor('low')).toBe(SUCCESS);
    expect(getPriorityColor(3)).toBe(SUCCESS);
  });

  it('defaults to neutral for unknown values (string, out-of-range number, undefined)', () => {
    expect(getPriorityColor('trivial')).toBe(NEUTRAL);
    expect(getPriorityColor(4)).toBe(NEUTRAL);
    expect(getPriorityColor(undefined)).toBe(NEUTRAL);
  });
});
