import { useQuery, useMutation } from '@tanstack/react-query';
import { apiClient } from '@/shared/services/apiClient';

const INTELLIGENCE_KEYS = {
  all: ['intelligence'] as const,
  supplyChain: () => [...INTELLIGENCE_KEYS.all, 'supply-chain'] as const,
  riskSummary: () => [...INTELLIGENCE_KEYS.all, 'risk-summary'] as const,
  vulnerabilityReport: () => [...INTELLIGENCE_KEYS.all, 'vulnerability-report'] as const,
  pipelineHealth: () => [...INTELLIGENCE_KEYS.all, 'pipeline-health'] as const,
  failureTrends: () => [...INTELLIGENCE_KEYS.all, 'failure-trends'] as const,
  forecast: () => [...INTELLIGENCE_KEYS.all, 'forecast'] as const,
  churnRisks: () => [...INTELLIGENCE_KEYS.all, 'churn-risks'] as const,
  healthScores: () => [...INTELLIGENCE_KEYS.all, 'health-scores'] as const,
  usageAnomalies: () => [...INTELLIGENCE_KEYS.all, 'usage-anomalies'] as const,
  tenantChurn: () => [...INTELLIGENCE_KEYS.all, 'tenant-churn'] as const,
  pricingRecs: () => [...INTELLIGENCE_KEYS.all, 'pricing-recommendations'] as const,
  apiFraud: () => [...INTELLIGENCE_KEYS.all, 'api-fraud'] as const,
  performanceScores: () => [...INTELLIGENCE_KEYS.all, 'performance-scores'] as const,
  commissionOpt: () => [...INTELLIGENCE_KEYS.all, 'commission-optimization'] as const,
  referralChurn: () => [...INTELLIGENCE_KEYS.all, 'referral-churn'] as const,
  spamDetection: () => [...INTELLIGENCE_KEYS.all, 'spam-detection'] as const,
  agentQuality: () => [...INTELLIGENCE_KEYS.all, 'agent-quality'] as const,
  fatigueAnalysis: (userId?: string) => [...INTELLIGENCE_KEYS.all, 'fatigue-analysis', userId] as const,
  digestRecs: () => [...INTELLIGENCE_KEYS.all, 'digest-recommendations'] as const,
  predictiveFailure: (serviceName?: string) => [...INTELLIGENCE_KEYS.all, 'predictive-failure', serviceName] as const,
  selfHealing: () => [...INTELLIGENCE_KEYS.all, 'self-healing'] as const,
  slaBreachRisk: () => [...INTELLIGENCE_KEYS.all, 'sla-breach-risk'] as const,
};

// === Supply Chain ===
export function useSupplyChainAnalysis() {
  return useMutation({
    mutationFn: async (params: { target?: string }) => {
      const response = await apiClient.post('/ai/intelligence/supply_chain/analyze', params);
      return response.data?.data;
    },
  });
}

export function useRiskSummary() {
  return useQuery({
    queryKey: INTELLIGENCE_KEYS.riskSummary(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/intelligence/supply_chain/risk_summary');
      return response.data?.data;
    },
  });
}

export function useVulnerabilityReport() {
  return useQuery({
    queryKey: INTELLIGENCE_KEYS.vulnerabilityReport(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/intelligence/supply_chain/vulnerability_report');
      return response.data?.data;
    },
  });
}

// === Pipeline ===
export function useAnalyzePipelineFailure() {
  return useMutation({
    mutationFn: async (params: { pipeline_run_id: string }) => {
      const response = await apiClient.post('/ai/intelligence/pipeline/analyze_failure', params);
      return response.data?.data;
    },
  });
}

export function usePipelineHealth() {
  return useQuery({
    queryKey: INTELLIGENCE_KEYS.pipelineHealth(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/intelligence/pipeline/health');
      return response.data?.data;
    },
  });
}

export function useFailureTrends() {
  return useQuery({
    queryKey: INTELLIGENCE_KEYS.failureTrends(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/intelligence/pipeline/trends');
      return response.data?.data;
    },
  });
}

// === Revenue ===
export function useRevenueForecast() {
  return useQuery({
    queryKey: INTELLIGENCE_KEYS.forecast(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/intelligence/revenue/forecast');
      return response.data?.data;
    },
  });
}

export function useChurnRisks() {
  return useQuery({
    queryKey: INTELLIGENCE_KEYS.churnRisks(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/intelligence/revenue/churn_risks');
      return response.data?.data;
    },
  });
}

export function useHealthScores() {
  return useQuery({
    queryKey: INTELLIGENCE_KEYS.healthScores(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/intelligence/revenue/health_scores');
      return response.data?.data;
    },
  });
}

// === BaaS ===
export function useUsageAnomalies() {
  return useQuery({
    queryKey: INTELLIGENCE_KEYS.usageAnomalies(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/intelligence/baas/usage_anomalies');
      return response.data?.data;
    },
  });
}

export function useTenantChurn() {
  return useQuery({
    queryKey: INTELLIGENCE_KEYS.tenantChurn(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/intelligence/baas/tenant_churn');
      return response.data?.data;
    },
  });
}

export function usePricingRecommendations() {
  return useQuery({
    queryKey: INTELLIGENCE_KEYS.pricingRecs(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/intelligence/baas/pricing_recommendations');
      return response.data?.data;
    },
  });
}

export function useApiFraud() {
  return useQuery({
    queryKey: INTELLIGENCE_KEYS.apiFraud(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/intelligence/baas/api_fraud');
      return response.data?.data;
    },
  });
}

// === Reseller ===
export function usePerformanceScores() {
  return useQuery({
    queryKey: INTELLIGENCE_KEYS.performanceScores(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/intelligence/reseller/performance_scores');
      return response.data?.data;
    },
  });
}

export function useCommissionOptimization() {
  return useQuery({
    queryKey: INTELLIGENCE_KEYS.commissionOpt(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/intelligence/reseller/commission_optimization');
      return response.data?.data;
    },
  });
}

export function useReferralChurnRisks() {
  return useQuery({
    queryKey: INTELLIGENCE_KEYS.referralChurn(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/intelligence/reseller/referral_churn_risks');
      return response.data?.data;
    },
  });
}

// === Reviews ===
export function useSentimentAnalysis() {
  return useMutation({
    mutationFn: async (params: { review_id: string }) => {
      const response = await apiClient.post('/ai/intelligence/reviews/sentiment_analysis', params);
      return response.data?.data;
    },
  });
}

export function useSpamDetection() {
  return useQuery({
    queryKey: INTELLIGENCE_KEYS.spamDetection(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/intelligence/reviews/spam_detection');
      return response.data?.data;
    },
  });
}

export function useGenerateResponse() {
  return useMutation({
    mutationFn: async (params: { review_id: string }) => {
      const response = await apiClient.post('/ai/intelligence/reviews/generate_response', params);
      return response.data?.data;
    },
  });
}

export function useAgentQuality() {
  return useQuery({
    queryKey: INTELLIGENCE_KEYS.agentQuality(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/intelligence/reviews/agent_quality');
      return response.data?.data;
    },
  });
}

// === Notifications ===
export function useSmartRouting() {
  return useMutation({
    mutationFn: async (params: { notification_id: string }) => {
      const response = await apiClient.post('/ai/intelligence/notifications/smart_routing', params);
      return response.data?.data;
    },
  });
}

export function useFatigueAnalysis(userId?: string) {
  return useQuery({
    queryKey: INTELLIGENCE_KEYS.fatigueAnalysis(userId),
    queryFn: async () => {
      const response = await apiClient.get('/ai/intelligence/notifications/fatigue_analysis', { params: { user_id: userId } });
      return response.data?.data;
    },
    enabled: !!userId,
  });
}

export function useDigestRecommendations() {
  return useQuery({
    queryKey: INTELLIGENCE_KEYS.digestRecs(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/intelligence/notifications/digest_recommendations');
      return response.data?.data;
    },
  });
}

// === Monitoring ===
export function usePredictiveFailure(serviceName?: string) {
  return useQuery({
    queryKey: INTELLIGENCE_KEYS.predictiveFailure(serviceName),
    queryFn: async () => {
      const response = await apiClient.get('/ai/intelligence/monitoring/predictive_failure', { params: { service_name: serviceName } });
      return response.data?.data;
    },
  });
}

export function useSelfHealing() {
  return useQuery({
    queryKey: INTELLIGENCE_KEYS.selfHealing(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/intelligence/monitoring/self_healing');
      return response.data?.data;
    },
  });
}

export function useSlaBreach() {
  return useQuery({
    queryKey: INTELLIGENCE_KEYS.slaBreachRisk(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/intelligence/monitoring/sla_breach_risk');
      return response.data?.data;
    },
  });
}
