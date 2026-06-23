/**
 * Globally-scoped foundational content — reusable building blocks.
 *
 * Shared across every content type that is GLOBAL (platform-provided, read-only)
 * or ACCOUNT-owned (editable): skills, prompt templates, mission/team/agent/
 * devops templates, knowledge bases. Wire these into a content page to get the
 * scope filter, read-only/clone treatment, and update-from-source flow.
 */
export type {
  ContentScope,
  ScopedContent,
  UpdateFromSourcePreview,
  UpdateFromSourceConflict,
  ConflictResolutions,
} from './types';

export { isGlobal, isClone, canEditContent } from './helpers';

export {
  createScopedContentApi,
  applyScopeParam,
  scopeParams,
} from './scopedContentApi';
export type { ScopedContentApi } from './scopedContentApi';

export { useScopeParam } from './useScopeParam';

export { ScopeFilter } from './components/ScopeFilter';
export { CloneToCustomizeButton } from './components/CloneToCustomizeButton';
export { UpdateAvailableBadge } from './components/UpdateAvailableBadge';
export { UpdateFromSourceModal } from './components/UpdateFromSourceModal';
