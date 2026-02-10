export type SandboxStatus = 'pending' | 'running' | 'paused' | 'completed' | 'failed' | 'cancelled';
export type TrustLevel = 'supervised' | 'monitored' | 'trusted' | 'autonomous';

export interface SandboxInstance {
  id: string;
  execution_id: string;
  agent_id: string;
  agent_name: string;
  status: SandboxStatus;
  trust_level: TrustLevel;
  template_name: string;
  image_name: string;
  image_tag: string;
  sandbox_mode: boolean;
  memory_used_mb?: number;
  cpu_used_millicores?: number;
  storage_used_bytes?: number;
  started_at?: string;
  completed_at?: string;
  created_at: string;
  updated_at: string;
}

export interface SandboxMetrics {
  execution_id: string;
  status: string;
  memory_used_mb?: number;
  cpu_used_millicores?: number;
  storage_used_bytes?: number;
  network_bytes_in?: number;
  network_bytes_out?: number;
  uptime_seconds?: number;
}

export interface SandboxStats {
  total: number;
  running: number;
  paused: number;
  completed: number;
  failed: number;
}
