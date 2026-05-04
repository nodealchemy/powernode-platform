// Kubernetes Cluster Management Types — Phase 2

export type ClusterFlavor = 'k3s' | 'kubeadm';
export type ClusterEnvironment = 'staging' | 'production' | 'development' | 'custom';
export type ClusterStatus =
  | 'pending'
  | 'bootstrapping'
  | 'active'
  | 'degraded'
  | 'disconnected'
  | 'error';

// k3s vocab (server | agent) AND kubeadm vocab (control_plane | worker)
// coexist in the same column. Use the model's #server? / #worker?
// predicates to ask flavor-aware questions.
export type ClusterNodeRole = 'server' | 'agent' | 'control_plane' | 'worker';
export type ClusterNodeStatus =
  | 'pending'
  | 'joining'
  | 'active'
  | 'not_ready'
  | 'disconnected'
  | 'error';

export interface KubernetesClusterSummary {
  id: string;
  name: string;
  slug: string;
  api_endpoint: string;
  flavor: ClusterFlavor;
  environment: ClusterEnvironment;
  status: ClusterStatus;
  k8s_version: string | null;
  node_count: number;
  pod_count: number;
  auto_sync: boolean;
  last_synced_at: string | null;
  has_kubeconfig: boolean;
}

export interface KubernetesClusterDetail extends KubernetesClusterSummary {
  description: string | null;
  sync_interval_seconds: number;
  consecutive_failures: number;
  metadata: Record<string, unknown>;
  created_at: string;
  updated_at: string;
}

export interface KubernetesNodeSummary {
  id: string;
  kubernetes_cluster_id: string;
  node_instance_id: string;
  name: string;
  role: ClusterNodeRole;
  status: ClusterNodeStatus;
  k8s_version: string | null;
  last_heartbeat_at: string | null;
}

export interface ClusterFilters {
  status?: ClusterStatus;
  flavor?: ClusterFlavor;
  environment?: ClusterEnvironment;
}

export interface NodeFilters {
  role?: ClusterNodeRole;
  status?: ClusterNodeStatus;
}

// API response shapes — matches Rails render_success envelope
// {success:true, data: {...}}.
export interface KubeconfigResponse {
  cluster_id: string;
  api_endpoint: string;
  kubeconfig: string;
}

export interface DecommissionResponse {
  message: string;
  freed_node_count: number;
}
