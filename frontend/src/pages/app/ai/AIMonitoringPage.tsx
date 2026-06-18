/**
 * AIMonitoringPage — SUPERSEDED.
 *
 * The legacy 7-tab Observability dashboard was split into two sidebar hubs:
 *   - `ObservabilityPage` (`/app/ai/observability`): health · systems · conversations · evaluation
 *   - `OperationsPage`    (`/app/ai/operations`):     aiops · alerts · traces
 * (the Credits tab moved to the Cost domain.)
 *
 * This module is retained as a thin re-export so existing imports/routes keep
 * resolving until routing is repointed to the new hubs directly. New code should
 * import `ObservabilityPage` / `OperationsPage` instead.
 */
export { ObservabilityPage, ObservabilityPage as AIMonitoringPage } from './ObservabilityPage';
