// Types
export type {
  AgentLineageNode,
  TrustScore,
  AutonomyStats,
  CircuitBreaker,
  CircuitBreakerState,
  CircuitBreakerEvent,
  CapabilityPolicy,
  CapabilityMatrix,
  AgentCapabilities,
  BehavioralFingerprint,
  ShadowExecution,
  TelemetryEvent,
  DelegationPolicy,
} from './types/autonomy';

// API hooks - queries
export {
  useTrustScores,
  useTrustScore,
  useAgentLineage,
  useAutonomyStats,
  useCapabilityMatrix,
  useAgentCapabilities,
  useCircuitBreakers,
  useAgentCircuitBreakers,
  useShadowExecutions,
  useAgentShadowExecutions,
  useTelemetryEvents,
  useAgentTelemetry,
  useDelegationPolicies,
  useAgentDelegationPolicy,
  useBehavioralFingerprints,
} from './api/autonomyApi';

// API hooks - mutations
export {
  useEvaluateTrustScore,
  useOverrideTrustScore,
  useEmergencyDemote,
  useResetCircuitBreaker,
  useCreateDelegationPolicy,
  useUpdateDelegationPolicy,
  useDeleteDelegationPolicy,
} from './api/autonomyApi';

// Components
export { TrustScoreCard } from './components/TrustScoreCard';
export { AgentLineageTree } from './components/AgentLineageTree';
export { CircuitBreakerStatusPanel } from './components/CircuitBreakerStatusPanel';
export { CapabilityMatrixViewer } from './components/CapabilityMatrixViewer';
export { BehavioralFingerprintChart } from './components/BehavioralFingerprintChart';
export { DelegationPolicyPanel } from './components/DelegationPolicyPanel';
export { ShadowModeResultsPanel } from './components/ShadowModeResultsPanel';
export { TelemetryEventStream } from './components/TelemetryEventStream';
export { KillSwitchStatusBar } from './components/KillSwitchStatusBar';

// Pages
export { AutonomyDashboardPage } from './pages/AutonomyDashboardPage';
