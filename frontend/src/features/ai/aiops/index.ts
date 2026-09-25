/**
 * AIOps Feature Module
 *
 * Real-time AI Operations Dashboard for comprehensive observability
 * of AI workflows: latency, costs, errors, throughput, and model performance.
 *
 * Revenue Model: Monitoring tiers + alerting add-ons
 * - Basic monitoring: included in all plans
 * - Advanced analytics: $79/mo
 * - Custom dashboards + API: $199/mo
 * - Business (white-label + embedding): $499/mo
 */

// fc-42: the Operations hub is gone — AiOpsContent (Overview/Trends/Providers/
// Agents) is now the Observability "Systems" tab body directly. The
// standalone AiOpsDashboard page wrapper had no route and no other caller, so
// it was deleted along with it; AiOpsContent is exported prop-less for that
// direct mount.
export { AiOpsContent } from './components/AiOpsDashboard';

// Standalone, self-fetching sections, importable individually where a host
// page wants only one (e.g. CircuitBreakersTab pulls in just the recent-errors
// feed via useAiOpsRecentErrors below). ReliabilitySection (the old combined
// provider-breakers + recent-errors block) was deleted: its breaker table read
// a stale ProviderMetric snapshot rather than the live
// Ai::CircuitBreakerRegistry state, and CircuitBreakersTab's
// ProviderCircuitBreakersPanel replaces it with the real thing.
export { OverviewSection } from './components/sections/OverviewSection';
export { TrendsSection } from './components/sections/TrendsSection';
export { ProvidersSection } from './components/sections/ProvidersSection';
export { AgentsSection } from './components/sections/AgentsSection';

// Query hooks + key factory (shared fetch surface for the sections).
export {
  AIOPS_KEYS,
  useAiOpsDashboard,
  useAiOpsRealTime,
  useAiOpsTrends,
  useAiOpsRecentErrors,
} from './api/aiopsApi';

export type { AiOpsTimeRange } from './components/sections/sectionShared';
