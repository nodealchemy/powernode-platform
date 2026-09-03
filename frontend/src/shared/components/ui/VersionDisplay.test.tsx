import { render, screen, waitFor } from '@testing-library/react';
import { VersionDisplay } from './VersionDisplay';
import { versionApi } from '@/shared/services/admin/versionApi';

// The footer's display contract: a release build shows its X.Y.Z; an
// incremental build shows the 7-char sha the module build stamped; a build
// with no identity shows "<version>-dev". Both halves (frontend define,
// backend /version payload) follow the same rule.
jest.mock('@/shared/services/api', () => ({ api: { get: jest.fn() } }));

describe('VersionDisplay (simple)', () => {
  afterEach(() => jest.restoreAllMocks());

  const backend = (overrides: Record<string, unknown>) =>
    jest.spyOn(versionApi, 'getVersion').mockResolvedValue({
      success: true,
      data: {
        version: '0.3.1', major: 0, minor: 3, patch: 1, build_date: '2026-09-03T16:00:00Z',
        git_commit: 'unknown', ...overrides,
      },
    } as never);

  it('shows the frontend short sha and the backend short sha for incremental builds', async () => {
    jest.spyOn(versionApi, 'getFrontendBuildInfo').mockReturnValue({
      version: '0.3.1', sha: 'a'.repeat(40), short_sha: 'aaaaaaa', branch: 'develop', tag: null, release: false,
      built_at: '2026-09-03T16:00:00Z', source: 'module-build',
    });
    backend({ display: 'bbbbbbb', short_sha: 'bbbbbbb', git_branch: 'develop', git_tag: null, release: false });

    render(<VersionDisplay show="simple" />);
    await waitFor(() => expect(screen.getByText('Frontend aaaaaaa • Backend bbbbbbb')).toBeInTheDocument());
    expect(screen.getByText('Frontend aaaaaaa • Backend bbbbbbb')).toHaveAttribute('title', expect.stringContaining('a'.repeat(40)));
  });

  it('shows the version only for a release build', async () => {
    jest.spyOn(versionApi, 'getFrontendBuildInfo').mockReturnValue({
      version: '0.3.1', sha: 'c'.repeat(40), short_sha: 'ccccccc', branch: 'master', tag: '0.3.1', release: true,
      built_at: '2026-09-03T16:00:00Z', source: 'module-build',
    });
    backend({ display: '0.3.1', short_sha: 'ddddddd', git_branch: 'master', git_tag: '0.3.1', release: true });

    render(<VersionDisplay show="simple" />);
    await waitFor(() => expect(screen.getByText('Frontend 0.3.1 • Backend 0.3.1')).toBeInTheDocument());
  });

  it('shows <version>-dev when a build carries no identity', async () => {
    jest.spyOn(versionApi, 'getFrontendBuildInfo').mockReturnValue({
      version: '0.3.1', sha: null, short_sha: null, branch: 'unknown', tag: null, release: false,
      built_at: null, source: 'local',
    });
    // An old backend that predates the display contract only sends `version`.
    backend({});

    render(<VersionDisplay show="simple" />);
    await waitFor(() => expect(screen.getByText('Frontend 0.3.1-dev • Backend 0.3.1-dev')).toBeInTheDocument());
  });
});
