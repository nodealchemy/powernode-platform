import { render, waitFor } from '@testing-library/react';
import App from './App';
import { api } from '@/shared/services/api';

// ESM-only markdown plugins reached through the page imports; babel-jest does
// not transform them, and the boot path never renders markdown.
jest.mock('remark-gfm', () => () => ({}));
jest.mock('remark-breaks', () => () => ({}));
jest.mock('rehype-highlight', () => () => ({}));
jest.mock('rehype-raw', () => () => ({}));
// The chat surfaces pull in the ESM-only a2ui SDK; the boot path renders
// neither, so stub them to keep that tree out of the module graph.
jest.mock('@/pages/app/DashboardPage', () => ({ DashboardPage: () => null }));
jest.mock('@/features/ai/chat/pages/DetachedChatPage', () => ({ DetachedChatPage: () => null }));
// The '@/assets/…' alias maps ahead of the css stub mapper, so these would
// otherwise be parsed as JS.
jest.mock('@/assets/styles/themes.css', () => ({}));
jest.mock('@/assets/styles/public-theme.css', () => ({}));
jest.mock('@/assets/styles/deprecated-css-override.css', () => ({}));

jest.mock('@/shared/services/api', () => ({
  api: {
    get: jest.fn(),
    post: jest.fn(),
    interceptors: { request: { use: jest.fn() }, response: { use: jest.fn() } },
  },
}));

describe('App boot', () => {
  it('fetches the public platform config on boot, before any user is authenticated', async () => {
    (api.get as jest.Mock).mockResolvedValue({ data: { success: true, data: { features: {} } } });
    (api.post as jest.Mock).mockRejectedValue(new Error('no refresh cookie'));

    render(<App />);

    await waitFor(() => expect(api.get).toHaveBeenCalledWith('/config'));
  });
});
