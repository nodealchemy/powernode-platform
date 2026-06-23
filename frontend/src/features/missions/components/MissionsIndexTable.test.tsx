import { fireEvent } from '@testing-library/react';
import type { ReactElement } from 'react';
import { renderWithProviders, mockAuthenticatedState } from '@/shared/utils/test-utils';
import { MissionsIndexTable } from './MissionsIndexTable';
import type { Mission } from '../types/mission';

// Regression: the sort pills (Updated/Created/Name) toggled sortBy/sortOrder
// state and highlighted, but filteredMissions only filtered and never sorted
// (sortBy/sortOrder weren't even in its deps), so row order never changed.
//
// Fixture ordering is deliberately scrambled so each sort yields a DISTINCT order:
//   API order:        Mike, Zeta, Alpha
//   updated_at desc:   Zeta(01-03), Alpha(01-02), Mike(01-01)
//   name asc:          Alpha, Mike, Zeta
//   name desc:         Zeta, Mike, Alpha
const mockMissions = [
  { id: '1', name: 'Mike', mission_type: 'feature', status: 'active', created_at: '2026-01-02T00:00:00Z', updated_at: '2026-01-01T00:00:00Z' },
  { id: '2', name: 'Zeta', mission_type: 'feature', status: 'active', created_at: '2026-01-01T00:00:00Z', updated_at: '2026-01-03T00:00:00Z' },
  { id: '3', name: 'Alpha', mission_type: 'feature', status: 'active', created_at: '2026-01-03T00:00:00Z', updated_at: '2026-01-02T00:00:00Z' },
] as unknown as Mission[];

jest.mock('../hooks/useMissions', () => ({
  useMissions: () => ({ missions: mockMissions, loading: false, hasManagePermission: false }),
}));

jest.mock('@/shared/hooks/useMissionModal', () => ({
  useMissionModal: () => ({ openMission: jest.fn() }),
}));

const render = (ui: ReactElement) =>
  renderWithProviders(ui, { preloadedState: mockAuthenticatedState });

const NAMES = ['Alpha', 'Mike', 'Zeta'];

const renderProps = {
  onNewMission: () => {},
  onStartMission: () => {},
  onPauseMission: () => {},
  onCancelMission: () => {},
  onApproveMission: () => {},
};

// Read the mission names in rendered row order.
function orderedNames(container: HTMLElement): string[] {
  return Array.from(container.querySelectorAll('tbody tr'))
    .map((row) => NAMES.find((n) => row.textContent?.includes(n)))
    .filter((n): n is string => Boolean(n));
}

describe('MissionsIndexTable sorting', () => {
  it('applies the default sort (updated_at desc) to the rendered rows', () => {
    const { container } = render(<MissionsIndexTable {...renderProps} />);
    expect(orderedNames(container)).toEqual(['Zeta', 'Alpha', 'Mike']);
  });

  it('reorders rows when the Name pill is toggled (desc then asc)', () => {
    const { container, getByRole } = render(<MissionsIndexTable {...renderProps} />);

    // First click on a new key -> name desc
    fireEvent.click(getByRole('button', { name: 'Name' }));
    expect(orderedNames(container)).toEqual(['Zeta', 'Mike', 'Alpha']);

    // Second click toggles to asc
    fireEvent.click(getByRole('button', { name: 'Name' }));
    expect(orderedNames(container)).toEqual(['Alpha', 'Mike', 'Zeta']);
  });
});
