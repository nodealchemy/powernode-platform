/**
 * Formatting utility functions
 *
 * Centralized formatting functions extracted from API services.
 * Use these functions instead of the utilities on individual API objects.
 */

/**
 * Formats an amount in cents to a currency string
 *
 * @param amountCents - Amount in cents (e.g., 1000 = $10.00)
 * @param currency - ISO 4217 currency code (default: 'USD')
 * @returns Formatted currency string (e.g., '$10.00')
 *
 * @example
 * formatCurrency(1000) // '$10.00'
 * formatCurrency(1000, 'EUR') // '10,00 EUR'
 * formatCurrency(null) // '$0.00'
 */
export function formatCurrency(
  amountCents: number | string | undefined | null,
  currency = 'USD'
): string {
  if (amountCents === undefined || amountCents === null) {
    return '$0.00';
  }

  const amount = typeof amountCents === 'string'
    ? parseInt(amountCents, 10) || 0
    : amountCents;

  if (isNaN(amount)) {
    return '$0.00';
  }

  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: currency.toUpperCase(),
  }).format(amount / 100);
}

/**
 * Formats a date string to a localized short date
 *
 * @param dateString - ISO date string
 * @returns Formatted date (e.g., 'Jan 15, 2024')
 *
 * @example
 * formatDate('2024-01-15') // 'Jan 15, 2024'
 */
export function formatDate(dateString: string | Date | null | undefined): string {
  if (!dateString) return '—';
  const date = typeof dateString === 'string' ? new Date(dateString) : dateString;

  return date.toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
}

/**
 * Formats a date string to a full localized date with time
 *
 * @param dateString - ISO date string
 * @returns Formatted datetime (e.g., 'Jan 15, 2024, 2:30 PM')
 */
export function formatDateTime(dateString: string | Date | null | undefined): string {
  if (!dateString) return '—';
  const date = typeof dateString === 'string' ? new Date(dateString) : dateString;

  return date.toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
}

/**
 * Formats an instant as a full timestamp in the VIEWER'S locale, seconds
 * included.
 *
 * Distinct from formatDateTime on purpose, and the difference is the point:
 * formatDateTime is the readable en-US display form ('Jan 15, 2024, 2:30 PM')
 * for a date a person reads once, while this is the operational form
 * ('1/15/2024, 2:30:07 PM') for screens where two events a few seconds apart
 * must not print the same string. Reach for this on task, event and log
 * surfaces; reach for formatDateTime on detail panes.
 *
 * Consolidated from copies in the system extension's operations screens
 * (IMP-c11d5ad755b8), which is why it keeps toLocaleString's exact output
 * rather than adopting the en-US shape.
 *
 * @param value - ISO date string or Date; null/undefined yields an em dash
 * @returns Locale timestamp with seconds, or '—'
 */
export function formatTimestamp(value: string | Date | null | undefined): string {
  if (!value) return '—';
  return (typeof value === 'string' ? new Date(value) : value).toLocaleString();
}

/**
 * Minute/hour/day tier arithmetic shared by {@link formatRelativeTime} and
 * {@link formatRelativeTimeCompact} (IMP-01a082a3, review F3) — both derive
 * the same floor(ms/60000) → floor(minutes/60) → floor(hours/24) ladder from
 * an elapsed-millisecond diff before applying their own thresholds, labels,
 * and tail behavior (future dates, absolute fallback, 'Never'/empty states),
 * which stay in each function. `diffMs` must be >= 0 (pass an absolute value
 * for a future-dated diff).
 */
function relativeTimeTiers(diffMs: number): { minutes: number; hours: number; days: number } {
  const minutes = Math.floor(diffMs / 60000);
  const hours = Math.floor(minutes / 60);
  const days = Math.floor(hours / 24);
  return { minutes, hours, days };
}

/**
 * Formats a date string to relative time (e.g., '5 minutes ago')
 *
 * @param dateString - ISO date string or null
 * @returns Relative time string or 'Never' if null
 *
 * @example
 * formatRelativeTime('2024-01-15T10:00:00Z') // '2h ago'
 * formatRelativeTime(null) // 'Never'
 */
export function formatRelativeTime(dateString: string | Date | null): string {
  if (!dateString) return 'Never';

  const date = typeof dateString === 'string' ? new Date(dateString) : dateString;
  const now = new Date();
  const diffInSeconds = Math.floor((now.getTime() - date.getTime()) / 1000);

  if (diffInSeconds < 0) {
    // Future date
    const absDiff = Math.abs(diffInSeconds);
    const { minutes, hours, days } = relativeTimeTiers(absDiff * 1000);
    if (absDiff < 60) return 'in a few seconds';
    if (hours < 1) return `in ${minutes}m`;
    if (days < 1) return `in ${hours}h`;
    if (days < 7) return `in ${days}d`;
    return formatDate(date);
  }

  const { minutes, hours, days } = relativeTimeTiers(diffInSeconds * 1000);
  if (diffInSeconds < 60) return 'Just now';
  if (hours < 1) return `${minutes}m ago`;
  if (days < 1) return `${hours}h ago`;
  if (days < 7) return `${days}d ago`;

  return formatDate(date);
}

/** Options for {@link formatRelativeTimeCompact}. */
export interface FormatRelativeTimeCompactOptions {
  /** String returned when `dateStr` is falsy. Default ''. */
  emptyValue?: string;
  /** Label for "less than a minute ago". Default 'just now' (lowercase —
   *  distinct from {@link formatRelativeTime}'s capitalized 'Just now'). */
  justNowLabel?: string;
  /** Once the day count reaches 30, switch to a `Xmo ago` month label
   *  instead of continuing to count unbounded days. Default false. */
  monthTier?: boolean;
  /** Once elapsed time reaches this many milliseconds, fall back to
   *  `new Date(dateStr).toLocaleDateString()` instead of day-counting.
   *  Unset (default) means never fall back — days grow unbounded. */
  absoluteFallbackAfterMs?: number;
}

/**
 * Formats a timestamp as a compact "list item" relative-time label —
 * distinct from {@link formatRelativeTime}, which additionally handles
 * future dates, a 'Never' empty state, and a >7-day fallback to an absolute
 * date. Consolidates ~10 near-identical local copies (IMP-01a082a3) used on
 * list rows (agent history, missions, ralph loops, etc.) where those extra
 * behaviors were never implemented and the lowercase 'just now' label is the
 * house style. Options reproduce each site's exact prior output — see
 * {@link FormatRelativeTimeCompactOptions}.
 *
 * @example
 * formatRelativeTimeCompact('2024-01-15T10:00:00Z') // '2h ago'
 * formatRelativeTimeCompact(null) // ''
 */
export function formatRelativeTimeCompact(
  dateStr: string | Date | null | undefined,
  options: FormatRelativeTimeCompactOptions = {}
): string {
  const { emptyValue = '', justNowLabel = 'just now', monthTier = false, absoluteFallbackAfterMs } = options;
  if (!dateStr) return emptyValue;

  const date = typeof dateStr === 'string' ? new Date(dateStr) : dateStr;
  const diff = Date.now() - date.getTime();

  if (absoluteFallbackAfterMs !== undefined) {
    if (diff < 60000) return justNowLabel;
    if (diff < 3600000) return `${Math.floor(diff / 60000)}m ago`;
    if (diff < absoluteFallbackAfterMs) return `${Math.floor(diff / 3600000)}h ago`;
    return date.toLocaleDateString();
  }

  const { minutes, hours, days } = relativeTimeTiers(diff);
  if (minutes < 1) return justNowLabel;
  if (hours < 1) return `${minutes}m ago`;
  if (days < 1) return `${hours}h ago`;
  if (monthTier && days >= 30) {
    return `${Math.floor(days / 30)}mo ago`;
  }
  return `${days}d ago`;
}

/**
 * Formats elapsed time between two instants as a compact duration.
 *
 * Consolidated from two component copies that differed only in whether a
 * sub-minute run read '45s' or '45 seconds' (IMP-c11d5ad755b8). The compact
 * form wins because the other branches were already compact — the long copy
 * rendered '45 seconds' and then '1m 30s' from the same function.
 *
 * @param startedAt - when the work began; null/undefined yields an em dash
 * @param completedAt - when it finished; omit or pass null for work still
 *   running, which measures against now
 * @returns '45s', '5m 30s', '2h 15m', or '—' when there is nothing to measure
 *
 * @example
 * formatDuration('2024-01-15T10:00:00Z', '2024-01-15T10:05:30Z') // '5m 30s'
 * formatDuration(null) // '—'
 */
export function formatDuration(
  startedAt: string | Date | null | undefined,
  completedAt?: string | Date | null
): string {
  if (!startedAt) return '—';

  const start = (typeof startedAt === 'string' ? new Date(startedAt) : startedAt).getTime();
  const end = completedAt
    ? (typeof completedAt === 'string' ? new Date(completedAt) : completedAt).getTime()
    : Date.now();

  const seconds = Math.floor((end - start) / 1000);
  // An unparseable timestamp gives NaN, which fails both range tests below and
  // would fall through to the hours branch as 'NaNh NaNm'. The copies this
  // replaced did exactly that; an em dash is what the rest of this module says
  // for a value it cannot use.
  if (!Number.isFinite(seconds)) return '—';

  if (seconds < 60) return `${seconds}s`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ${seconds % 60}s`;
  return `${Math.floor(seconds / 3600)}h ${Math.floor((seconds % 3600) / 60)}m`;
}

/**
 * Options for {@link formatDurationMs}. Each axis maps to a real difference
 * found across the ~12 local copies this consolidates (IMP-01a082a3) — none
 * are hypothetical, and every default reproduces the most common shape
 * (agentConstants.ts / AgentDetailStatsCards.tsx) so `formatDurationMs(ms)`
 * with no options matches those two call sites exactly.
 */
interface FormatDurationMsCommonOptions {
  /** String returned when the value is considered empty. Default '—'. */
  emptyValue?: string;
  /**
   * How emptiness is detected: 'falsy' treats 0 (and NaN) as empty — matches
   * sites that guarded with `!ms`; 'nullish' only null/undefined are empty (0
   * still renders as '0ms'); 'none' skips the guard entirely. Default
   * 'nullish'.
   */
  emptyCheck?: 'falsy' | 'nullish' | 'none';
  /** Sub-1000ms rendering: 'round' applies Math.round, 'raw' prints the
   *  millisecond value unrounded. Default 'round'. */
  subSecond?: 'round' | 'raw';
  /**
   * Whether a value under 1000ms gets the raw/rounded `Xms` sub-second
   * shortcut before any tiering runs. Every mode defaults this to true
   * EXCEPT 'floor-integer', which defaults to false — most floor-integer
   * sites floor straight to whole seconds with no millisecond display (a
   * sub-second value renders '0s'), but at least one still wants the
   * shortcut, so it's a real, independent axis rather than being implied by
   * `tiering`.
   */
  subSecondTier?: boolean;
}

/**
 * Options for {@link formatDurationMs}, discriminated on `tiering` so a flag
 * that only applies to one mode (e.g. `roundRemainderSeconds`) is a type
 * error under any other mode instead of a silent no-op (IMP-01a082a3, review
 * F2). Each axis maps to a real difference found across the ~12 local copies
 * this consolidates — none are hypothetical, and every default reproduces
 * the most common shape (agentConstants.ts / AgentDetailStatsCards.tsx) so
 * `formatDurationMs(ms)` with no options matches those two call sites
 * exactly.
 */
export type FormatDurationMsOptions = FormatDurationMsCommonOptions &
  (
    | {
        /** Keep rendering decimal seconds forever, no minute tier. Default
         *  tiering when omitted. */
        tiering?: 'decimal-seconds-only';
        /** Decimal places for the seconds display. Default 1. */
        decimals?: number;
      }
    | {
        /** Switch to seconds below 60s, then minutes (decimal or integer
         *  per `integerMinutes`) — optionally escalating to decimal hours
         *  past 60 minutes when `decimalHourTier` is set. */
        tiering: 'decimal-minutes';
        /** Decimal places for the seconds/minutes/hours display. Default 1. */
        decimals?: number;
        /** Render the minute tier as a whole number instead of one decimal
         *  place. Default false. */
        integerMinutes?: boolean;
        /** Escalate to a decimal-hours display past 60 minutes instead of
         *  showing minutes indefinitely. Default false. */
        decimalHourTier?: boolean;
      }
    | {
        /** Floor (or round, per `roundSeconds`) straight to whole seconds
         *  with no decimal display at any tier, then integer minute/hour
         *  tiering per `minuteTier`/`hourTier`. */
        tiering: 'floor-integer';
        /** 'minutes-seconds' renders `Xm Ys`, 'minutes-only' renders `Xm`
         *  with no seconds remainder. Default 'minutes-seconds'. */
        minuteTier?: 'minutes-only' | 'minutes-seconds';
        /** Round (vs. floor) the initial seconds-from-ms conversion before
         *  tiering. Default false (floor). */
        roundSeconds?: boolean;
        /** Whether minutes escalate to an `Xh Ym` tier past 60 minutes.
         *  false leaves minutes unbounded (e.g. '90m 0s'). Default true. */
        hourTier?: boolean;
      }
    | {
        /** Decimal seconds below 60s (like 'decimal-minutes'), then integer
         *  `Xm Ys` minutes above it with no hour tier — minutes grow
         *  unbounded (e.g. '90m 0s'). */
        tiering: 'decimal-seconds-then-floor-minutes';
        /** Decimal places for the sub-60s seconds display. Default 1. */
        decimals?: number;
        /** The seconds remainder in the `Xm Ys` minute tier is
         *  `Math.round((ms % 60000) / 1000)` instead of
         *  `Math.floor(ms / 1000) % 60`. These genuinely differ (e.g.
         *  125678ms: floored remainder is 5s, rounded remainder is 6s) —
         *  real sites used the rounded form. Default false (floor). */
        roundRemainderSeconds?: boolean;
      }
  );

/**
 * Formats an already-known millisecond duration (e.g. `execution.duration_ms`,
 * `span.duration_ms`) directly — as opposed to {@link formatDuration}, which
 * takes two instants and computes the elapsed time between them. These are
 * genuinely different contracts (a scalar duration vs. a pair of timestamps),
 * which is why this is a separate function rather than an overload.
 *
 * Consolidates ~12 near-identical local copies (IMP-01a082a3) that differed
 * in real, load-bearing ways — see {@link FormatDurationMsOptions}. Pass
 * options to reproduce a specific site's exact prior output; the no-options
 * default matches the most common shape.
 *
 * @example
 * formatDurationMs(450) // '450ms'
 * formatDurationMs(45000) // '45.0s'
 * formatDurationMs(null) // '—'
 */
export function formatDurationMs(
  ms: number | null | undefined,
  options: FormatDurationMsOptions = {}
): string {
  const { emptyValue = '—', emptyCheck = 'nullish', subSecond = 'round' } = options;

  const isEmpty =
    emptyCheck === 'none'
      ? false
      : emptyCheck === 'falsy'
        ? !ms || (typeof ms === 'number' && isNaN(ms))
        : ms === null || ms === undefined;
  if (isEmpty) return emptyValue;

  const value = ms as number;

  const subSecondTier = options.subSecondTier ?? options.tiering !== 'floor-integer';

  if (subSecondTier && value < 1000) {
    const shown = subSecond === 'round' ? Math.round(value) : value;
    return `${shown}ms`;
  }

  if (options.tiering === 'floor-integer') {
    const { minuteTier = 'minutes-seconds', roundSeconds = false, hourTier = true } = options;
    const seconds = roundSeconds ? Math.round(value / 1000) : Math.floor(value / 1000);
    if (seconds < 60) return `${seconds}s`;
    const minutes = Math.floor(seconds / 60);
    if (minuteTier === 'minutes-only') {
      if (!hourTier || minutes < 60) return `${minutes}m`;
      const hours = Math.floor(minutes / 60);
      return `${hours}h ${minutes % 60}m`;
    }
    if (!hourTier || minutes < 60) return `${minutes}m ${seconds % 60}s`;
    const hours = Math.floor(minutes / 60);
    return `${hours}h ${minutes % 60}m`;
  }

  if (options.tiering === 'decimal-seconds-then-floor-minutes') {
    const { decimals = 1, roundRemainderSeconds = false } = options;
    if (value < 60000) return `${(value / 1000).toFixed(decimals)}s`;
    const minutes = Math.floor(value / 60000);
    const remainderSeconds = roundRemainderSeconds
      ? Math.round((value % 60000) / 1000)
      : Math.floor(value / 1000) % 60;
    return `${minutes}m ${remainderSeconds}s`;
  }

  if (options.tiering === 'decimal-minutes') {
    const { decimals = 1, integerMinutes = false, decimalHourTier = false } = options;
    if (value < 60000) {
      return `${(value / 1000).toFixed(decimals)}s`;
    }
    if (decimalHourTier && value >= 3600000) {
      return `${(value / 3600000).toFixed(decimals)}h`;
    }
    return integerMinutes
      ? `${Math.floor(value / 60000)}m`
      : `${(value / 60000).toFixed(decimals)}m`;
  }

  // options.tiering === 'decimal-seconds-only' or undefined (default)
  const { decimals = 1 } = options;
  return `${(value / 1000).toFixed(decimals)}s`;
}

/**
 * Formats a number with thousands separators
 *
 * @param value - Number to format
 * @returns Formatted number string (e.g., '1,234,567')
 */
export function formatNumber(value: number): string {
  return new Intl.NumberFormat('en-US').format(value);
}

/**
 * Formats a number as a percentage
 *
 * @param value - Decimal value (e.g., 0.15 for 15%)
 * @param decimals - Number of decimal places (default: 1)
 * @returns Formatted percentage string (e.g., '15.0%')
 */
export function formatPercent(value: number, decimals = 1): string {
  return new Intl.NumberFormat('en-US', {
    style: 'percent',
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  }).format(value);
}

/** Options for {@link formatFileSize}. */
export interface FormatFileSizeOptions {
  /** String returned when `bytes` is <= 0. Unset (default): 0/negative
   *  values fall through the normal ladder ('0 B', or a raw negative
   *  number for a negative input, matching every pre-existing caller). */
  nonPositiveValue?: string;
  /** Cap the unit ladder at MB instead of continuing to GB/TB/PB — matches
   *  sites that never expected multi-gigabyte values. Unset (default): the
   *  full 'B'..'PB' ladder, matching every pre-existing caller. */
  capAtMB?: boolean;
  /** Cap the unit ladder at GB instead of continuing to TB/PB (IMP-01a082a3).
   *  Mutually exclusive with `capAtMB` — pass at most one. */
  capAtGB?: boolean;
  /** Decimal places for the non-'B' units. Either one number applied to
   *  every unit, or a per-unit override (e.g. `{ MB: 2 }` leaves KB at the
   *  default of 1). Default 1 for every unit — matches every pre-existing
   *  caller. Ignored when `autoTrimDecimals` is set. */
  decimals?: number | Partial<Record<'KB' | 'MB' | 'GB' | 'TB' | 'PB', number>>;
  /**
   * When set, non-'B' units render as `parseFloat(size.toFixed(n))` (trailing
   * zeros stripped — `2048 bytes` becomes `'2 KB'`, not `'2.0 KB'`) instead of
   * the fixed-decimal `size.toFixed(n)` `decimals` normally produces. Two
   * real sites used `parseFloat(x.toFixed(n))` this way (IMP-01a082a3); unset
   * (default) keeps the fixed-decimal behavior every other caller expects.
   */
  autoTrimDecimals?: number;
  /** Label for the smallest unit (< 1024 bytes). Default 'B'. One real site
   *  used the word 'Bytes' instead (IMP-01a082a3). */
  byteUnitLabel?: string;
}

/**
 * Formats bytes to human-readable size
 *
 * @param bytes - Size in bytes
 * @param options - see {@link FormatFileSizeOptions}; the no-options default
 *   reproduces this function's original behavior exactly (all pre-existing
 *   callers pass no options and are unaffected).
 * @returns Formatted size string (e.g., '1.5 MB')
 */
export function formatFileSize(bytes: number, options: FormatFileSizeOptions = {}): string {
  const {
    nonPositiveValue,
    capAtMB = false,
    capAtGB = false,
    decimals = 1,
    autoTrimDecimals,
    byteUnitLabel = 'B',
  } = options;

  if (nonPositiveValue !== undefined && bytes <= 0) return nonPositiveValue;

  // PB tops the ladder because WireGuard peer counters reach it: the system
  // extension's peer list carried its own PB-capable formatter, and adopting
  // this one without PB would render a petabyte as '1024.0 TB'
  // (IMP-c11d5ad755b8). `capAtMB`/`capAtGB` opt specific sites back out when
  // they never expected — or rendered — anything past that unit (IMP-01a082a3).
  const units = capAtMB
    ? ([byteUnitLabel, 'KB', 'MB'] as const)
    : capAtGB
      ? ([byteUnitLabel, 'KB', 'MB', 'GB'] as const)
      : ([byteUnitLabel, 'KB', 'MB', 'GB', 'TB', 'PB'] as const);
  let size = bytes;
  let unitIndex = 0;

  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }

  const unit = units[unitIndex];

  if (unitIndex === 0) {
    return `${size.toFixed(0)} ${unit}`;
  }

  if (autoTrimDecimals !== undefined) {
    return `${parseFloat(size.toFixed(autoTrimDecimals))} ${unit}`;
  }

  const unitDecimals =
    typeof decimals === 'number' ? decimals : (decimals[unit as 'KB' | 'MB' | 'GB' | 'TB' | 'PB'] ?? 1);

  return `${size.toFixed(unitDecimals)} ${unit}`;
}

/**
 * Nullable-accepting wrapper around {@link formatFileSize}. `formatFileSize`
 * itself keeps a strict `bytes: number` signature on purpose — the system
 * extension's `PeerList.tsx` traffic counter depends on that compile-time
 * guard to avoid silently rendering a missing counter as '0 B'
 * (IMP-01a082a3, review F1). Callers that genuinely have an optional byte
 * count and want a placeholder string for it should call this instead.
 *
 * @param bytes - Size in bytes, or null/undefined for an absent value
 * @param emptyValue - String returned when `bytes` is null/undefined
 * @param options - see {@link FormatFileSizeOptions}, forwarded to `formatFileSize`
 */
export function formatFileSizeOrEmpty(
  bytes: number | null | undefined,
  emptyValue: string,
  options: FormatFileSizeOptions = {}
): string {
  if (bytes === null || bytes === undefined) return emptyValue;
  return formatFileSize(bytes, options);
}

/**
 * Capitalizes the first letter of a string
 *
 * @param str - String to capitalize
 * @returns Capitalized string
 */
export function capitalize(str: string): string {
  if (!str) return '';
  return str.charAt(0).toUpperCase() + str.slice(1);
}

/**
 * Truncates a string to a maximum length with ellipsis
 *
 * @param str - String to truncate
 * @param maxLength - Maximum length
 * @returns Truncated string with ellipsis if needed
 */
export function truncate(str: string, maxLength: number): string {
  if (!str || str.length <= maxLength) return str;
  return `${str.slice(0, maxLength - 3)}...`;
}

/**
 * Formats a credit card number with masked digits
 *
 * @param lastFour - Last 4 digits of card
 * @param brand - Card brand (e.g., 'visa', 'mastercard')
 * @returns Formatted card display (e.g., 'VISA **** 1234')
 */
export function formatCardDisplay(lastFour: string, brand?: string): string {
  const brandDisplay = brand ? brand.toUpperCase() : 'Card';
  return `${brandDisplay} **** ${lastFour}`;
}

/**
 * Formats a bank account number with masked digits
 *
 * @param lastFour - Last 4 digits of account
 * @returns Formatted account display (e.g., 'Bank **** 1234')
 */
export function formatBankAccountDisplay(lastFour: string): string {
  return `Bank **** ${lastFour}`;
}

// ============================================
// Subscription & Plan Price Formatting
// ============================================

export interface PriceInput {
  cents: number;
  currency_iso?: string;
}

export interface PlanDiscountInfo {
  billing_cycle?: string;
  has_annual_discount?: boolean;
  annual_discount_percent?: number | string;
  has_promotional_discount?: boolean;
  promotional_discount_percent?: number | string;
  promotional_discount_code?: string;
  promotional_discount_start?: string;
  promotional_discount_end?: string;
}

export type BillingCycle = 'monthly' | 'yearly' | 'quarterly';

/**
 * Formats subscription price with billing cycle
 *
 * @param price - Price in cents or price object
 * @param billingCycle - The billing cycle (monthly, yearly, quarterly)
 * @param currency - ISO 4217 currency code (default: 'USD')
 * @returns Formatted price string (e.g., '$10.00/month')
 *
 * @example
 * formatSubscriptionPrice(1000, 'monthly') // '$10.00/month'
 * formatSubscriptionPrice({ cents: 12000, currency_iso: 'USD' }, 'yearly') // '$120.00/year'
 * formatSubscriptionPrice(0, 'monthly') // 'Free'
 */
export function formatSubscriptionPrice(
  price: number | PriceInput | null | undefined,
  billingCycle: BillingCycle = 'monthly',
  currency = 'USD'
): string {
  const priceCents = normalizePriceCents(price);
  const actualCurrency = typeof price === 'object' && price?.currency_iso ? price.currency_iso : currency;

  if (priceCents === 0) {
    return 'Free';
  }

  const formattedAmount = formatCurrency(priceCents, actualCurrency);
  const cycleLabel = getBillingCycleLabel(billingCycle);

  return `${formattedAmount}/${cycleLabel}`;
}

/**
 * Calculates and formats a discounted price
 *
 * @param priceCents - Base price in cents
 * @param discountInfo - Plan discount information
 * @param displayBillingCycle - The billing cycle being displayed (may differ from plan cycle)
 * @param currency - ISO 4217 currency code
 * @returns Object with formatted prices and discount info
 */
export function calculateDiscountedPrice(
  priceCents: number,
  discountInfo: PlanDiscountInfo,
  displayBillingCycle: BillingCycle = 'monthly',
  currency = 'USD'
): {
  originalPriceCents: number;
  discountedPriceCents: number;
  discountPercent: number;
  formattedOriginal: string;
  formattedDiscounted: string;
  hasDiscount: boolean;
  discountType: 'annual' | 'promotional' | null;
} {
  let discountedPriceCents = priceCents;
  let discountPercent = 0;
  let discountType: 'annual' | 'promotional' | null = null;
  let originalPriceCents = priceCents;

  // Apply annual pricing when viewing yearly billing for monthly plans
  if (
    displayBillingCycle === 'yearly' &&
    discountInfo.billing_cycle === 'monthly'
  ) {
    originalPriceCents = priceCents * 12;

    // Apply explicit annual discount if configured
    if (discountInfo.has_annual_discount && discountInfo.annual_discount_percent) {
      const annualDiscountPercent = parseFloat(String(discountInfo.annual_discount_percent));
      discountedPriceCents = Math.round(originalPriceCents * (1 - annualDiscountPercent / 100));
      discountPercent = annualDiscountPercent;
      discountType = 'annual';
    } else {
      // Apply default 10% annual discount for yearly billing view
      const defaultAnnualDiscount = 10;
      discountedPriceCents = Math.round(originalPriceCents * (1 - defaultAnnualDiscount / 100));
      discountPercent = defaultAnnualDiscount;
      discountType = 'annual';
    }
  }
  // Apply promotional discount (only if no code required)
  else if (
    discountInfo.has_promotional_discount &&
    discountInfo.promotional_discount_percent &&
    !discountInfo.promotional_discount_code &&
    isPromotionalDiscountActive(discountInfo)
  ) {
    const promoDiscountPercent = parseFloat(String(discountInfo.promotional_discount_percent));
    discountedPriceCents = Math.round(priceCents * (1 - promoDiscountPercent / 100));
    discountPercent = promoDiscountPercent;
    discountType = 'promotional';
  }

  const cycleLabel = getBillingCycleLabel(displayBillingCycle);

  return {
    originalPriceCents,
    discountedPriceCents,
    discountPercent,
    formattedOriginal: `${formatCurrency(originalPriceCents, currency)}/${cycleLabel}`,
    formattedDiscounted: `${formatCurrency(discountedPriceCents, currency)}/${cycleLabel}`,
    hasDiscount: discountType !== null,
    discountType,
  };
}

/**
 * Calculates savings amount and percentage for yearly billing
 *
 * @param monthlyPriceCents - Monthly price in cents
 * @param yearlyPriceCents - Yearly price in cents (already discounted)
 * @returns Savings info
 */
export function calculateAnnualSavings(
  monthlyPriceCents: number,
  yearlyPriceCents: number
): {
  savingsCents: number;
  savingsPercent: number;
  formattedSavings: string;
} {
  const fullYearlyPrice = monthlyPriceCents * 12;
  const savingsCents = fullYearlyPrice - yearlyPriceCents;
  const savingsPercent = fullYearlyPrice > 0 ? Math.round((savingsCents / fullYearlyPrice) * 100) : 0;

  return {
    savingsCents,
    savingsPercent,
    formattedSavings: formatCurrency(savingsCents),
  };
}

// ============================================
// Helper Functions
// ============================================

/**
 * Normalizes various price input formats to cents
 */
export function normalizePriceCents(
  price: number | PriceInput | null | undefined
): number {
  if (price == null) return 0;
  if (typeof price === 'object' && 'cents' in price) {
    return price.cents ?? 0;
  }
  if (typeof price === 'number') {
    return isNaN(price) ? 0 : price;
  }
  return 0;
}

/**
 * Gets the display label for a billing cycle
 */
export function getBillingCycleLabel(cycle: BillingCycle | string): string {
  switch (cycle) {
    case 'yearly':
    case 'year':
      return 'year';
    case 'quarterly':
    case 'quarter':
      return 'quarter';
    case 'monthly':
    case 'month':
    default:
      return 'month';
  }
}

/**
 * Checks if a promotional discount is currently active
 */
export function isPromotionalDiscountActive(discountInfo: PlanDiscountInfo): boolean {
  if (!discountInfo.has_promotional_discount || !discountInfo.promotional_discount_percent) {
    return false;
  }

  const now = new Date();
  const startDate = discountInfo.promotional_discount_start
    ? new Date(discountInfo.promotional_discount_start)
    : null;
  const endDate = discountInfo.promotional_discount_end
    ? new Date(discountInfo.promotional_discount_end)
    : null;

  const hasStarted = !startDate || startDate <= now;
  const hasNotEnded = !endDate || endDate >= now;

  return hasStarted && hasNotEnded;
}
