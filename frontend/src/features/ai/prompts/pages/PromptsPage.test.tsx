import { screen, fireEvent } from '@testing-library/react';
import { render } from '@/test-utils';
import { PromptsPage } from './PromptsPage';

// fc-43 review F5: the page's Refresh must refetch the list the user sees.
// The wrapper used to run its own usePromptTemplates() — a hidden second
// instance — and wire Refresh to that one.

const mockVisibleRefresh = jest.fn();
const mockOtherRefresh = jest.fn();
const mockHookCalls: unknown[] = [];

// Stable return values: the page's effects depend on them.
const mockTemplates: unknown[] = [];
const mockStable = {
  createTemplate: jest.fn(),
  updateTemplate: jest.fn(),
  deleteTemplate: jest.fn(),
  duplicateTemplate: jest.fn(),
  previewTemplate: jest.fn(),
  cloneTemplate: jest.fn(),
  previewUpdateFromSource: jest.fn(),
  applyUpdateFromSource: jest.fn(),
};

jest.mock('../hooks/usePromptTemplates', () => ({
  usePromptTemplates: (options?: unknown) => {
    mockHookCalls.push(options);
    return {
      ...mockStable,
      templates: mockTemplates,
      loading: false,
      refresh: options ? mockVisibleRefresh : mockOtherRefresh,
    };
  },
}));

describe('PromptsPage', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockHookCalls.length = 0;
  });

  it('is titled Prompts, matching its sidebar item', () => {
    render(<PromptsPage />);

    expect(screen.getByRole('heading', { name: 'Prompts' })).toBeInTheDocument();
  });

  it('Refresh refetches the visible template list, and there is only that one list', () => {
    render(<PromptsPage />);

    fireEvent.click(screen.getByRole('button', { name: /refresh/i }));

    expect(mockVisibleRefresh).toHaveBeenCalledTimes(1);
    expect(mockOtherRefresh).not.toHaveBeenCalled();
    expect(mockHookCalls.every((o) => o !== undefined)).toBe(true);
  });
});
