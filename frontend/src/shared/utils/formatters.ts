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
export function formatDate(dateString: string | Date): string {
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
export function formatDateTime(dateString: string | Date): string {
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
    if (absDiff < 60) return 'in a few seconds';
    if (absDiff < 3600) return `in ${Math.floor(absDiff / 60)}m`;
    if (absDiff < 86400) return `in ${Math.floor(absDiff / 3600)}h`;
    if (absDiff < 604800) return `in ${Math.floor(absDiff / 86400)}d`;
    return formatDate(date);
  }

  if (diffInSeconds < 60) return 'Just now';
  if (diffInSeconds < 3600) return `${Math.floor(diffInSeconds / 60)}m ago`;
  if (diffInSeconds < 86400) return `${Math.floor(diffInSeconds / 3600)}h ago`;
  if (diffInSeconds < 604800) return `${Math.floor(diffInSeconds / 86400)}d ago`;

  return formatDate(date);
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

/**
 * Formats bytes to human-readable size
 *
 * @param bytes - Size in bytes
 * @returns Formatted size string (e.g., '1.5 MB')
 */
export function formatFileSize(bytes: number): string {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let size = bytes;
  let unitIndex = 0;

  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }

  return `${size.toFixed(unitIndex === 0 ? 0 : 1)} ${units[unitIndex]}`;
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
 * Converts snake_case or kebab-case to Title Case
 *
 * @param str - String to convert
 * @returns Title case string
 *
 * @example
 * toTitleCase('hello_world') // 'Hello World'
 * toTitleCase('hello-world') // 'Hello World'
 */
export function toTitleCase(str: string): string {
  return str
    .replace(/[-_]/g, ' ')
    .split(' ')
    .map(word => capitalize(word))
    .join(' ');
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
 * Formats a phone number to standard US format
 *
 * @param phone - Phone number string
 * @returns Formatted phone number (e.g., '(555) 123-4567')
 */
export function formatPhoneNumber(phone: string): string {
  const cleaned = phone.replace(/\D/g, '');

  if (cleaned.length === 10) {
    return `(${cleaned.slice(0, 3)}) ${cleaned.slice(3, 6)}-${cleaned.slice(6)}`;
  }
  if (cleaned.length === 11 && cleaned.startsWith('1')) {
    return `+1 (${cleaned.slice(1, 4)}) ${cleaned.slice(4, 7)}-${cleaned.slice(7)}`;
  }

  return phone;
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

  // Apply annual discount when viewing yearly billing for monthly plans
  if (
    displayBillingCycle === 'yearly' &&
    discountInfo.billing_cycle === 'monthly' &&
    discountInfo.has_annual_discount &&
    discountInfo.annual_discount_percent
  ) {
    const annualDiscountPercent = parseFloat(String(discountInfo.annual_discount_percent));
    originalPriceCents = priceCents * 12;
    discountedPriceCents = Math.round(originalPriceCents * (1 - annualDiscountPercent / 100));
    discountPercent = annualDiscountPercent;
    discountType = 'annual';
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
 * Calculates yearly price from monthly price with optional discount
 *
 * @param monthlyPriceCents - Monthly price in cents
 * @param annualDiscountPercent - Discount percentage for annual billing (default: 0)
 * @returns Yearly price in cents
 */
export function calculateYearlyPrice(
  monthlyPriceCents: number,
  annualDiscountPercent = 0
): number {
  const yearlyBase = monthlyPriceCents * 12;
  if (annualDiscountPercent > 0) {
    return Math.round(yearlyBase * (1 - annualDiscountPercent / 100));
  }
  return yearlyBase;
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

/**
 * Formats proration amount with appropriate sign
 *
 * @param prorationCents - Proration amount in cents (positive = charge, negative = credit)
 * @param currency - ISO 4217 currency code
 * @returns Formatted proration string
 */
export function formatProration(
  prorationCents: number,
  currency = 'USD'
): {
  formatted: string;
  isCredit: boolean;
  isCharge: boolean;
} {
  const isCredit = prorationCents < 0;
  const isCharge = prorationCents > 0;
  const absAmount = Math.abs(prorationCents);
  const formatted = formatCurrency(absAmount, currency);

  return {
    formatted: isCredit ? `-${formatted}` : formatted,
    isCredit,
    isCharge,
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

/**
 * Gets days remaining until a promotional discount ends
 */
export function getPromotionalDiscountDaysRemaining(discountInfo: PlanDiscountInfo): number | null {
  if (!discountInfo.promotional_discount_end) return null;

  const endDate = new Date(discountInfo.promotional_discount_end);
  const now = new Date();
  const diffTime = endDate.getTime() - now.getTime();
  const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));

  return diffDays > 0 ? diffDays : null;
}
