import React from 'react';
import { render, screen, fireEvent, waitFor, within } from '@testing-library/react';
import { MemoryRouter, Routes, Route } from 'react-router-dom';

const mockAddNotification = jest.fn();
const mockGetAlerts = jest.fn();
const mockAcknowledgeAlert = jest.fn();
const mockResolveAlert = jest.fn();

jest.mock('@/shared/components/layout/PageContainer', () => ({
  PageContainer: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
}));
jest.mock('@/shared/hooks/usePermissions', () => ({
  usePermissions: () => ({
    hasPermission: (p: string) => ['ai.aiops.read', 'ai.aiops.manage'].includes(p),
  }),
}));
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: mockAddNotification }),
}));
jest.mock('@/shared/services/ai/MonitoringApiService', () => ({
  monitoringApi: {
    getAlerts: (...args: unknown[]) => mockGetAlerts(...args),
    acknowledgeAlert: (...args: unknown[]) => mockAcknowledgeAlert(...args),
    resolveAlert: (...args: unknown[]) => mockResolveAlert(...args),
  },
}));
jest.mock('@/shared/components/error/AiErrorBoundary', () => ({
  AiErrorBoundary: ({ children }: { children: React.ReactNode }) => <>{children}</>,
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

const ALERT_ID = '019f0000-0000-7000-8000-000000000001';

const apiAlert = (overrides: Record<string, unknown> = {}) => ({
  id: ALERT_ID,
  alert_type: 'high_latency',
  severity: 'critical',
  message: 'Alert triggered: High latency',
  timestamp: '2026-09-24T10:00:00Z',
  acknowledged: false,
  resolved: false,
  ...overrides,
});

async function renderAlertsShowingAll() {
  render(
    <MemoryRouter initialEntries={['/app/ai/operations/alerts']}>
      <Routes>
        <Route path="/app/ai/operations/*" element={<OperationsPage />} />
      </Routes>
    </MemoryRouter>,
  );
  await screen.findByText('Alert triggered: High latency');
  // Show every status so the row stays visible once its status changes.
  fireEvent.change(screen.getByDisplayValue('Active'), { target: { value: 'all' } });
}

const confirmInModal = (label: string) =>
  fireEvent.click(within(screen.getByRole('dialog')).getByRole('button', { name: label }));

describe('OperationsPage alert actions', () => {
  beforeEach(() => {
    mockGetAlerts.mockResolvedValue([apiAlert()]);
  });

  it('acknowledges through the API and updates the row', async () => {
    mockAcknowledgeAlert.mockResolvedValue(
      apiAlert({ acknowledged: true, acknowledged_at: '2026-09-24T10:05:00Z' }),
    );
    await renderAlertsShowingAll();

    fireEvent.click(screen.getByRole('button', { name: /^Acknowledge$/ }));
    confirmInModal('Acknowledge Alert');

    await waitFor(() => expect(mockAcknowledgeAlert).toHaveBeenCalledWith(ALERT_ID, undefined));
    expect(await screen.findByText('Acknowledged', { selector: 'span' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /^Acknowledge$/ })).not.toBeInTheDocument();
    expect(mockGetAlerts).toHaveBeenCalledTimes(1);
  });

  it('resolves through the API with the note and updates the row', async () => {
    mockResolveAlert.mockResolvedValue(
      apiAlert({ resolved: true, resolved_at: '2026-09-24T10:06:00Z' }),
    );
    await renderAlertsShowingAll();

    fireEvent.click(screen.getByRole('button', { name: /^Resolve$/ }));
    fireEvent.change(screen.getByPlaceholderText('Add a note about this resolve...'), {
      target: { value: 'restarted provider' },
    });
    confirmInModal('Resolve Alert');

    await waitFor(() => expect(mockResolveAlert).toHaveBeenCalledWith(ALERT_ID, 'restarted provider'));
    expect(await screen.findByText('Resolved', { selector: 'span' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /^Resolve$/ })).not.toBeInTheDocument();
  });

  it('reports a failed acknowledge and leaves the row unchanged', async () => {
    mockAcknowledgeAlert.mockRejectedValue(new Error('Alert not found'));
    await renderAlertsShowingAll();

    fireEvent.click(screen.getByRole('button', { name: /^Acknowledge$/ }));
    confirmInModal('Acknowledge Alert');

    await waitFor(() =>
      expect(mockAddNotification).toHaveBeenCalledWith(
        expect.objectContaining({ type: 'error', message: 'Alert not found' }),
      ),
    );
    expect(screen.getByRole('button', { name: /^Acknowledge$/ })).toBeInTheDocument();
  });
});
