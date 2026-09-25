import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { apiClient } from '@/shared/services/apiClient';
import { RecommendationsContent } from './RecommendationsDashboard';
import { TrajectoryInsights } from './TrajectoryInsights';

jest.mock('@/shared/services/apiClient', () => ({
  apiClient: { get: jest.fn(), post: jest.fn() },
}));

jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: jest.fn() }),
}));

const mockGet = apiClient.get as jest.Mock;
const mockPost = apiClient.post as jest.Mock;

// fc-39: these components called apiClient inline. They now go through
// learningApi; the fixtures are the real { success, data } envelope, so a
// component that read the raw axios body again would render nothing.
describe('learning components read through learningApi', () => {
  beforeEach(() => {
    mockGet.mockReset();
    mockPost.mockReset();
  });

  it('RecommendationsContent lists a pending recommendation and applies it', async () => {
    mockGet.mockResolvedValue({
      data: {
        success: true,
        data: {
          recommendations: [
            {
              id: 'rec-1',
              recommendation_type: 'provider_switch',
              target_type: '',
              target_id: '',
              current_config: {},
              recommended_config: {},
              evidence: { suggestion: 'Switch to the cheaper provider' },
              confidence_score: 0.8,
              status: 'pending',
              created_at: '2026-09-25T00:00:00Z',
            },
          ],
        },
      },
    });
    mockPost.mockResolvedValue({ data: { success: true, data: { recommendation: { id: 'rec-1' } } } });

    render(
      <MemoryRouter>
        <RecommendationsContent />
      </MemoryRouter>
    );

    expect(await screen.findByText('Switch to the cheaper provider')).toBeInTheDocument();
    expect(mockGet).toHaveBeenCalledWith('/ai/learning/recommendations');

    fireEvent.click(screen.getByText('Apply'));
    await waitFor(() => expect(mockPost).toHaveBeenCalledWith('/ai/learning/recommendations/rec-1/apply'));
  });

  it('TrajectoryInsights renders cache metrics from the unwrapped envelope', async () => {
    mockGet.mockImplementation((url: string) =>
      Promise.resolve(
        url === '/ai/learning/cache_metrics'
          ? { data: { success: true, data: { metrics: { hits: 42, misses: 8, hit_rate: 84, estimated_savings_usd: 1.5 } } } }
          : { data: { success: true, data: { trends: [] } } }
      )
    );

    render(
      <MemoryRouter>
        <TrajectoryInsights />
      </MemoryRouter>
    );

    expect(await screen.findByText('84%')).toBeInTheDocument();
    expect(screen.getByText('42')).toBeInTheDocument();
  });
});
