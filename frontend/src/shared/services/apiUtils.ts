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
 * Wraps list data with pagination info
 */
export function wrapListResponse<T>(
  data: T[],
  pagination: PaginationInfo
): ListResponse<T> {
  return {
    success: true,
    data,
    pagination,
  };
}

/**
 * Normalizes pagination response from different API formats
 * Handles various pagination key naming conventions
 */
export function normalizePagination(raw: Record<string, unknown>): PaginationInfo {
  return {
    page: (raw.page ?? raw.current_page ?? 1) as number,
    perPage: (raw.per_page ?? raw.perPage ?? 20) as number,
    total: (raw.total ?? raw.total_count ?? 0) as number,
    totalPages: (raw.pages ?? raw.total_pages ?? 0) as number,
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
 * Checks if response indicates success
 */
export function isSuccessResponse<T>(response: APIResponse<T>): response is APIResponse<T> & { data: T } {
  return response.success === true && response.data !== undefined;
}

/**
 * Checks if response indicates error
 */
export function isErrorResponse<T>(response: APIResponse<T>): response is APIResponse<T> & { error: string } {
  return response.success === false || response.error !== undefined;
}

/**
 * Safe API call wrapper with error handling
 * Catches errors and returns standardized error response
 */
export async function safeApiCall<T>(
  apiCall: () => Promise<T>
): Promise<APIResponse<T>> {
  try {
    const data = await apiCall();
    return wrapSuccess(data);
  } catch (error) {
    return wrapError(error);
  }
}

/**
 * Builds query string from params object
 * Filters out undefined/null values
 */
export function buildQueryParams(params: Record<string, unknown>): URLSearchParams {
  const searchParams = new URLSearchParams();

  Object.entries(params).forEach(([key, value]) => {
    if (value !== undefined && value !== null && value !== '') {
      if (Array.isArray(value)) {
        value.forEach(v => searchParams.append(key, String(v)));
      } else {
        searchParams.set(key, String(value));
      }
    }
  });

  return searchParams;
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
