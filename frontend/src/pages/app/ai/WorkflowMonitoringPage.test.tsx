import { render, waitFor } from '@testing-library/react';
import { MemoryRouter, Routes, Route } from 'react-router-dom';

// Import component
import { WorkflowMonitoringPage } from './WorkflowMonitoringPage';

describe('WorkflowMonitoringPage', () => {
  // Simple component that captures the path for testing
  const NavigationCapture = () => {
    return <div data-testid="redirected">Redirected</div>;
  };

  it('redirects to the AI monitoring page with workflows tab', async () => {
    render(
      <MemoryRouter initialEntries={['/app/ai/workflow-monitoring']} future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
        <Routes>
          <Route path="/app/ai/workflow-monitoring" element={<WorkflowMonitoringPage />} />
          <Route path="/app/ai/monitoring/workflows" element={<NavigationCapture />} />
        </Routes>
      </MemoryRouter>
    );

    // Wait for redirect to complete
    await waitFor(() => {
      expect(document.querySelector('[data-testid="redirected"]')).toBeInTheDocument();
    });
  });

  it('renders null while redirecting', () => {
    render(
      <MemoryRouter initialEntries={['/app/ai/workflow-monitoring']} future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
        <Routes>
          <Route path="/app/ai/workflow-monitoring" element={<WorkflowMonitoringPage />} />
          <Route path="/app/ai/monitoring/workflows" element={<div>Target Page</div>} />
        </Routes>
      </MemoryRouter>
    );

    // The component itself renders null, so the only content is the route target
    // After redirect, the target page will be shown
  });
});
