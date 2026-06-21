/**
 * Generic API helpers for the globally-scoped content endpoints shared by every
 * foundational content type (skills, prompt templates, mission/team/agent/devops
 * templates, knowledge bases):
 *
 *   POST  {base}/:id/clone                        -> fork a global item into the account
 *   GET   {base}/:id/update_from_source/preview   -> 3-way diff of a clone vs its origin
 *   POST  {base}/:id/update_from_source           -> apply the merge
 *
 * A content feature builds its own typed wrapper by calling
 * `createScopedContentApi('/ai/skills')` (etc.) so the clone/update plumbing is
 * written once and reused.
 *
 * Responses follow the platform envelope `{ success, data }`. The clone and
 * update-from-source actions nest the serialized record one level deeper under
 * `data.data` (the controller passes `{ data: record }` as its payload); this
 * helper unwraps that so callers always receive the bare record.
 */
import { api } from '@/shared/services/api';
import type {
  ContentScope,
  UpdateFromSourcePreview,
  ConflictResolutions,
} from './types';

/** Append `?scope=` to a params object when a non-default scope is selected. */
export function applyScopeParam(
  params: URLSearchParams,
  scope?: ContentScope,
): URLSearchParams {
  if (scope) params.set('scope', scope);
  return params;
}

/** Plain object form of the scope param, for axios `{ params }` callers. */
export function scopeParams(scope?: ContentScope): Record<string, string> {
  return scope ? { scope } : {};
}

export interface ScopedContentApi<T> {
  /** Fork a global (read-only) item into the account as an editable copy. */
  clone: (id: string) => Promise<T>;
  /** 3-way diff of an account copy against its origin (no save). */
  updateFromSourcePreview: (id: string) => Promise<UpdateFromSourcePreview>;
  /** Apply the merge, optionally resolving conflicts. Returns the updated copy. */
  updateFromSource: (id: string, resolutions?: ConflictResolutions) => Promise<T>;
}

interface Envelope<D> {
  success?: boolean;
  data?: D;
  error?: string;
}

/**
 * Build clone / update-from-source helpers bound to a resource base path.
 *
 * @param basePath e.g. `'/ai/skills'` or `'/ai/prompt_templates'`
 */
export function createScopedContentApi<T>(basePath: string): ScopedContentApi<T> {
  return {
    async clone(id: string): Promise<T> {
      const response = await api.post<Envelope<Envelope<T>>>(`${basePath}/${id}/clone`);
      // Controller returns `{ data: record }` as its payload, so the record is
      // at body.data.data (with body.data.data falling back to body.data for
      // controllers that serialize the record directly).
      const body = response.data;
      const inner = body?.data;
      return ((inner && (inner as Envelope<T>).data) ?? inner) as T;
    },

    async updateFromSourcePreview(id: string): Promise<UpdateFromSourcePreview> {
      const response = await api.get<Envelope<UpdateFromSourcePreview>>(
        `${basePath}/${id}/update_from_source/preview`,
      );
      return response.data.data as UpdateFromSourcePreview;
    },

    async updateFromSource(
      id: string,
      resolutions?: ConflictResolutions,
    ): Promise<T> {
      const response = await api.post<Envelope<UpdateFromSourcePreview & { data?: T }>>(
        `${basePath}/${id}/update_from_source`,
        resolutions ? { resolutions } : {},
      );
      const payload = response.data.data;
      return (payload?.data ?? payload) as T;
    },
  };
}
