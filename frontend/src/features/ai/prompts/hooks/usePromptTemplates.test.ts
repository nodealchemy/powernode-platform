import { renderHook, waitFor } from '@testing-library/react';
import { usePromptTemplates } from './usePromptTemplates';
import { promptsApi } from '../services/promptsApi';
import type { ContentScope } from '@/features/content/scoped';

// Regression: the loadTemplates useCallback dep array enumerated every filter
// param except params?.scope, so changing the ScopeFilter on PromptsPage never
// recreated loadTemplates and the list silently kept the previous scope.
jest.mock('../services/promptsApi', () => ({
  promptsApi: {
    getAll: jest.fn(),
  },
}));

describe('usePromptTemplates scope refetch', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (promptsApi.getAll as jest.Mock).mockResolvedValue({
      prompt_templates: [],
      meta: { total: 0, by_category: {}, by_domain: {} },
    });
  });

  it('refetches when params.scope changes', async () => {
    const { rerender } = renderHook(
      ({ scope }: { scope: ContentScope }) => usePromptTemplates({ scope }),
      { initialProps: { scope: 'all' as ContentScope } },
    );

    await waitFor(() => expect(promptsApi.getAll).toHaveBeenCalledTimes(1));
    expect(promptsApi.getAll).toHaveBeenLastCalledWith({ scope: 'all' });

    rerender({ scope: 'global' as ContentScope });

    await waitFor(() => expect(promptsApi.getAll).toHaveBeenCalledTimes(2));
    expect(promptsApi.getAll).toHaveBeenLastCalledWith({ scope: 'global' });
  });
});
