/**
 * Type Guards for Runtime Type Safety
 *
 * This module provides type guard functions for safe runtime type checking.
 * Use these to narrow unknown types to specific interfaces.
 */

import type { NodeOutputData } from '@/shared/types/workflow';

/**
 * Checks if output is JSON type
 */
export function isNodeOutputJson(
  output: unknown
): output is Extract<NodeOutputData, { type: 'json' }> {
  return (
    typeof output === 'object' &&
    output !== null &&
    'type' in output &&
    (output as Record<string, unknown>).type === 'json' &&
    'data' in output
  );
}

/**
 * Checks if output is text type
 */
export function isNodeOutputText(
  output: unknown
): output is Extract<NodeOutputData, { type: 'text' }> {
  return (
    typeof output === 'object' &&
    output !== null &&
    'type' in output &&
    (output as Record<string, unknown>).type === 'text' &&
    'content' in output
  );
}

/**
 * Checks if output is markdown type
 */
export function isNodeOutputMarkdown(
  output: unknown
): output is Extract<NodeOutputData, { type: 'markdown' }> {
  return (
    typeof output === 'object' &&
    output !== null &&
    'type' in output &&
    (output as Record<string, unknown>).type === 'markdown' &&
    'content' in output
  );
}

/**
 * Checks if output is error type
 */
export function isNodeOutputError(
  output: unknown
): output is Extract<NodeOutputData, { type: 'error' }> {
  return (
    typeof output === 'object' &&
    output !== null &&
    'type' in output &&
    (output as Record<string, unknown>).type === 'error' &&
    'message' in output
  );
}

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

/**
 * Safely extracts a string property from an unknown object
 */
export function getStringProperty(
  obj: unknown,
  key: string
): string | undefined {
  if (!isObject(obj)) return undefined;
  const value = obj[key];
  return typeof value === 'string' ? value : undefined;
}

/**
 * Safely extracts a number property from an unknown object
 */
export function getNumberProperty(
  obj: unknown,
  key: string
): number | undefined {
  if (!isObject(obj)) return undefined;
  const value = obj[key];
  return typeof value === 'number' ? value : undefined;
}
