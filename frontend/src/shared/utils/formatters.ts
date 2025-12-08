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
