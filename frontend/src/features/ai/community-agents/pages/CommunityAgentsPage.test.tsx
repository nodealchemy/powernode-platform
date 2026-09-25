import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { Provider } from 'react-redux';
import { configureStore } from '@reduxjs/toolkit';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { CommunityAgentsContent } from './CommunityAgentsPage';

// Mock child components
jest.mock('../components/AgentDiscovery', () => ({
  AgentDiscovery: ({ onInvokeAgent, onSelectAgent }: { onInvokeAgent?: (agent: { id: string; name: string }) => void; onSelectAgent?: (agent: { id: string; name: string }) => void }) => (
    <div data-testid="agent-discovery">
      Agent Discovery Component
      <button data-testid="invoke-agent-btn" onClick={() => onInvokeAgent?.({ id: 'agent-1', name: 'Test Agent' })}>
        Invoke Agent
      </button>
      <button data-testid="select-agent-btn" onClick={() => onSelectAgent?.({ id: 'agent-1', name: 'Test Agent' })}>
        View Details
      </button>
    </div>
  ),
}));

jest.mock('../components/FederationPartnerList', () => ({
  FederationPartnerList: ({ onSelectPartner, onCreatePartner }: { onSelectPartner?: (partner: { id: string; name: string }) => void; onCreatePartner?: () => void }) => (
    <div data-testid="federation-partner-list">
      Federation Partner List
      <button data-testid="select-partner-btn" onClick={() => onSelectPartner?.({ id: 'partner-1', name: 'Test Partner' })}>
        Select Partner
      </button>
      <button data-testid="create-partner-btn" onClick={onCreatePartner}>
        Create Partner
      </button>
    </div>
  ),
}));

const LocationProbe = () => {
  const location = useLocation();
  return <div data-testid="location-probe">{location.pathname}</div>;
};

const createTestStore = () =>
  configureStore({
    reducer: {
      auth: (state = { user: null, isAuthenticated: false }) => state,
      ui: (state = { notifications: [] }) => state,
    },
  });

const renderAt = (path: string, props = {}) =>
  render(
    <Provider store={createTestStore()}>
      <MemoryRouter initialEntries={[path]}>
        <CommunityAgentsContent {...props} />
        <LocationProbe />
      </MemoryRouter>
    </Provider>
  );

describe('CommunityAgentsContent path tabs', () => {
  it('lands on Discover by default', () => {
    renderAt('/app/ai/agents/community');
    expect(screen.getByTestId('agent-discovery')).toBeInTheDocument();
    expect(screen.queryByTestId('federation-partner-list')).not.toBeInTheDocument();
  });

  it('deep-links directly to Federation', () => {
    renderAt('/app/ai/agents/community/federation');
    expect(screen.getByTestId('federation-partner-list')).toBeInTheDocument();
    expect(screen.queryByTestId('agent-discovery')).not.toBeInTheDocument();
  });

  it('updates the URL when a tab is clicked', async () => {
    renderAt('/app/ai/agents/community');
    fireEvent.click(screen.getByText('Agent Federation'));

    await waitFor(() =>
      expect(screen.getByTestId('location-probe')).toHaveTextContent('/app/ai/agents/community/federation')
    );
    expect(screen.getByTestId('federation-partner-list')).toBeInTheDocument();
  });

  describe('callbacks', () => {
    it('calls onInvokeAgent when agent is invoked', () => {
      const onInvokeAgent = jest.fn();
      renderAt('/app/ai/agents/community', { onInvokeAgent });

      fireEvent.click(screen.getByTestId('invoke-agent-btn'));

      expect(onInvokeAgent).toHaveBeenCalledWith(expect.objectContaining({ id: 'agent-1', name: 'Test Agent' }));
    });

    it('calls onViewAgentDetails when agent details is requested', () => {
      const onViewAgentDetails = jest.fn();
      renderAt('/app/ai/agents/community', { onViewAgentDetails });

      fireEvent.click(screen.getByTestId('select-agent-btn'));

      expect(onViewAgentDetails).toHaveBeenCalledWith(expect.objectContaining({ id: 'agent-1', name: 'Test Agent' }));
    });

    it('calls onViewPartnerDetails when partner is selected', () => {
      const onViewPartnerDetails = jest.fn();
      renderAt('/app/ai/agents/community/federation', { onViewPartnerDetails });

      fireEvent.click(screen.getByTestId('select-partner-btn'));

      expect(onViewPartnerDetails).toHaveBeenCalledWith(expect.objectContaining({ id: 'partner-1', name: 'Test Partner' }));
    });

    it('opens the create partner modal when create partner is clicked', () => {
      renderAt('/app/ai/agents/community/federation');

      fireEvent.click(screen.getByTestId('create-partner-btn'));

      expect(screen.getByText('Add Federation Partner')).toBeInTheDocument();
    });
  });
});
