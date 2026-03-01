import React, { useState, useEffect } from 'react';
import { Server, Box, Loader2 } from 'lucide-react';
import apiClient from '@/shared/services/apiClient';

interface DockerHost {
  id: string;
  name: string;
  status: string;
  container_count: number;
}

interface SwarmCluster {
  id: string;
  name: string;
  status: string;
  service_count: number;
}

interface InfrastructureBindingProps {
  teamId: string;
  selectedHosts: string[];
  selectedClusters: string[];
  onUpdate: (hostIds: string[], clusterIds: string[]) => void;
}

export const InfrastructureBinding: React.FC<InfrastructureBindingProps> = ({
  teamId: _teamId,
  selectedHosts,
  selectedClusters,
  onUpdate
}) => {
  const [hosts, setHosts] = useState<DockerHost[]>([]);
  const [clusters, setClusters] = useState<SwarmCluster[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchInfra = async () => {
      try {
        const [hostsRes, clustersRes] = await Promise.allSettled([
          apiClient.get('/devops/docker_hosts'),
          apiClient.get('/devops/swarm_clusters')
        ]);

        if (hostsRes.status === 'fulfilled') {
          setHosts(hostsRes.value.data?.data || []);
        }
        if (clustersRes.status === 'fulfilled') {
          setClusters(clustersRes.value.data?.data || []);
        }
      } catch {
        // Silently handle
      } finally {
        setLoading(false);
      }
    };
    fetchInfra();
  }, []);

  const toggleHost = (hostId: string) => {
    const newHosts = selectedHosts.includes(hostId)
      ? selectedHosts.filter(id => id !== hostId)
      : [...selectedHosts, hostId];
    onUpdate(newHosts, selectedClusters);
  };

  const toggleCluster = (clusterId: string) => {
    const newClusters = selectedClusters.includes(clusterId)
      ? selectedClusters.filter(id => id !== clusterId)
      : [...selectedClusters, clusterId];
    onUpdate(selectedHosts, newClusters);
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center py-6">
        <Loader2 className="h-5 w-5 animate-spin text-theme-primary" />
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* Docker Hosts */}
      <div>
        <h4 className="text-sm font-medium text-theme-primary mb-2 flex items-center gap-2">
          <Box className="h-4 w-4" />
          Docker Hosts
        </h4>
        {hosts.length === 0 ? (
          <p className="text-xs text-theme-secondary">No Docker hosts available</p>
        ) : (
          <div className="space-y-2">
            {hosts.map(host => (
              <label
                key={host.id}
                className={`flex items-center gap-3 p-3 border rounded-lg cursor-pointer transition-colors ${
                  selectedHosts.includes(host.id)
                    ? 'border-theme-primary bg-theme-primary/5'
                    : 'border-theme hover:bg-theme-surface-hover'
                }`}
              >
                <input
                  type="checkbox"
                  checked={selectedHosts.includes(host.id)}
                  onChange={() => toggleHost(host.id)}
                  className="rounded border-theme text-theme-primary focus:ring-theme-primary"
                />
                <div className="flex-1">
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-medium text-theme-primary">{host.name}</span>
                    <span className={`h-2 w-2 rounded-full ${
                      host.status === 'connected' ? 'bg-theme-success' : 'bg-theme-danger-solid'
                    }`} />
                  </div>
                  <span className="text-xs text-theme-secondary">{host.container_count} containers</span>
                </div>
              </label>
            ))}
          </div>
        )}
      </div>

      {/* Swarm Clusters */}
      <div>
        <h4 className="text-sm font-medium text-theme-primary mb-2 flex items-center gap-2">
          <Server className="h-4 w-4" />
          Swarm Clusters
        </h4>
        {clusters.length === 0 ? (
          <p className="text-xs text-theme-secondary">No Swarm clusters available</p>
        ) : (
          <div className="space-y-2">
            {clusters.map(cluster => (
              <label
                key={cluster.id}
                className={`flex items-center gap-3 p-3 border rounded-lg cursor-pointer transition-colors ${
                  selectedClusters.includes(cluster.id)
                    ? 'border-theme-primary bg-theme-primary/5'
                    : 'border-theme hover:bg-theme-surface-hover'
                }`}
              >
                <input
                  type="checkbox"
                  checked={selectedClusters.includes(cluster.id)}
                  onChange={() => toggleCluster(cluster.id)}
                  className="rounded border-theme text-theme-primary focus:ring-theme-primary"
                />
                <div className="flex-1">
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-medium text-theme-primary">{cluster.name}</span>
                    <span className={`h-2 w-2 rounded-full ${
                      cluster.status === 'active' ? 'bg-theme-success' : 'bg-theme-danger-solid'
                    }`} />
                  </div>
                  <span className="text-xs text-theme-secondary">{cluster.service_count} services</span>
                </div>
              </label>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};
