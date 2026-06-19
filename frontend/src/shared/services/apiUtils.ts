/**
 * API utility functions for standardized response handling
 *
 * This module provides helper functions for working with API responses,
 * including response wrapping, pagination handling, and error formatting.
 */

import { APIResponse, PaginatedResponse } from '@/shared/types';

// Re-export types for convenience
export type { APIResponse, PaginatedResponse };

/**
 * Pagination information for list endpoints
 */
export interface PaginationInfo {
  page: number;
  perPage: number;
  total: number;
  totalPages: number;
}

/**
 * Extracts data from API response, handling nested data property
 */
export function extractData<T>(response: { data?: T } | T): T {
  if (response && typeof response === 'object' && 'data' in response) {
    return (response as { data: T }).data;
  }
  return response as T;
}

/**
 * Converts snake_case keys to camelCase
 */
export function toCamelCase<T extends Record<string, unknown>>(obj: T): T {
  const result: Record<string, unknown> = {};

  for (const [key, value] of Object.entries(obj)) {
    const camelKey = key.replace(/_([a-z])/g, (_, letter) => letter.toUpperCase());

    if (value && typeof value === 'object' && !Array.isArray(value)) {
      result[camelKey] = toCamelCase(value as Record<string, unknown>);
    } else if (Array.isArray(value)) {
      result[camelKey] = value.map(item =>
        item && typeof item === 'object' ? toCamelCase(item as Record<string, unknown>) : item
      );
    } else {
      result[camelKey] = value;
    }
  }

  return result as T;
}

/**
 * Converts camelCase keys to snake_case
 */
export function toSnakeCase<T extends Record<string, unknown>>(obj: T): T {
  const result: Record<string, unknown> = {};

  for (const [key, value] of Object.entries(obj)) {
    const snakeKey = key.replace(/[A-Z]/g, letter => `_${letter.toLowerCase()}`);

    if (value && typeof value === 'object' && !Array.isArray(value)) {
      result[snakeKey] = toSnakeCase(value as Record<string, unknown>);
    } else if (Array.isArray(value)) {
      result[snakeKey] = value.map(item =>
        item && typeof item === 'object' ? toSnakeCase(item as Record<string, unknown>) : item
      );
    } else {
      result[snakeKey] = value;
    }
  }

  return result as T;
}
