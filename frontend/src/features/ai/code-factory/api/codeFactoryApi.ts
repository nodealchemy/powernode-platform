import { apiClient } from '@/shared/services/apiClient';
import type {
  RiskContract,
  ReviewState,
  EvidenceManifest,
  HarnessGap,
  PreflightResult,
  HarnessGapMetrics,
  SlaCompliance,
} from '../types/codeFactory';

const BASE_PATH = '/ai/code_factory';

interface ApiEnvelope<T> {
  success: boolean;
  data: T;
  meta?: Record<string, unknown>;
  message?: string;
}

async function unwrap<T>(request: Promise<{ data: ApiEnvelope<T> }>): Promise<ApiEnvelope<T>> {
  const response = await request;
  return response.data;
}

export const codeFactoryApi = {
  // Contracts
  getContracts: (params?: { status?: string; repository_id?: string }) =>
    unwrap<{ contracts: RiskContract[] }>(apiClient.get(`${BASE_PATH}/contracts`, { params })),

  getContract: (id: string) =>
    unwrap<{ contract: RiskContract }>(apiClient.get(`${BASE_PATH}/contracts/${id}`)),

  createContract: (data: Partial<RiskContract>) =>
    unwrap<{ contract: RiskContract }>(apiClient.post(`${BASE_PATH}/contracts`, data)),

  updateContract: (id: string, data: Partial<RiskContract>) =>
    unwrap<{ contract: RiskContract }>(apiClient.put(`${BASE_PATH}/contracts/${id}`, data)),

  activateContract: (id: string) =>
    unwrap<{ contract: RiskContract }>(apiClient.post(`${BASE_PATH}/contracts/${id}/activate`)),

  // Preflight
  runPreflight: (data: {
    contract_id?: string;
    pr_number: number;
    head_sha: string;
    changed_files: string[];
    repository_id?: string;
  }) =>
    unwrap<{ preflight: PreflightResult }>(apiClient.post(`${BASE_PATH}/preflight`, data)),

  // Review States
  getReviewStates: (params?: { status?: string; repository_id?: string }) =>
    unwrap<{ review_states: ReviewState[] }>(apiClient.get(`${BASE_PATH}/review_states`, { params })),

  getReviewState: (id: string) =>
    unwrap<{ review_state: ReviewState }>(apiClient.get(`${BASE_PATH}/review_states/${id}`)),

  triggerRemediation: (id: string, findings: Record<string, unknown>[]) =>
    unwrap<{ remediation: Record<string, unknown> }>(
      apiClient.post(`${BASE_PATH}/review_states/${id}/remediate`, { findings })
    ),

  resolveThreads: (id: string) =>
    unwrap<{ thread_resolution: Record<string, unknown> }>(
      apiClient.post(`${BASE_PATH}/review_states/${id}/resolve_threads`)
    ),

  // Evidence
  submitEvidence: (data: {
    review_state_id: string;
    manifest_type: string;
    artifacts?: Record<string, unknown>[];
    assertions?: Record<string, unknown>[];
  }) =>
    unwrap<{ evidence: { manifest_id: string; validation: Record<string, unknown> } }>(
      apiClient.post(`${BASE_PATH}/evidence`, data)
    ),

  getEvidence: (id: string) =>
    unwrap<{ evidence: EvidenceManifest }>(apiClient.get(`${BASE_PATH}/evidence/${id}`)),

  // Harness Gaps
  getHarnessGaps: (params?: { status?: string; severity?: string }) =>
    unwrap<{
      harness_gaps: HarnessGap[];
      metrics: HarnessGapMetrics;
      sla: SlaCompliance;
    }>(apiClient.get(`${BASE_PATH}/harness_gaps`, { params })),

  createHarnessGap: (data: {
    incident_id: string;
    description: string;
    severity?: string;
    incident_source?: string;
    risk_contract_id?: string;
    sla_hours?: number;
  }) =>
    unwrap<{ harness_gap: HarnessGap }>(apiClient.post(`${BASE_PATH}/harness_gaps`, data)),

  addTestCase: (id: string, testReference: string) =>
    unwrap<{ harness_gap: HarnessGap }>(
      apiClient.put(`${BASE_PATH}/harness_gaps/${id}/add_case`, { test_reference: testReference })
    ),

  closeHarnessGap: (id: string, resolutionNotes?: string) =>
    unwrap<{ harness_gap: HarnessGap }>(
      apiClient.put(`${BASE_PATH}/harness_gaps/${id}/close`, { resolution_notes: resolutionNotes })
    ),

  // Webhook
  processWebhook: (data: {
    event_type: string;
    pr_number: number;
    head_sha: string;
    changed_files: string[];
    repository_id?: string;
  }) =>
    unwrap<{ result: Record<string, unknown> }>(apiClient.post(`${BASE_PATH}/webhook`, data)),
};
