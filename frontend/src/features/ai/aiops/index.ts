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

export { AiOpsDashboard, AiOpsContent } from './components/AiOpsDashboard';

// Standalone, self-fetching sections. AiOpsContent renders Overview/Trends/
// Providers/Agents in the Operations tab; Cost + Reliability are exported here
// so they can be mounted into the existing Observability Credits/Alerts tabs.
export { OverviewSection } from './components/sections/OverviewSection';
export { TrendsSection } from './components/sections/TrendsSection';
export { ProvidersSection } from './components/sections/ProvidersSection';
export { AgentsSection } from './components/sections/AgentsSection';
export { CostSection } from './components/sections/CostSection';
export { ReliabilitySection } from './components/sections/ReliabilitySection';

// Query hooks + key factory (shared fetch surface for the sections).
export {
  AIOPS_KEYS,
  useAiOpsDashboard,
  useAiOpsRealTime,
  useAiOpsTrends,
  useAiOpsRecentErrors,
} from './api/aiopsApi';

export type { AiOpsTimeRange } from './components/sections/sectionShared';
