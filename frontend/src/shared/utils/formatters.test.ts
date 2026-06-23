import {
  formatCurrency,
  formatDate,
  formatRelativeTime,
  formatNumber,
  formatPercent,
  formatFileSize,
  capitalize,
  truncate,
  formatCardDisplay,
  formatBankAccountDisplay,
  formatSubscriptionPrice,
  calculateDiscountedPrice,
  calculateAnnualSavings,
  normalizePriceCents,
  getBillingCycleLabel,
  isPromotionalDiscountActive,
} from './formatters';

describe('formatCurrency', () => {
  it("returns '$0.00' for null/undefined", () => {
    expect(formatCurrency(null)).toBe('$0.00');
    expect(formatCurrency(undefined)).toBe('$0.00');
  });

  it('converts cents to a USD string', () => {
    expect(formatCurrency(1000)).toBe('$10.00');
    expect(formatCurrency(1234)).toBe('$12.34');
    expect(formatCurrency(0)).toBe('$0.00');
  });

  it('parses numeric strings and falls back to $0.00 for non-numeric / NaN', () => {
    expect(formatCurrency('1000')).toBe('$10.00');
    expect(formatCurrency('not-a-number')).toBe('$0.00');
    expect(formatCurrency(NaN)).toBe('$0.00');
  });

  it('honors the currency code', () => {
    expect(formatCurrency(1000, 'eur')).toContain('10.00'); // code upper-cased internally
  });
});

describe('formatDate', () => {
  it("returns '—' for empty values", () => {
    expect(formatDate(null)).toBe('—');
    expect(formatDate(undefined)).toBe('—');
    expect(formatDate('')).toBe('—');
  });

  it('formats a Date as a short en-US date', () => {
    // Local-time Date (no TZ shift) keeps the assertion stable across runners.
    expect(formatDate(new Date(2024, 0, 15))).toBe('Jan 15, 2024');
  });
});

describe('formatRelativeTime', () => {
  beforeEach(() => {
    jest.useFakeTimers();
    jest.setSystemTime(new Date('2024-06-15T12:00:00Z'));
  });
  afterEach(() => {
    jest.useRealTimers();
  });

  it("returns 'Never' for null", () => {
    expect(formatRelativeTime(null)).toBe('Never');
  });

  it('buckets past times', () => {
    expect(formatRelativeTime(new Date('2024-06-15T11:59:40Z'))).toBe('Just now');
    expect(formatRelativeTime(new Date('2024-06-15T11:55:00Z'))).toBe('5m ago');
    expect(formatRelativeTime(new Date('2024-06-15T10:00:00Z'))).toBe('2h ago');
    expect(formatRelativeTime(new Date('2024-06-12T12:00:00Z'))).toBe('3d ago');
  });

  it('buckets future times', () => {
    expect(formatRelativeTime(new Date('2024-06-15T12:00:30Z'))).toBe('in a few seconds');
    expect(formatRelativeTime(new Date('2024-06-15T12:05:00Z'))).toBe('in 5m');
    expect(formatRelativeTime(new Date('2024-06-15T14:00:00Z'))).toBe('in 2h');
  });
});

describe('formatNumber', () => {
  it('adds thousands separators', () => {
    expect(formatNumber(1234567)).toBe('1,234,567');
    expect(formatNumber(0)).toBe('0');
  });
});

describe('formatPercent', () => {
  it('formats a decimal as a percentage with default 1 decimal', () => {
    expect(formatPercent(0.15)).toBe('15.0%');
    expect(formatPercent(1)).toBe('100.0%');
  });

  it('honors the decimals argument', () => {
    expect(formatPercent(0.15, 0)).toBe('15%');
  });
});

describe('formatFileSize', () => {
  it('formats bytes with no decimals and rolls over units', () => {
    expect(formatFileSize(0)).toBe('0 B');
    expect(formatFileSize(512)).toBe('512 B');
    expect(formatFileSize(1024)).toBe('1.0 KB');
    expect(formatFileSize(1536)).toBe('1.5 KB');
    expect(formatFileSize(1024 * 1024)).toBe('1.0 MB');
    expect(formatFileSize(1024 ** 3)).toBe('1.0 GB');
    expect(formatFileSize(1024 ** 4)).toBe('1.0 TB');
  });
});

describe('capitalize', () => {
  it('uppercases the first character only', () => {
    expect(capitalize('hello')).toBe('Hello');
    expect(capitalize('Hello')).toBe('Hello');
    expect(capitalize('')).toBe('');
  });
});

describe('truncate', () => {
  it('leaves short strings untouched', () => {
    expect(truncate('hi', 8)).toBe('hi');
  });

  it('truncates with an ellipsis (slice maxLength-3 + ...)', () => {
    expect(truncate('hello world', 8)).toBe('hello...');
  });
});

describe('masked display helpers', () => {
  it('formats card and bank displays', () => {
    expect(formatCardDisplay('1234', 'visa')).toBe('VISA **** 1234');
    expect(formatCardDisplay('1234')).toBe('Card **** 1234');
    expect(formatBankAccountDisplay('5678')).toBe('Bank **** 5678');
  });
});

describe('normalizePriceCents', () => {
  it('normalizes numbers, price objects, and nullish/NaN to cents', () => {
    expect(normalizePriceCents(1000)).toBe(1000);
    expect(normalizePriceCents({ cents: 500 })).toBe(500);
    expect(normalizePriceCents(null)).toBe(0);
    expect(normalizePriceCents(undefined)).toBe(0);
    expect(normalizePriceCents(NaN)).toBe(0);
  });
});

describe('getBillingCycleLabel', () => {
  it('maps cycles to display labels', () => {
    expect(getBillingCycleLabel('yearly')).toBe('year');
    expect(getBillingCycleLabel('quarterly')).toBe('quarter');
    expect(getBillingCycleLabel('monthly')).toBe('month');
    expect(getBillingCycleLabel('anything-else')).toBe('month');
  });
});

describe('formatSubscriptionPrice', () => {
  it("returns 'Free' when the price is zero", () => {
    expect(formatSubscriptionPrice(0, 'monthly')).toBe('Free');
  });

  it('formats a price with its billing cycle', () => {
    expect(formatSubscriptionPrice(1000, 'monthly')).toBe('$10.00/month');
    expect(formatSubscriptionPrice({ cents: 12000, currency_iso: 'USD' }, 'yearly')).toBe('$120.00/year');
  });
});

describe('calculateDiscountedPrice', () => {
  it('applies the default 10% annual discount for yearly view of a monthly plan', () => {
    const r = calculateDiscountedPrice(1000, { billing_cycle: 'monthly' }, 'yearly');
    expect(r.originalPriceCents).toBe(12000);
    expect(r.discountedPriceCents).toBe(10800);
    expect(r.discountPercent).toBe(10);
    expect(r.discountType).toBe('annual');
    expect(r.hasDiscount).toBe(true);
    expect(r.formattedOriginal).toBe('$120.00/year');
    expect(r.formattedDiscounted).toBe('$108.00/year');
  });

  it('applies an explicit annual discount percent when configured', () => {
    const r = calculateDiscountedPrice(
      1000,
      { billing_cycle: 'monthly', has_annual_discount: true, annual_discount_percent: 20 },
      'yearly'
    );
    expect(r.discountedPriceCents).toBe(9600);
    expect(r.discountPercent).toBe(20);
  });

  it('reports no discount for a plain monthly view', () => {
    const r = calculateDiscountedPrice(1000, { billing_cycle: 'monthly' }, 'monthly');
    expect(r.hasDiscount).toBe(false);
    expect(r.discountType).toBeNull();
    expect(r.originalPriceCents).toBe(1000);
    expect(r.discountedPriceCents).toBe(1000);
  });
});

describe('calculateAnnualSavings', () => {
  it('computes savings vs 12x monthly with percent rounding', () => {
    const r = calculateAnnualSavings(1000, 10800);
    expect(r.savingsCents).toBe(1200);
    expect(r.savingsPercent).toBe(10);
    expect(r.formattedSavings).toBe('$12.00');
  });

  it('guards against divide-by-zero', () => {
    const r = calculateAnnualSavings(0, 0);
    expect(r.savingsPercent).toBe(0);
    expect(r.savingsCents).toBe(0);
  });
});

describe('isPromotionalDiscountActive', () => {
  beforeEach(() => {
    jest.useFakeTimers();
    jest.setSystemTime(new Date('2024-06-15T12:00:00Z'));
  });
  afterEach(() => {
    jest.useRealTimers();
  });

  it('is false without a promotional discount configured', () => {
    expect(isPromotionalDiscountActive({})).toBe(false);
    expect(isPromotionalDiscountActive({ has_promotional_discount: true })).toBe(false);
  });

  it('is active within the date window (or with no dates)', () => {
    expect(
      isPromotionalDiscountActive({ has_promotional_discount: true, promotional_discount_percent: 25 })
    ).toBe(true);
    expect(
      isPromotionalDiscountActive({
        has_promotional_discount: true,
        promotional_discount_percent: 25,
        promotional_discount_start: '2024-06-01T00:00:00Z',
        promotional_discount_end: '2024-06-30T00:00:00Z',
      })
    ).toBe(true);
  });

  it('is inactive when the window has ended', () => {
    expect(
      isPromotionalDiscountActive({
        has_promotional_discount: true,
        promotional_discount_percent: 25,
        promotional_discount_end: '2024-06-10T00:00:00Z',
      })
    ).toBe(false);
  });
});
