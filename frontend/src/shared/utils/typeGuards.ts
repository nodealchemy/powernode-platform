/**
 * Type Guards for Runtime Type Safety
 *
 * This module provides type guard functions for safe runtime type checking.
 * Use these to narrow unknown types to specific interfaces.
 */

/**
 * Safely extracts error message from unknown error type
 * @param error Unknown error value
 * @returns Error message string
 */
export function getErrorMessage(error: unknown): string {
  if (error instanceof Error) {
    return error.message;
  }

  if (typeof error === 'string') {
    return error;
  }

  if (
    typeof error === 'object' &&
    error !== null &&
    'message' in error &&
    typeof (error as Record<string, unknown>).message === 'string'
  ) {
    return (error as Record<string, unknown>).message as string;
  }

  return 'An unexpected error occurred';
}

/**
 * Checks if a value is a non-null object
 */
export function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
