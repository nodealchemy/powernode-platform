import React from 'react';
import { Routes, Route, Navigate } from 'react-router-dom';
import { HardDrive, Server, Boxes } from 'lucide-react';
import { SubNavRail } from '@/shared/components/navigation/SubNavRail';
import { PathTabSpec, firstAccessibleTabPath } from '@/shared/components/navigation/PathTabs';
import { ProtectedRoute } from '@/shared/components/ui/ProtectedRoute';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { DockerHubPage } from '@/pages/app/devops/DockerHubPage';
import { SwarmHubPage } from '@/pages/app/devops/SwarmHubPage';
import { KubernetesHubPage } from '@/pages/app/devops/KubernetesHubPage';
import { HostProvider } from '@/features/devops/docker/context/HostContext';
import { ClusterProvider } from '@/features/devops/swarm/context/ClusterContext';
import { HostDashboardPage } from '@/features/devops/docker/pages/HostDashboardPage';
import { ContainerDetailPage } from '@/features/devops/docker/pages/ContainerDetailPage';
import { ClusterDashboardPage } from '@/features/devops/swarm/pages/ClusterDashboardPage';
import { SwarmNodesPage } from '@/features/devops/swarm/pages/SwarmNodesPage';
import { SwarmServiceDetailPage } from '@/features/devops/swarm/pages/SwarmServiceDetailPage';

/**
 * ContainersHubPage — the single DevOps home for container runtimes: Docker,
 * Swarm and Kubernetes. (Sandboxes live once, under AI › Execution —
 * /app/ai/execution/containers — so they are not a leaf here.) Follows the Cost hub's pattern
 * (pages/app/ai/CostPage.tsx): ONE vertical SubNavRail whose leaves are
 * path-addressable under `/app/devops/containers/<leaf>`.
 *
 * Each leaf is the existing page, mounted as-is — it keeps its own
 * PageContainer (title, breadcrumbs, actions) and its own tab row, so the
 * hub adds only the rail and never a second header. Each leaf also keeps its
 * own permission gate: the rail hides a leaf the user can't read, and the
 * ProtectedRoute below refuses it when reached by URL.
 */

export const CONTAINERS_BASE = '/app/devops/containers';

/** Rail items. Permissions match each leaf's own route gate. */
export const CONTAINERS_NAV: PathTabSpec[] = [
  { key: 'docker', label: 'Docker', permission: 'devops.docker.read', icon: <HardDrive size={16} /> },
  { key: 'swarm', label: 'Swarm', permission: 'devops.swarm.read', icon: <Server size={16} /> },
  { key: 'kubernetes', label: 'Kubernetes', permission: 'devops.kubernetes.read', icon: <Boxes size={16} /> },
];

const gate = (permission: string, element: React.ReactNode) => (
  <ProtectedRoute requiredPermissions={[permission]}>{element}</ProtectedRoute>
);

const docker = (element: React.ReactNode) => gate('devops.docker.read', element);
const swarm = (element: React.ReactNode) => gate('devops.swarm.read', element);

export const ContainersHubPage: React.FC = () => {
  const { hasPermission } = usePermissions();

  const fallback =
    firstAccessibleTabPath(CONTAINERS_NAV, CONTAINERS_BASE, hasPermission) ?? `${CONTAINERS_BASE}/docker`;

  return (
    <SubNavRail
      items={CONTAINERS_NAV}
      basePath={CONTAINERS_BASE}
      hasPermission={hasPermission}
      ariaLabel="Containers navigation"
      title="Containers"
      emptyState={<p className="text-theme-secondary">You do not have permission to view containers.</p>}
    >
      <Routes>
        <Route index element={<Navigate to={fallback} replace />} />

        {/* Docker — static tab routes before :hostId so "containers" etc. never match as an id. */}
        <Route path="docker/containers" element={docker(<DockerHubPage />)} />
        <Route path="docker/images" element={docker(<DockerHubPage />)} />
        <Route path="docker/networks" element={docker(<DockerHubPage />)} />
        <Route path="docker/volumes" element={docker(<DockerHubPage />)} />
        <Route path="docker/monitoring" element={docker(<DockerHubPage />)} />
        <Route
          path="docker/:hostId/containers/:containerId/*"
          element={docker(<HostProvider><ContainerDetailPage /></HostProvider>)}
        />
        <Route path="docker/:hostId" element={docker(<HostProvider><HostDashboardPage /></HostProvider>)} />
        <Route path="docker/*" element={docker(<DockerHubPage />)} />

        {/* Swarm — static tab routes before :clusterId for the same reason. */}
        <Route path="swarm/services" element={swarm(<SwarmHubPage />)} />
        <Route path="swarm/stacks" element={swarm(<SwarmHubPage />)} />
        <Route path="swarm/networks" element={swarm(<SwarmHubPage />)} />
        <Route path="swarm/secrets" element={swarm(<SwarmHubPage />)} />
        <Route path="swarm/operations" element={swarm(<SwarmHubPage />)} />
        <Route
          path="swarm/:clusterId/services/:serviceId/*"
          element={swarm(<ClusterProvider><SwarmServiceDetailPage /></ClusterProvider>)}
        />
        <Route path="swarm/:clusterId/nodes" element={swarm(<ClusterProvider><SwarmNodesPage /></ClusterProvider>)} />
        <Route path="swarm/:clusterId" element={swarm(<ClusterProvider><ClusterDashboardPage /></ClusterProvider>)} />
        <Route path="swarm/*" element={swarm(<SwarmHubPage />)} />

        <Route path="kubernetes/*" element={gate('devops.kubernetes.read', <KubernetesHubPage />)} />

        <Route path="*" element={<Navigate to={fallback} replace />} />
      </Routes>
    </SubNavRail>
  );
};

export default ContainersHubPage;
