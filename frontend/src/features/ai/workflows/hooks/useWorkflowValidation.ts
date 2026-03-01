import { useState, useCallback, useRef, useEffect } from 'react';
import type { WorkflowValidationResult } from '@/shared/types/workflow';
import { validationApi } from '@/shared/services/ai';

export interface UseWorkflowValidationOptions {
  workflowId: string;
  autoValidate?: boolean;
  validateOnChange?: boolean;
  debounceMs?: number;
}

export interface UseWorkflowValidationReturn {
  validationResult: WorkflowValidationResult | null;
  isValidating: boolean;
  error: string | null;
  validate: () => Promise<WorkflowValidationResult | null>;
  clearResult: () => void;
}

/**
 * Custom hook for workflow validation
 *
 * @example
 * ```tsx
 * const { validationResult, isValidating, validate } = useWorkflowValidation({
 *   workflowId: 'workflow-123',
 *   autoValidate: true
 * });
 *
 * // Manual validation
 * const handleValidate = async () => {
 *   const result = await validate();
 *   if (result) {
 *     logger.info('Health score:', result.health_score);
 *   }
 * };
 * ```
 */
export const useWorkflowValidation = (
  options: UseWorkflowValidationOptions
): UseWorkflowValidationReturn => {
  const {
    workflowId,
    autoValidate = false,
    validateOnChange = false,
    debounceMs = 1000
  } = options;

  const [validationResult, setValidationResult] = useState<WorkflowValidationResult | null>(null);
  const [isValidating, setIsValidating] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const debounceTimerRef = useRef<NodeJS.Timeout | null>(null);
  const validateCountRef = useRef(0);

  /**
   * Perform workflow validation
   */
  const validate = useCallback(async (): Promise<WorkflowValidationResult | null> => {
    if (!workflowId) {
      setError('No workflow ID provided');
      return null;
    }

    try {
      setIsValidating(true);
      setError(null);
      validateCountRef.current += 1;

      const response = await validationApi.validateWorkflow(workflowId);
      setValidationResult(response.validation_result);
      return response.validation_result;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Validation failed';
      setError(errorMessage);
      return null;
    } finally {
      setIsValidating(false);
    }
  }, [workflowId]);

  /**
   * Debounced validation
   */
  const debouncedValidate = useCallback(() => {
    if (debounceTimerRef.current) {
      clearTimeout(debounceTimerRef.current);
    }

    debounceTimerRef.current = setTimeout(() => {
      validate();
    }, debounceMs);
  }, [validate, debounceMs]);

  /**
   * Clear validation result
   */
  const clearResult = useCallback(() => {
    setValidationResult(null);
    setError(null);
  }, []);

  /**
   * Auto-validate on mount
   */
  useEffect(() => {
    if (autoValidate && workflowId) {
      validate();
    }
  }, [autoValidate, workflowId, validate]);

  /**
   * Validate on workflow changes
   */
  useEffect(() => {
    if (validateOnChange && workflowId) {
      debouncedValidate();
    }

    return () => {
      if (debounceTimerRef.current) {
        clearTimeout(debounceTimerRef.current);
      }
    };
  }, [validateOnChange, workflowId, debouncedValidate]);

  return {
    validationResult,
    isValidating,
    error,
    validate,
    clearResult
  };
};
