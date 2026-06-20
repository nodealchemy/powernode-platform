import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { SeedStep } from './SeedStep';
import type { SetupStep } from '../services/setupApi';

jest.mock('../services/setupApi', () => ({
  __esModule: true,
  setupApi: { seed: jest.fn() },
}));

import { setupApi } from '../services/setupApi';

const mockSeed = setupApi.seed as jest.Mock;

const step: SetupStep = {
  key: 'seed',
  title: 'Example data',
  order: 90,
  owner: 'core',
  required: false,
  component: 'core/seed',
  completed: false,
  completed_at: null,
};

describe('SeedStep', () => {
  beforeEach(() => mockSeed.mockReset());

  it('seeds and reports success', async () => {
    mockSeed.mockResolvedValue({ seeded: true });
    render(<SeedStep step={step} />);

    fireEvent.click(screen.getByTestId('setup-seed-btn'));
    await waitFor(() => expect(screen.getByTestId('setup-seed-btn')).toHaveTextContent('Seeded'));
  });

  it('reports nothing-to-seed when no seeder is present', async () => {
    mockSeed.mockResolvedValue({ seeded: false, reason: 'no_seeder' });
    render(<SeedStep step={step} />);

    fireEvent.click(screen.getByTestId('setup-seed-btn'));
    await waitFor(() => expect(screen.getByTestId('setup-seed-empty')).toBeInTheDocument());
  });
});
