import { provisioningApi } from './provisioningApi';

const mockGet = jest.fn();
const mockPost = jest.fn();

// Default export, not a named one — provisioningApi imports it that way.
jest.mock('@/shared/services/apiClient', () => ({
  __esModule: true,
  default: {
    get: (...args: unknown[]) => mockGet(...args),
    post: (...args: unknown[]) => mockPost(...args),
  },
}));

describe('provisioningApi platform volumes', () => {
  beforeEach(() => jest.clearAllMocks());

  it('reads the list from the path the shim declares', async () => {
    // The literal is pinned rather than derived: computing it from the client
    // would make the assertion agree by construction and prove nothing.
    mockGet.mockResolvedValue({
      data: {
        data: {
          volumes: [{ id: 'v-1', name: 'pg-data', size_gb: 50 }],
          count: 1,
          has_more: false,
        },
      },
    });

    await expect(provisioningApi.listPlatformVolumes()).resolves.toEqual({
      volumes: [{ id: 'v-1', name: 'pg-data', size_gb: 50 }],
      count: 1,
      hasMore: false,
    });
    expect(mockGet).toHaveBeenCalledWith('/system/platform/volumes');
  });

  it('carries the envelope that says the page is partial', async () => {
    // paginated_result defaults to 100 rows and reports the uncapped total, so
    // a caller that drops count and has_more presents a partial list as if it
    // were the whole account.
    mockGet.mockResolvedValue({
      data: { data: { volumes: [{ id: 'v-1' }], count: 340, has_more: true } },
    });

    await expect(provisioningApi.listPlatformVolumes()).resolves.toMatchObject({
      count: 340,
      hasMore: true,
    });
  });

  it('falls back to the row count when the envelope omits count', async () => {
    mockGet.mockResolvedValue({ data: { data: { volumes: [{ id: 'v-1' }, { id: 'v-2' }] } } });

    await expect(provisioningApi.listPlatformVolumes()).resolves.toMatchObject({
      count: 2,
      hasMore: false,
    });
  });

  it('rejects a body that is not the double envelope rather than reporting none', async () => {
    // render_success wraps the tool payload, so the volumes live at
    // data.data.volumes. Reading one level up would yield [] — and the wizard
    // would state positively that an account full of volumes has none, which
    // is the one answer that causes the duplicate this list prevents.
    mockGet.mockResolvedValue({ data: { volumes: [{ id: 'v-1' }] } });

    await expect(provisioningApi.listPlatformVolumes()).rejects.toThrow(
      'Unexpected volumes response shape',
    );
  });

  it('rejects a payload with no volumes key', async () => {
    mockGet.mockResolvedValue({ data: { data: {} } });

    await expect(provisioningApi.listPlatformVolumes()).rejects.toThrow(
      'Unexpected volumes response shape',
    );
  });

  it('still creates against the same path', async () => {
    mockPost.mockResolvedValue({ data: { data: { volume: { id: 'v-2' } } } });

    await provisioningApi.createPlatformVolume({ name: 'n', size_gb: 1, transport: 'block' });

    expect(mockPost).toHaveBeenCalledWith('/system/platform/volumes', {
      name: 'n',
      size_gb: 1,
      transport: 'block',
    });
  });
});
