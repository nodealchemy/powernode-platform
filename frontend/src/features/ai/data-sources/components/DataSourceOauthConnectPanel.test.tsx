import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { DataSourceOauthConnectPanel, oauthConnectPanelNav } from './DataSourceOauthConnectPanel';
import { dataSourcesApi } from '@/shared/services/ai/DataSourcesApiService';
import type { AiDataSource, AiDataSourceCredential } from '@/shared/types/ai';

// x-com-provider campaign (I5): coverage for the OAuth2 connect panel — the
// core UX this increment adds (client_id/secret form, redirect_uri + copy,
// Authorize navigation, connected-state display), gated on auth_config and
// on the manage permission.

jest.mock('@/shared/services/ai/DataSourcesApiService', () => ({
  dataSourcesApi: {
    authorizeOauth: jest.fn(),
    createCredential: jest.fn(),
    updateCredential: jest.fn(),
  },
}));

const mockAddNotification = jest.fn();
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: mockAddNotification }),
}));

const mockedApi = dataSourcesApi as unknown as {
  authorizeOauth: jest.Mock;
  createCredential: jest.Mock;
  updateCredential: jest.Mock;
};

const baseDataSource: AiDataSource = {
  id: 'ds-1',
  account_id: 'acct-1',
  name: 'X.com',
  slug: 'x-com',
  source_type: 'x_com',
  description: 'X.com data source',
  api_base_url: 'https://api.x.example.com',
  capabilities: [],
  configuration: {},
  rate_limits: {},
  default_parameters: {},
  metadata: {},
  is_active: true,
  requires_auth: true,
  priority_order: 1,
  health_status: 'unknown',
  credential_count: 0,
  created_at: '2026-01-01T00:00:00Z',
  updated_at: '2026-01-01T00:00:00Z',
  auth_config: { authorize_url: 'https://x.example.com/i/oauth2/authorize', token_url: 'https://api.x.example.com/2/oauth2/token' },
  credentials: [],
};

const baseCredential: AiDataSourceCredential = {
  id: 'cred-1',
  name: 'X.com OAuth App',
  is_active: true,
  is_default: true,
  consecutive_failures: 0,
  success_count: 0,
  failure_count: 0,
  created_at: '2026-01-01T00:00:00Z',
  updated_at: '2026-01-01T00:00:00Z',
};

describe('DataSourceOauthConnectPanel', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockedApi.authorizeOauth.mockResolvedValue({
      authorization_url: 'https://x.example.com/i/oauth2/authorize?state=abc',
      redirect_uri: 'https://app.example.com/api/v1/ai/data_sources/ds-1/oauth/callback',
      state: 'abc',
    });
  });

  it('renders nothing when the data source has no auth_config.authorize_url', () => {
    const { container } = render(
      <DataSourceOauthConnectPanel
        dataSource={{ ...baseDataSource, auth_config: {} }}
        canManage
        onCredentialsChanged={jest.fn()}
      />
    );

    expect(container).toBeEmptyDOMElement();
  });

  it('shows the client ID/secret form when no OAuth app credential is configured yet', () => {
    render(
      <DataSourceOauthConnectPanel dataSource={baseDataSource} canManage onCredentialsChanged={jest.fn()} />
    );

    expect(screen.getByLabelText('Client ID')).toBeInTheDocument();
    expect(screen.getByLabelText('Client Secret')).toBeInTheDocument();
    expect(screen.getByText('Not connected')).toBeInTheDocument();
  });

  it('hides the client ID/secret form and management controls for a user without the manage permission', () => {
    render(
      <DataSourceOauthConnectPanel dataSource={baseDataSource} canManage={false} onCredentialsChanged={jest.fn()} />
    );

    expect(screen.queryByLabelText('Client ID')).not.toBeInTheDocument();
    expect(screen.queryByText(/Authorize with the Provider/)).not.toBeInTheDocument();
  });

  it('creates a new credential with the entered client_id/client_secret when none exists yet', async () => {
    mockedApi.createCredential.mockResolvedValue({});
    const onCredentialsChanged = jest.fn();

    render(
      <DataSourceOauthConnectPanel dataSource={baseDataSource} canManage onCredentialsChanged={onCredentialsChanged} />
    );

    fireEvent.change(screen.getByLabelText('Client ID'), { target: { value: 'my-client-id' } });
    fireEvent.change(screen.getByLabelText('Client Secret'), { target: { value: 'my-client-secret' } });
    fireEvent.click(screen.getByText('Save App Credentials'));

    await waitFor(() => expect(mockedApi.createCredential).toHaveBeenCalledWith('ds-1', {
      name: 'X.com OAuth App',
      is_active: true,
      client_id: 'my-client-id',
      client_secret: 'my-client-secret',
    }));
    expect(onCredentialsChanged).toHaveBeenCalled();
  });

  it('fetches the redirect_uri/authorization_url once an OAuth credential is configured', async () => {
    const dataSource = {
      ...baseDataSource,
      credentials: [{ ...baseCredential, oauth_configured: true }],
    };

    render(<DataSourceOauthConnectPanel dataSource={dataSource} canManage onCredentialsChanged={jest.fn()} />);

    await waitFor(() => expect(mockedApi.authorizeOauth).toHaveBeenCalledWith('ds-1', 'cred-1'));
    expect(await screen.findByDisplayValue(
      'https://app.example.com/api/v1/ai/data_sources/ds-1/oauth/callback'
    )).toBeInTheDocument();
  });

  it('copies the redirect_uri to the clipboard', async () => {
    Object.assign(navigator, { clipboard: { writeText: jest.fn() } });
    const dataSource = {
      ...baseDataSource,
      credentials: [{ ...baseCredential, oauth_configured: true }],
    };

    render(<DataSourceOauthConnectPanel dataSource={dataSource} canManage onCredentialsChanged={jest.fn()} />);

    await screen.findByDisplayValue('https://app.example.com/api/v1/ai/data_sources/ds-1/oauth/callback');
    fireEvent.click(screen.getByTitle('Copy redirect URI'));

    expect(navigator.clipboard.writeText).toHaveBeenCalledWith(
      'https://app.example.com/api/v1/ai/data_sources/ds-1/oauth/callback'
    );
    expect(mockAddNotification).toHaveBeenCalledWith(expect.objectContaining({ type: 'success' }));
  });

  it('navigates the browser to the authorization_url when "Authorize" is clicked', async () => {
    // jsdom locks window.location/assign down as non-configurable, so the
    // component routes navigation through oauthConnectPanelNav — spy on that.
    const navigateSpy = jest.spyOn(oauthConnectPanelNav, 'navigate').mockImplementation(() => {});

    const dataSource = {
      ...baseDataSource,
      credentials: [{ ...baseCredential, oauth_configured: true }],
    };

    render(<DataSourceOauthConnectPanel dataSource={dataSource} canManage onCredentialsChanged={jest.fn()} />);

    const authorizeButton = await screen.findByText(/Authorize with the Provider/);
    fireEvent.click(authorizeButton);

    expect(navigateSpy).toHaveBeenCalledWith('https://x.example.com/i/oauth2/authorize?state=abc');
  });

  it('shows the connected state with scopes and expiry, and offers "Reconnect"', async () => {
    const dataSource = {
      ...baseDataSource,
      credentials: [{
        ...baseCredential,
        oauth_configured: true,
        oauth_connected: true,
        oauth_scopes: ['tweet.read', 'tweet.write'],
        oauth_token_expires_at: '2026-01-02T00:00:00Z',
        oauth_token_expired: false,
      }],
    };

    render(<DataSourceOauthConnectPanel dataSource={dataSource} canManage onCredentialsChanged={jest.fn()} />);

    expect(screen.getByText('Connected')).toBeInTheDocument();
    expect(screen.getByText('tweet.read')).toBeInTheDocument();
    expect(screen.getByText('tweet.write')).toBeInTheDocument();
    expect(await screen.findByText(/Reconnect with the Provider/)).toBeInTheDocument();
  });

  it('shows a token-expired warning when oauth_token_expired is true', () => {
    const dataSource = {
      ...baseDataSource,
      credentials: [{
        ...baseCredential,
        oauth_configured: true,
        oauth_connected: true,
        oauth_token_expired: true,
      }],
    };

    render(<DataSourceOauthConnectPanel dataSource={dataSource} canManage onCredentialsChanged={jest.fn()} />);

    expect(screen.getByText('Token expired')).toBeInTheDocument();
  });
});
