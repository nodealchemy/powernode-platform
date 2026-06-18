import React from 'react';
import { render, screen } from '@testing-library/react';
import { MemoryRouter, Routes, Route } from 'react-router-dom';

let mockAllowed: string[] = [];

jest.mock('@/shared/components/layout/PageContainer', () => ({
  PageContainer: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
}));
jest.mock('@/shared/hooks/usePermissions', () => ({
  usePermissions: () => ({ hasPermission: (p: string) => mockAllowed.includes(p) }),
}));
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: jest.fn() }),
}));
jest.mock('@/shared/services/ai/MonitoringApiService', () => ({
  monitoringApi: { getAlerts: jest.fn().mockResolvedValue([]) },
}));
jest.mock('@/shared/components/error/AiErrorBoundary', () => ({
  AiErrorBoundary: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));
jest.mock('@/features/ai/monitoring/components/AlertManagementCenter', () => ({
  AlertManagementCenter: () => <div data-testid="alerts-leaf" />,
}));
jest.mock('@/features/ai/aiops/components/AiOpsDashboard', () => ({
  AiOpsContent: () => <div data-testid="aiops-leaf" />,
}));
jest.mock('@/features/ai/aiops', () => ({
  ReliabilitySection: () => <div data-testid="reliability" />,
}));
jest.mock('../ExecutionTracesPage', () => ({
  ExecutionTracesContent: () => <div data-testid="traces-leaf" />,
}));

import { OperationsPage } from '../OperationsPage';

function renderAt(path: string) {
  return render(
    <MemoryRouter initialEntries={[path]}>
      <Routes>
        <Route path="/app/ai/operations/*" element={<OperationsPage />} />
      </Routes>
    </MemoryRouter>,
  );
}

describe('OperationsPage', () => {
  afterEach(() => {
    mockAllowed = [];
  });

  it('renders AIOps / Alerts / Traces tabs when operations are permitted', () => {
    mockAllowed = ['ai.aiops.read', 'ai_monitoring.read'];
    renderAt('/app/ai/operations/aiops');

    expect(screen.getByRole('link', { name: 'AIOps' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Alerts' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Execution Traces' })).toBeInTheDocument();
    expect(screen.getByTestId('aiops-leaf')).toBeInTheDocument();
  });

  it('redirects the hub index to the first accessible tab (AIOps)', () => {
    mockAllowed = ['ai.aiops.read'];
    renderAt('/app/ai/operations');
    expect(screen.getByTestId('aiops-leaf')).toBeInTheDocument();
  });

  it('shows Access Denied when the user lacks operations permissions', () => {
    mockAllowed = [];
    renderAt('/app/ai/operations/aiops');
    expect(screen.getByText('Access Denied')).toBeInTheDocument();
    expect(screen.queryByTestId('aiops-leaf')).not.toBeInTheDocument();
  });
});
