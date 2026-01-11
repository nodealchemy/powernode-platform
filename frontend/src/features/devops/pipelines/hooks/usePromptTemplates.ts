import { useState, useEffect, useCallback, useRef } from 'react';
import { ciCdPromptTemplatesApi } from '@/services/ciCdApi';
import type { CiCdPromptTemplate, CiCdPromptTemplateFormData, CiCdPromptPreviewResponse } from '@/types/cicd';
import { useNotifications } from '@/shared/hooks/useNotifications';

interface UsePromptTemplatesParams {
  category?: string;
  is_active?: boolean;
  root_only?: boolean;
}

export function usePromptTemplates(params: UsePromptTemplatesParams = {}) {
  const [templates, setTemplates] = useState<CiCdPromptTemplate[]>([]);
  const [meta, setMeta] = useState<{
    total: number;
    by_category: Record<string, number>;
  } | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const { showNotification } = useNotifications();
  const hasLoadedRef = useRef(false);
  const currentParamsRef = useRef<string>('');

  const fetchTemplates = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const data = await ciCdPromptTemplatesApi.getAll(params);
      setTemplates(data.prompt_templates);
      setMeta(data.meta);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to fetch prompt templates';
      setError(message);
    } finally {
      setLoading(false);
    }
  }, [params]);

  useEffect(() => {
    const paramsKey = JSON.stringify(params);
    if (!hasLoadedRef.current || currentParamsRef.current !== paramsKey) {
      hasLoadedRef.current = true;
      currentParamsRef.current = paramsKey;
      fetchTemplates();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [params.category, params.is_active, params.root_only]);

  const createTemplate = async (data: CiCdPromptTemplateFormData) => {
    try {
      const template = await ciCdPromptTemplatesApi.create(data);
      showNotification('Prompt template created successfully', 'success');
      await fetchTemplates();
      return template;
    } catch (err) {
      showNotification('Failed to create prompt template', 'error');
      return null;
    }
  };

  const updateTemplate = async (id: string, data: Partial<CiCdPromptTemplateFormData>) => {
    try {
      const template = await ciCdPromptTemplatesApi.update(id, data);
      showNotification('Prompt template updated successfully', 'success');
      await fetchTemplates();
      return template;
    } catch (err) {
      showNotification('Failed to update prompt template', 'error');
      return null;
    }
  };

  const deleteTemplate = async (id: string) => {
    try {
      await ciCdPromptTemplatesApi.delete(id);
      showNotification('Prompt template deleted successfully', 'success');
      await fetchTemplates();
      return true;
    } catch (err) {
      showNotification('Failed to delete prompt template', 'error');
      return false;
    }
  };

  const duplicateTemplate = async (id: string) => {
    try {
      const template = await ciCdPromptTemplatesApi.duplicate(id);
      showNotification('Prompt template duplicated successfully', 'success');
      await fetchTemplates();
      return template;
    } catch (err) {
      showNotification('Failed to duplicate prompt template', 'error');
      return null;
    }
  };

  const previewTemplate = async (id: string, variables: Record<string, string>): Promise<CiCdPromptPreviewResponse | null> => {
    try {
      const result = await ciCdPromptTemplatesApi.preview(id, variables);
      return result;
    } catch (err) {
      showNotification('Failed to preview prompt template', 'error');
      return null;
    }
  };

  return {
    templates,
    meta,
    loading,
    error,
    refresh: fetchTemplates,
    createTemplate,
    updateTemplate,
    deleteTemplate,
    duplicateTemplate,
    previewTemplate,
  };
}

export function usePromptTemplate(id: string | null) {
  const [template, setTemplate] = useState<CiCdPromptTemplate | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const { showNotification } = useNotifications();
  const hasLoadedRef = useRef<string | null>(null);

  const fetchTemplate = useCallback(async () => {
    if (!id) return;

    try {
      setLoading(true);
      setError(null);
      const data = await ciCdPromptTemplatesApi.getById(id, true);
      setTemplate(data);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to fetch prompt template';
      setError(message);
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    if (id && hasLoadedRef.current !== id) {
      hasLoadedRef.current = id;
      fetchTemplate();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id]);

  const updateTemplate = async (data: Partial<CiCdPromptTemplateFormData>) => {
    if (!id) return null;

    try {
      const updated = await ciCdPromptTemplatesApi.update(id, data);
      showNotification('Prompt template updated successfully', 'success');
      setTemplate(updated);
      return updated;
    } catch (err) {
      showNotification('Failed to update prompt template', 'error');
      return null;
    }
  };

  return {
    template,
    loading,
    error,
    refresh: fetchTemplate,
    updateTemplate,
  };
}
