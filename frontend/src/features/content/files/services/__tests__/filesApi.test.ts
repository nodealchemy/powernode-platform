import api from '@/shared/services/api';
import { filesApi } from '../filesApi';

jest.mock('@/shared/services/api', () => ({
  __esModule: true,
  default: { get: jest.fn(), post: jest.fn(), delete: jest.fn() },
}));

const mockGet = api.get as jest.Mock;

// fc-39: extensions attach files to their own records and list them through
// this one /files client, so getFiles takes the attachable filter.
describe('filesApi.getFiles', () => {
  beforeEach(() => mockGet.mockReset());

  it('passes an attachable filter through and unwraps the envelope', async () => {
    const payload = { files: [{ id: 'f1' }], pagination: { current_page: 1, per_page: 20, total_pages: 1, total_count: 1 } };
    mockGet.mockResolvedValue({ data: { success: true, data: payload } });

    const result = await filesApi.getFiles({
      attachable_type: 'Page',
      attachable_id: 'page-1',
      category: 'page_content',
    });

    expect(mockGet).toHaveBeenCalledWith('/files', {
      params: { attachable_type: 'Page', attachable_id: 'page-1', category: 'page_content' },
    });
    expect(result).toEqual(payload);
  });
});
