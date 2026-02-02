import { useMemo, useCallback } from 'react';
import Ajv, { ErrorObject } from 'ajv';
import addFormats from 'ajv-formats';
import type { JsonSchema, JsonSchemaProperty } from '../JsonSchemaForm';

export interface ValidationResult {
  isValid: boolean;
  errors: Record<string, string>;
  rawErrors: ErrorObject[] | null;
}

export interface UseSchemaValidationOptions {
  /** Enable AJV strict mode (default: false) */
  strict?: boolean;
  /** Remove additional properties not in schema (default: false) */
  removeAdditional?: boolean;
  /** Use defaults from schema (default: true) */
  useDefaults?: boolean;
  /** Coerce types (default: true) */
  coerceTypes?: boolean;
  /** Allow all formats (default: true for workflow variables) */
  allErrors?: boolean;
}

const defaultOptions: UseSchemaValidationOptions = {
  strict: false,
  removeAdditional: false,
  useDefaults: true,
  coerceTypes: true,
  allErrors: true,
};

/**
 * Hook for validating form data against a JSON Schema using AJV.
 * Supports format validation (email, uri, date-time, etc.) and custom error messages.
 */
export function useSchemaValidation(
  schema: JsonSchema | Record<string, unknown> | null,
  options: UseSchemaValidationOptions = {}
) {
  const mergedOptions = { ...defaultOptions, ...options };

  // Create AJV instance with formats
  const ajv = useMemo(() => {
    const instance = new Ajv({
      strict: mergedOptions.strict,
      removeAdditional: mergedOptions.removeAdditional,
      useDefaults: mergedOptions.useDefaults,
      coerceTypes: mergedOptions.coerceTypes,
      allErrors: mergedOptions.allErrors,
      // Allow unknown formats (like our custom 'textarea')
      validateFormats: true,
      allowUnionTypes: true,
    });

    // Add standard formats (email, uri, date-time, etc.)
    addFormats(instance, {
      mode: 'fast',
      formats: [
        'date',
        'time',
        'date-time',
        'duration',
        'uri',
        'uri-reference',
        'uri-template',
        'url',
        'email',
        'hostname',
        'ipv4',
        'ipv6',
        'regex',
        'uuid',
        'json-pointer',
        'relative-json-pointer',
      ],
    });

    // Add custom format for our textarea type (always valid)
    instance.addFormat('textarea', {
      type: 'string',
      validate: () => true,
    });

    // Add format for workflow variables ({{variable.path}})
    instance.addFormat('variable', {
      type: 'string',
      validate: (value: string) => /\{\{[^}]+\}\}/.test(value),
    });

    return instance;
  }, [
    mergedOptions.strict,
    mergedOptions.removeAdditional,
    mergedOptions.useDefaults,
    mergedOptions.coerceTypes,
    mergedOptions.allErrors,
  ]);

  // Compile schema validator
  const validator = useMemo(() => {
    if (!schema) return null;

    try {
      // Normalize schema if needed
      const normalizedSchema = normalizeSchemaForValidation(schema);
      return ajv.compile(normalizedSchema);
    } catch {
      if (process.env.NODE_ENV === 'development') {
        console.warn('Failed to compile schema:', error);
      }
      return null;
    }
  }, [ajv, schema]);

  /**
   * Validate data against the schema
   */
  const validate = useCallback(
    (data: Record<string, unknown>): ValidationResult => {
      if (!validator) {
        return { isValid: true, errors: {}, rawErrors: null };
      }

      // Allow workflow variables in any string field
      const dataWithResolvedVariables = preprocessDataForValidation(data);

      const isValid = validator(dataWithResolvedVariables);

      if (isValid) {
        return { isValid: true, errors: {}, rawErrors: null };
      }

      const errors = formatValidationErrors(validator.errors || []);

      return {
        isValid: false,
        errors,
        rawErrors: validator.errors || null,
      };
    },
    [validator]
  );

  /**
   * Validate a single field
   */
  const validateField = useCallback(
    (fieldPath: string, value: unknown): string | null => {
      if (!schema) return null;

      const normalizedSchema = normalizeSchemaForValidation(schema);
      const fieldSchema = getFieldSchema(normalizedSchema, fieldPath);

      if (!fieldSchema) return null;

      try {
        const fieldValidator = ajv.compile({
          type: 'object',
          properties: { [fieldPath]: fieldSchema },
        });

        const isValid = fieldValidator({ [fieldPath]: value });

        if (isValid) return null;

        const errors = fieldValidator.errors || [];
        return errors.length > 0 ? formatSingleError(errors[0]) : null;
      } catch {
        return null;
      }
    },
    [ajv, schema]
  );

  /**
   * Check if a value contains a workflow variable reference
   */
  const containsVariable = useCallback((value: unknown): boolean => {
    if (typeof value !== 'string') return false;
    return /\{\{[^}]+\}\}/.test(value);
  }, []);

  return {
    validate,
    validateField,
    containsVariable,
    isSchemaValid: !!validator,
  };
}

// Helper functions

function normalizeSchemaForValidation(
  schema: JsonSchema | Record<string, unknown>
): Record<string, unknown> {
  if (schema && typeof schema === 'object' && 'properties' in schema) {
    return schema as Record<string, unknown>;
  }

  if (schema && typeof schema === 'object') {
    return {
      type: 'object',
      properties: schema,
    };
  }

  return { type: 'object', properties: {} };
}

function getFieldSchema(
  schema: Record<string, unknown>,
  fieldPath: string
): JsonSchemaProperty | null {
  const properties = schema.properties as Record<string, JsonSchemaProperty> | undefined;
  if (!properties) return null;

  const parts = fieldPath.split('.');
  let current: JsonSchemaProperty | undefined = properties[parts[0]];

  for (let i = 1; i < parts.length; i++) {
    if (!current?.properties) return null;
    current = current.properties[parts[i]];
  }

  return current || null;
}

function formatValidationErrors(errors: ErrorObject[]): Record<string, string> {
  const result: Record<string, string> = {};

  for (const error of errors) {
    const path = error.instancePath
      ? error.instancePath.replace(/^\//, '').replace(/\//g, '.')
      : (error.params as Record<string, string>)?.missingProperty || 'form';

    if (!result[path]) {
      result[path] = formatSingleError(error);
    }
  }

  return result;
}

function formatSingleError(error: ErrorObject): string {
  const params = error.params as Record<string, unknown>;

  switch (error.keyword) {
    case 'required':
      return `${formatFieldName(params.missingProperty as string)} is required`;
    case 'type':
      return `Must be a ${params.type}`;
    case 'minimum':
      return `Must be at least ${params.limit}`;
    case 'maximum':
      return `Must be at most ${params.limit}`;
    case 'minLength':
      return `Must be at least ${params.limit} characters`;
    case 'maxLength':
      return `Must be at most ${params.limit} characters`;
    case 'pattern':
      return 'Invalid format';
    case 'format':
      return `Invalid ${params.format} format`;
    case 'enum':
      return `Must be one of: ${(params.allowedValues as unknown[])?.join(', ')}`;
    case 'minItems':
      return `Must have at least ${params.limit} items`;
    case 'maxItems':
      return `Must have at most ${params.limit} items`;
    case 'uniqueItems':
      return 'Items must be unique';
    default:
      return error.message || 'Invalid value';
  }
}

function formatFieldName(name: string): string {
  return name
    .replace(/_/g, ' ')
    .replace(/([A-Z])/g, ' $1')
    .replace(/^./, (str) => str.toUpperCase())
    .trim();
}

function preprocessDataForValidation(
  data: Record<string, unknown>
): Record<string, unknown> {
  const result: Record<string, unknown> = {};

  for (const [key, value] of Object.entries(data)) {
    // If value is a string with workflow variable, keep it as-is
    // AJV will validate the pattern if needed
    if (typeof value === 'string' && /\{\{[^}]+\}\}/.test(value)) {
      // Replace variable placeholders with a valid placeholder for format validation
      // This allows variables in email/uri fields to pass validation
      result[key] = value.replace(/\{\{[^}]+\}\}/g, 'placeholder@example.com');
    } else if (typeof value === 'object' && value !== null && !Array.isArray(value)) {
      result[key] = preprocessDataForValidation(value as Record<string, unknown>);
    } else {
      result[key] = value;
    }
  }

  return result;
}

export default useSchemaValidation;
