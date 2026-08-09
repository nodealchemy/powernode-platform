/**
 * Host UI API surface — the single source of truth for every module the core
 * app exposes to dedicated (runtime-loaded) extension frontend bundles.
 *
 * ARCHITECTURE
 * ------------
 * Extension frontends are built as standalone ESM bundles (P2) and linked to
 * core at RUNTIME via an injected `<script type="importmap">`. During the
 * extension build, every id listed here is marked EXTERNAL, so the extension
 * bundle emits bare `import … from '<id>'` statements instead of inlining core
 * code. At runtime the browser resolves each bare specifier through the import
 * map to a stable re-export chunk core emits (`/assets/host/<name>.js`), which
 * re-exports core's OWN module instance.
 *
 * WHY THIS MATTERS (the whole point)
 * ----------------------------------
 * Because the extension imports these instead of bundling its own copy, every
 * stateful singleton — `apiClient`, `WebSocketManager`, `featureRegistry`, the
 * redux store/slices, and React itself — resolves to core's ONE instance. An
 * extension that bundled its own React or its own featureRegistry would render
 * against a second, empty registry and a detached React runtime (hooks would
 * throw "invalid hook call"). The import map is what keeps them unified.
 *
 * COUPLING SURFACE
 * ----------------
 * This array is the EXPLICIT, curated coupling contract between core and
 * extension frontends. Any NEW `@/…` module an extension needs to import MUST
 * be added to {@link HOST_APP_IDS} here — otherwise the extension build cannot
 * externalize it and will fail (or, worse, silently bundle a duplicate). Keep
 * it minimal: a smaller surface is a smaller contract to keep stable.
 *
 * The `@/…` list below was derived empirically from the imports the system
 * extension frontend actually uses:
 *   grep -rhoE "from '@/[^']+'" extensions/system/frontend/src | sort -u
 */

/**
 * Version of the host UI API contract. The compose-time-emitted per-extension
 * `manifest.json` declares the `coreUiApi` version it was built against; the
 * runtime loader refuses to load a module whose `coreUiApi` does not match this
 * value (prevents linking an extension built against an incompatible surface).
 * Bump this on any BREAKING change to an exposed module's runtime shape.
 */
export const CORE_UI_API_VERSION = 1;

/**
 * Core `@/…` modules exposed to extension frontends. Derived empirically from
 * `extensions/system/frontend/src`. ADD to this list when an extension needs a
 * new core module (that is the explicit coupling surface — see file header).
 */
const HOST_APP_IDS = [
  // Feature surfaces reused by extensions
  '@/features/ai/provisioning/PlatformDeploymentWizardCard',
  '@/features/onboarding/ProviderCredentialForm',
  // Shared components
  '@/shared/components/approval-chains/ApprovalChainList',
  '@/shared/components/autonomy/AutonomyPolicyGroup',
  '@/shared/components/charts',
  '@/shared/components/concierge/ConciergeActionCard',
  '@/shared/components/entity',
  '@/shared/components/layout/PageContainer',
  '@/shared/components/navigation/PathTabs',
  '@/shared/components/ui/Badge',
  '@/shared/components/ui/Button',
  '@/shared/components/ui/Card',
  '@/shared/components/ui/ConfirmationModal',
  '@/shared/components/ui/LoadingSpinner',
  '@/shared/components/ui/Modal',
  '@/shared/components/ui/MultiSelect',
  '@/shared/components/ui/TabContainer',
  // Shared hooks
  '@/shared/hooks/BreadcrumbContext',
  '@/shared/hooks/useArmedConfirm',
  '@/shared/hooks/useAuth',
  '@/shared/hooks/useAutonomyConfig',
  '@/shared/hooks/useNotifications',
  '@/shared/hooks/usePermissions',
  '@/shared/hooks/useQueryParamFilter',
  '@/shared/hooks/useWebSocket',
  // Shared services (stateful singletons — MUST be core's single instance)
  '@/shared/services',
  '@/shared/services/apiClient',
  '@/shared/services/entityRegistry',
  '@/shared/services/featureRegistry',
  '@/shared/services/slices/authSlice',
  '@/shared/services/slices/uiSlice',
  '@/shared/services/WebSocketManager',
  // Shared types (type-only — the emitted re-export chunk is inert at runtime
  // because TS erases type-only imports; kept here so the extension build can
  // externalize them uniformly)
  '@/shared/types/ai',
  '@/shared/types/autonomy',
  // Shared utils
  '@/shared/utils/formatters',
  '@/shared/utils/logger',
  '@/shared/utils/workflowLayout',
] as const;

/**
 * npm singletons that MUST resolve to core's single instance. React, ReactDOM,
 * the router, redux, and axios all hold cross-cutting module state (React's
 * dispatcher, the redux store, axios interceptors); a duplicate instance breaks
 * hooks / context / auth. Externalizing them through the import map guarantees
 * the extension shares core's copies.
 */
const HOST_NPM_IDS = [
  'react',
  'react/jsx-runtime',
  'react-dom',
  'react-dom/client',
  'react-router-dom',
  'react-redux',
  '@reduxjs/toolkit',
  'axios',
] as const;

/**
 * Every bare specifier core exposes to extension frontends. This drives both
 * the emitted host re-export chunks and the injected import map (see
 * `vite.config.ts`), and is the authoritative externals list for P2's
 * extension build.
 */
export const HOST_EXPOSED_IDS: readonly string[] = [...HOST_APP_IDS, ...HOST_NPM_IDS];

/**
 * Deterministic, collision-checked file-stem for the host re-export chunk of a
 * given exposed id. Used as the SINGLE source of truth for both the emitted
 * chunk filename (`assets/host/<name>.js`) and the import-map target, so the
 * two can never drift. Kept dependency-free so `vite.config.ts` (Node build
 * context) can import it directly.
 *
 * e.g. '@/shared/services/apiClient' -> 'shared-services-apiClient'
 *      'react/jsx-runtime'           -> 'react-jsx-runtime'
 *      '@reduxjs/toolkit'            -> 'reduxjs-toolkit'
 */
export function hostChunkName(id: string): string {
  return id
    .replace(/^@\//, '') // core alias prefix
    .replace(/^@/, '') // scoped npm packages
    .replace(/[^a-zA-Z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}
