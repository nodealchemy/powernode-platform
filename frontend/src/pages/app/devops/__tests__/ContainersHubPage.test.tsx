import React from 'react';
import { render, screen } from '@testing-library/react';
import { MemoryRouter, Routes, Route } from 'react-router-dom';

// fc-44: Containers is ONE DevOps nav item — a rail hub whose leaves are the
// existing Docker, Swarm and Kubernetes pages, each mounted unchanged under
// /app/devops/containers/<leaf>. Sandboxes live under AI › Execution (fc-32).

let mockGranted: string[] = [];
jest.mock('@/shared/hooks/usePermissions', () => ({
  usePermissions: () => ({ hasPermission: (p: string) => mockGranted.includes(p) }),
}));

// ProtectedRoute reads auth state from Redux; here it only needs to prove the
// hub wraps each leaf in the leaf's own permission gate.
jest.mock('@/shared/components/ui/ProtectedRoute', () => ({
  ProtectedRoute: ({ requiredPermissions = [], children }: { requiredPermissions?: string[]; children: React.ReactNode }) =>
    requiredPermissions.every((p) => mockGranted.includes(p)) ? <>{children}</> : <div data-testid="access-denied" />,
}));

jest.mock('@/pages/app/devops/DockerHubPage', () => ({
  DockerHubPage: () => <div data-testid="docker-leaf" />,
}));
jest.mock('@/pages/app/devops/SwarmHubPage', () => ({
  SwarmHubPage: () => <div data-testid="swarm-leaf" />,
}));
jest.mock('@/pages/app/devops/KubernetesHubPage', () => ({
  KubernetesHubPage: () => <div data-testid="kubernetes-leaf" />,
}));
jest.mock('@/features/devops/docker/context/HostContext', () => ({
  HostProvider: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));
jest.mock('@/features/devops/swarm/context/ClusterContext', () => ({
  ClusterProvider: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));
jest.mock('@/features/devops/docker/pages/HostDashboardPage', () => ({
  HostDashboardPage: () => {
    const { hostId } = jest.requireActual('react-router-dom').useParams();
    return <div data-testid="docker-host">{hostId}</div>;
  },
}));
jest.mock('@/features/devops/docker/pages/ContainerDetailPage', () => ({
  ContainerDetailPage: () => {
    const { hostId, containerId } = jest.requireActual('react-router-dom').useParams();
    return <div data-testid="docker-container">{`${hostId}/${containerId}`}</div>;
  },
}));
jest.mock('@/features/devops/swarm/pages/ClusterDashboardPage', () => ({
  ClusterDashboardPage: () => {
    const { clusterId } = jest.requireActual('react-router-dom').useParams();
    return <div data-testid="swarm-cluster">{clusterId}</div>;
  },
}));
jest.mock('@/features/devops/swarm/pages/SwarmNodesPage', () => ({
  SwarmNodesPage: () => <div data-testid="swarm-nodes" />,
}));
jest.mock('@/features/devops/swarm/pages/SwarmServiceDetailPage', () => ({
  SwarmServiceDetailPage: () => <div data-testid="swarm-service" />,
}));

import { ContainersHubPage } from '../ContainersHubPage';

const ALL = ['devops.docker.read', 'devops.swarm.read', 'devops.kubernetes.read'];

function renderAt(path: string) {
  return render(
    <MemoryRouter initialEntries={[path]}>
      <Routes>
        <Route path="/app/devops/containers/*" element={<ContainersHubPage />} />
      </Routes>
    </MemoryRouter>,
  );
}

describe('ContainersHubPage', () => {
  beforeEach(() => {
    mockGranted = [...ALL];
  });

  it('shows one rail item per container runtime, in order, and no Sandboxes leaf', () => {
    renderAt('/app/devops/containers/docker');

    const rail = screen.getByTestId('sub-nav-rail');
    expect(Array.from(rail.querySelectorAll('a')).map((a) => a.textContent)).toEqual([
      'Docker',
      'Swarm',
      'Kubernetes',
    ]);
    expect(screen.getByTestId('sub-nav-docker')).toHaveAttribute('href', '/app/devops/containers/docker');
  });

  it.each([
    ['docker', 'docker-leaf'],
    ['docker/images', 'docker-leaf'],
    ['swarm', 'swarm-leaf'],
    ['swarm/stacks', 'swarm-leaf'],
    ['kubernetes', 'kubernetes-leaf'],
  ])('renders the existing page at /app/devops/containers/%s', (leafPath, testId) => {
    renderAt(`/app/devops/containers/${leafPath}`);

    expect(screen.getByTestId(testId)).toBeInTheDocument();
  });

  it('routes Docker host and container detail URLs under the hub', () => {
    renderAt('/app/devops/containers/docker/h1');
    expect(screen.getByTestId('docker-host')).toHaveTextContent('h1');
  });

  it('routes a Docker container detail URL under the hub', () => {
    renderAt('/app/devops/containers/docker/h1/containers/c9');
    expect(screen.getByTestId('docker-container')).toHaveTextContent('h1/c9');
  });

  it('routes Swarm cluster detail URLs under the hub', () => {
    renderAt('/app/devops/containers/swarm/k1');
    expect(screen.getByTestId('swarm-cluster')).toHaveTextContent('k1');
  });

  it('opens the first leaf the user can access at the bare hub URL', () => {
    mockGranted = ['devops.swarm.read'];
    renderAt('/app/devops/containers');

    expect(screen.getByTestId('swarm-leaf')).toBeInTheDocument();
    expect(screen.queryByTestId('sub-nav-docker')).not.toBeInTheDocument();
  });

  it('keeps each leaf behind its own permission even when reached by URL', () => {
    mockGranted = ['devops.swarm.read'];
    renderAt('/app/devops/containers/docker');

    expect(screen.queryByTestId('docker-leaf')).not.toBeInTheDocument();
  });
});
