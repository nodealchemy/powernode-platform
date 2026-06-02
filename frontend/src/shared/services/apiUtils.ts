/**
 * API utility functions for standardized response handling
 *
 * This module provides helper functions for working with API responses,
 * including response wrapping, pagination handling, and error formatting.
 */

import { APIResponse, PaginatedResponse } from '@/shared/types';
import { getErrorMessage } from '@/shared/utils/errorHandling';

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
 * Standardized list response with data and pagination
 */
export interface ListResponse<T> {
  success: boolean;
  data: T[];
  pagination: PaginationInfo;
  error?: string;
}

/**
 * Wraps data in a successful APIResponse
 */
export function wrapSuccess<T>(data: T, message?: string): APIResponse<T> {
  return {
    success: true,
    data,
    ...(message && { message }),
  };
}

/**
 * Creates an error APIResponse
 */
export function wrapError<T = never>(error: string | unknown): APIResponse<T> {
  const errorMessage = typeof error === 'string' ? error : getErrorMessage(error);
  return {
    success: false,
    error: errorMessage,
  };
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
