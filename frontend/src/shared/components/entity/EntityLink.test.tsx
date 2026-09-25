import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import { MemoryRouter, Routes, Route, useLocation } from 'react-router-dom';
import { EntityLink } from './EntityLink';
import { entityRegistry } from '@/shared/services/entityRegistry';
import { registerCoreEntities } from '@/shared/entity/registerCoreEntities';

const mockHasPermission = jest.fn();
jest.mock('@/shared/hooks/usePermissions', () => ({
  usePermissions: () => ({ hasPermission: mockHasPermission }),
}));

const LocationProbe: React.FC = () => {
  const location = useLocation();
  return <div data-testid="location">{`${location.pathname}${location.search}`}</div>;
};

const renderAt = (ui: React.ReactElement, path = '/app/ai/control/approvals') =>
  render(
    <MemoryRouter initialEntries={[path]}>
      <Routes>
        <Route
          path="*"
          element={
            <>
              {ui}
              <LocationProbe />
            </>
          }
        />
      </Routes>
    </MemoryRouter>,
  );

// fc-43: an agent reference opens the one agent detail page, not the deleted
// global AgentDetailModal (`?agent=`). Teams and missions keep their own
// url-param modals; that mode is unchanged.
describe('EntityLink', () => {
  beforeEach(() => {
    entityRegistry.clear();
    registerCoreEntities();
    mockHasPermission.mockReset();
  });

  it.each(['agent', 'ai_agent'])('%s navigates to /app/ai/agents/:id and never sets ?agent=', (type) => {
    mockHasPermission.mockReturnValue(true);
    renderAt(<EntityLink type={type} id="a-1" label="Planner" />);

    fireEvent.click(screen.getByText('Planner'));

    expect(screen.getByTestId('location')).toHaveTextContent(/^\/app\/ai\/agents\/a-1$/);
  });

  it('renders the agent link as a real link to the detail page', () => {
    mockHasPermission.mockReturnValue(true);
    renderAt(<EntityLink type="agent" id="a-1" label="Planner" />);

    expect(screen.getByRole('link', { name: 'Planner' })).toHaveAttribute('href', '/app/ai/agents/a-1');
  });

  it('degrades the agent link to plain text without ai.agents.read', () => {
    mockHasPermission.mockImplementation((p: string) => p !== 'ai.agents.read');
    renderAt(<EntityLink type="agent" id="a-1" label="Planner" />);

    expect(screen.queryByRole('link')).not.toBeInTheDocument();
    expect(screen.queryByRole('button')).not.toBeInTheDocument();
    expect(screen.getByText('Planner').tagName).toBe('SPAN');
  });

  it('does not let the click bubble to a row handler', () => {
    mockHasPermission.mockReturnValue(true);
    const onRowClick = jest.fn();
    renderAt(
      <div onClick={onRowClick}>
        <EntityLink type="agent" id="a-1" label="Planner" />
      </div>,
    );

    fireEvent.click(screen.getByText('Planner'));

    expect(onRowClick).not.toHaveBeenCalled();
  });

  it.each([
    ['agent_team', 'team'],
    ['mission', 'mission'],
  ])('%s still opens its own url-param modal (?%s=)', (type, param) => {
    mockHasPermission.mockReturnValue(true);
    renderAt(<EntityLink type={type} id="x-9" label="Target" />);

    fireEvent.click(screen.getByText('Target'));

    expect(screen.getByTestId('location')).toHaveTextContent(`/app/ai/control/approvals?${param}=x-9`);
  });
});
