/**
 * Hook for managing AI prompt templates
 */

import { useState, useEffect, useCallback } from 'react';
import { promptsApi } from '../services/promptsApi';
import type {
  PromptTemplate,
  PromptTemplateFormData,
  PromptTemplatesParams,
  PromptPreviewResponse,
} from '../types';

interface UsePromptTemplatesResult {
  templates: PromptTemplate[];
  meta: {
    total: number;
    by_category: Record<string, number>;
    by_domain: Record<string, number>;
  } | null;
  loading: boolean;
  error: string | null;
  refresh: () => Promise<void>;
  createTemplate: (data: PromptTemplateFormData) => Promise<PromptTemplate>;
  updateTemplate: (id: string, data: Partial<PromptTemplateFormData>) => Promise<PromptTemplate>;
  deleteTemplate: (id: string) => Promise<void>;
  duplicateTemplate: (id: string) => Promise<PromptTemplate>;
  previewTemplate: (id: string, variables: Record<string, string>) => Promise<PromptPreviewResponse>;
}

export function usePromptTemplates(params?: PromptTemplatesParams): UsePromptTemplatesResult {
  const [templates, setTemplates] = useState<PromptTemplate[]>([]);
  const [meta, setMeta] = useState<UsePromptTemplatesResult['meta']>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const loadTemplates = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const response = await promptsApi.getAll(params);
      setTemplates(response.prompt_templates);
      setMeta(response.meta);
    } catch {
      setError(err instanceof Error ? err.message : 'Failed to load prompt templates');
    } finally {
      setLoading(false);
    }
  }, [params?.category, params?.domain, params?.is_active, params?.root_only, params?.search]);

  useEffect(() => {
    loadTemplates();
  }, [loadTemplates]);

  const createTemplate = useCallback(async (data: PromptTemplateFormData) => {
    const template = await promptsApi.create(data);
    await loadTemplates();
    return template;
  }, [loadTemplates]);

  const updateTemplate = useCallback(async (id: string, data: Partial<PromptTemplateFormData>) => {
    const template = await promptsApi.update(id, data);
    await loadTemplates();
    return template;
  }, [loadTemplates]);

  const deleteTemplate = useCallback(async (id: string) => {
    await promptsApi.delete(id);
    await loadTemplates();
  }, [loadTemplates]);

  const duplicateTemplate = useCallback(async (id: string) => {
    const template = await promptsApi.duplicate(id);
    await loadTemplates();
    return template;
  }, [loadTemplates]);

  const previewTemplate = useCallback(async (id: string, variables: Record<string, string>) => {
    return promptsApi.preview(id, variables);
  }, []);

  return {
    templates,
    meta,
    loading,
    error,
    refresh: loadTemplates,
    createTemplate,
    updateTemplate,
    deleteTemplate,
    duplicateTemplate,
    previewTemplate,
  };
}

interface UsePromptTemplateResult {
  template: PromptTemplate | null;
  loading: boolean;
  error: string | null;
  refresh: () => Promise<void>;
  updateTemplate: (data: Partial<PromptTemplateFormData>) => Promise<PromptTemplate>;
}

export function usePromptTemplate(id: string | undefined): UsePromptTemplateResult {
  const [template, setTemplate] = useState<PromptTemplate | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const loadTemplate = useCallback(async () => {
    if (!id) {
      setTemplate(null);
      setLoading(false);
      return;
    }

    try {
      setLoading(true);
      setError(null);
      const data = await promptsApi.getById(id, true);
      setTemplate(data);
    } catch {
      setError(err instanceof Error ? err.message : 'Failed to load prompt template');
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    loadTemplate();
  }, [loadTemplate]);

  const updateTemplate = useCallback(async (data: Partial<PromptTemplateFormData>) => {
    if (!id) throw new Error('No template ID');
    const updated = await promptsApi.update(id, data);
    setTemplate(updated);
    return updated;
  }, [id]);

  return {
    template,
    loading,
    error,
    refresh: loadTemplate,
    updateTemplate,
  };
}
