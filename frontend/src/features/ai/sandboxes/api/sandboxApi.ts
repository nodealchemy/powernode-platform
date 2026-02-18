import { apiClient } from '@/shared/services/apiClient';
import type { SandboxInstance, SandboxMetrics, SandboxStats } from '../types/sandbox';

export const fetchSandboxes = async (): Promise<SandboxInstance[]> => {
  const response = await apiClient.get('/ai/container_sandboxes');
  return response.data?.sandboxes || [];
};

export const fetchSandbox = async (id: string): Promise<SandboxInstance> => {
  const response = await apiClient.get(`/ai/container_sandboxes/${id}`);
  return response.data?.sandbox;
};

export const fetchSandboxMetrics = async (id: string): Promise<SandboxMetrics> => {
  const response = await apiClient.get(`/ai/container_sandboxes/${id}/metrics`);
  return response.data?.metrics;
};

export const fetchSandboxStats = async (): Promise<SandboxStats> => {
  const response = await apiClient.get('/ai/container_sandboxes/stats');
  return response.data?.stats;
};

export const createSandbox = async (params: {
  agent_id: string;
  config?: Record<string, unknown>;
}): Promise<SandboxInstance> => {
  const response = await apiClient.post('/ai/container_sandboxes', params);
  return response.data?.sandbox;
};

export const destroySandbox = async (id: string): Promise<void> => {
  await apiClient.delete(`/ai/container_sandboxes/${id}`);
};

export const pauseSandbox = async (id: string): Promise<SandboxInstance> => {
  const response = await apiClient.post(`/ai/container_sandboxes/${id}/pause`);
  return response.data?.sandbox;
};

export const resumeSandbox = async (id: string): Promise<SandboxInstance> => {
  const response = await apiClient.post(`/ai/container_sandboxes/${id}/resume`);
  return response.data?.sandbox;
};
