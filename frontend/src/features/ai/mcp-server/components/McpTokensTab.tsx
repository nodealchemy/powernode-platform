import React, { useState } from 'react';
import { Plus, Trash2, Copy, Check, Key } from 'lucide-react';
import { useMcpTokens, useCreateMcpToken, useRevokeMcpToken } from '../hooks/useMcpServer';
import { useNotifications } from '@/shared/hooks/useNotifications';
import type { McpTokenCreateResponse } from '../types';

export const McpTokensTab: React.FC = () => {
  const { data: tokens, isLoading } = useMcpTokens();
  const createToken = useCreateMcpToken();
  const revokeToken = useRevokeMcpToken();
  const { addNotification } = useNotifications();

  const [showCreateModal, setShowCreateModal] = useState(false);
  const [tokenName, setTokenName] = useState('');
  const [createdToken, setCreatedToken] = useState<McpTokenCreateResponse | null>(null);
  const [copied, setCopied] = useState(false);
  const [revokeConfirmId, setRevokeConfirmId] = useState<string | null>(null);

  const handleCreate = async () => {
    if (!tokenName.trim()) return;
    try {
      const result = await createToken.mutateAsync({ name: tokenName.trim() });
      setCreatedToken(result);
      setTokenName('');
      addNotification({ type: 'success', message: 'MCP token created' });
    } catch {
      addNotification({ type: 'error', message: 'Failed to create token' });
    }
  };

  const handleCopy = async (text: string) => {
    await navigator.clipboard.writeText(text);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const handleRevoke = async (id: string) => {
    try {
      await revokeToken.mutateAsync(id);
      setRevokeConfirmId(null);
      addNotification({ type: 'success', message: 'Token revoked' });
    } catch {
      addNotification({ type: 'error', message: 'Failed to revoke token' });
    }
  };

  const formatDate = (date: string | null) => {
    if (!date) return 'Never';
    return new Date(date).toLocaleDateString(undefined, {
      month: 'short', day: 'numeric', year: 'numeric',
      hour: '2-digit', minute: '2-digit',
    });
  };

  if (isLoading) {
    return <div className="text-theme-secondary p-8 text-center">Loading tokens...</div>;
  }

  return (
    <div className="space-y-6">
      {/* Created token display (shown once after creation) */}
      {createdToken && (
        <div className="rounded-lg border border-theme-success/30 bg-theme-success/5 p-4">
          <div className="flex items-start justify-between">
            <div>
              <h3 className="text-sm font-medium text-theme-primary">Token Created Successfully</h3>
              <p className="mt-1 text-xs text-theme-secondary">
                Copy this token now — it won't be shown again.
              </p>
              <code className="mt-2 block rounded bg-theme-tertiary px-3 py-2 text-sm font-mono text-theme-primary break-all">
                {createdToken.token}
              </code>
            </div>
            <div className="flex gap-2 ml-4">
              <button
                onClick={() => handleCopy(createdToken.token)}
                className="inline-flex items-center gap-1 rounded px-3 py-1.5 text-xs bg-theme-primary text-theme-inverse hover:bg-theme-primary-hover"
              >
                {copied ? <Check size={14} /> : <Copy size={14} />}
                {copied ? 'Copied' : 'Copy'}
              </button>
              <button
                onClick={() => setCreatedToken(null)}
                className="rounded px-3 py-1.5 text-xs bg-theme-tertiary text-theme-secondary hover:bg-theme-secondary"
              >
                Dismiss
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Create token section */}
      {showCreateModal ? (
        <div className="rounded-lg border border-theme-border bg-theme-secondary p-4">
          <h3 className="text-sm font-medium text-theme-primary mb-3">Generate New MCP Token</h3>
          <div className="flex gap-3">
            <input
              type="text"
              value={tokenName}
              onChange={(e) => setTokenName(e.target.value)}
              placeholder="Token name (e.g., 'Claude Code')"
              className="flex-1 rounded border border-theme-border bg-theme-primary px-3 py-2 text-sm text-theme-primary placeholder-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-accent"
              onKeyDown={(e) => e.key === 'Enter' && handleCreate()}
            />
            <button
              onClick={handleCreate}
              disabled={createToken.isPending || !tokenName.trim()}
              className="inline-flex items-center gap-1 rounded px-4 py-2 text-sm bg-theme-accent text-white hover:bg-theme-accent-hover disabled:opacity-50"
            >
              <Key size={14} />
              Generate
            </button>
            <button
              onClick={() => { setShowCreateModal(false); setTokenName(''); }}
              className="rounded px-4 py-2 text-sm bg-theme-tertiary text-theme-secondary hover:bg-theme-secondary"
            >
              Cancel
            </button>
          </div>
        </div>
      ) : (
        <div className="flex justify-end">
          <button
            onClick={() => setShowCreateModal(true)}
            className="inline-flex items-center gap-1.5 rounded px-4 py-2 text-sm bg-theme-accent text-white hover:bg-theme-accent-hover"
          >
            <Plus size={14} />
            Generate Token
          </button>
        </div>
      )}

      {/* Token list */}
      <div className="overflow-hidden rounded-lg border border-theme-border">
        <table className="w-full text-sm">
          <thead className="bg-theme-secondary">
            <tr className="text-left text-theme-secondary">
              <th className="px-4 py-3 font-medium">Name</th>
              <th className="px-4 py-3 font-medium">Token</th>
              <th className="px-4 py-3 font-medium">Created</th>
              <th className="px-4 py-3 font-medium">Last Used</th>
              <th className="px-4 py-3 font-medium">Expires</th>
              <th className="px-4 py-3 font-medium">Status</th>
              <th className="px-4 py-3 font-medium">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-theme-border">
            {(!tokens || tokens.length === 0) ? (
              <tr>
                <td colSpan={7} className="px-4 py-8 text-center text-theme-tertiary">
                  No MCP tokens yet. Generate one to connect external MCP clients.
                </td>
              </tr>
            ) : (
              tokens.map((token) => (
                <tr key={token.id} className="bg-theme-primary hover:bg-theme-secondary/50">
                  <td className="px-4 py-3 text-theme-primary font-medium">{token.name}</td>
                  <td className="px-4 py-3 font-mono text-xs text-theme-secondary">{token.masked_token}</td>
                  <td className="px-4 py-3 text-theme-secondary">{formatDate(token.created_at)}</td>
                  <td className="px-4 py-3 text-theme-secondary">{formatDate(token.last_used_at)}</td>
                  <td className="px-4 py-3 text-theme-secondary">{formatDate(token.expires_at)}</td>
                  <td className="px-4 py-3">
                    <span className={`inline-flex rounded-full px-2 py-0.5 text-xs font-medium ${
                      token.revoked
                        ? 'bg-theme-error/10 text-theme-error'
                        : 'bg-theme-success/10 text-theme-success'
                    }`}>
                      {token.revoked ? 'Revoked' : 'Active'}
                    </span>
                  </td>
                  <td className="px-4 py-3">
                    {!token.revoked && (
                      revokeConfirmId === token.id ? (
                        <div className="flex items-center gap-2">
                          <button
                            onClick={() => handleRevoke(token.id)}
                            className="rounded px-2 py-1 text-xs bg-theme-error text-white hover:bg-theme-error-hover"
                          >
                            Confirm
                          </button>
                          <button
                            onClick={() => setRevokeConfirmId(null)}
                            className="rounded px-2 py-1 text-xs bg-theme-tertiary text-theme-secondary"
                          >
                            Cancel
                          </button>
                        </div>
                      ) : (
                        <button
                          onClick={() => setRevokeConfirmId(token.id)}
                          className="inline-flex items-center gap-1 rounded px-2 py-1 text-xs text-theme-error hover:bg-theme-error/10"
                        >
                          <Trash2 size={12} />
                          Revoke
                        </button>
                      )
                    )}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      {/* Connection guide */}
      <McpConnectionGuide />
    </div>
  );
};

const McpConnectionGuide: React.FC = () => {
  const [expanded, setExpanded] = useState(false);
  const [guideCopied, setGuideCopied] = useState(false);

  const endpointUrl = `${window.location.origin}/api/v1/mcp/message`;

  const configSnippet = JSON.stringify({
    "mcpServers": {
      "powernode": {
        "url": endpointUrl,
        "headers": {
          "Authorization": "Bearer pnmcp_YOUR_TOKEN_HERE"
        }
      }
    }
  }, null, 2);

  const handleCopyConfig = async () => {
    await navigator.clipboard.writeText(configSnippet);
    setGuideCopied(true);
    setTimeout(() => setGuideCopied(false), 2000);
  };

  return (
    <div className="rounded-lg border border-theme-border bg-theme-secondary">
      <button
        onClick={() => setExpanded(!expanded)}
        className="flex w-full items-center justify-between px-4 py-3 text-sm font-medium text-theme-primary hover:bg-theme-tertiary/50"
      >
        <span>How to connect MCP clients</span>
        <span className="text-theme-tertiary">{expanded ? '−' : '+'}</span>
      </button>
      {expanded && (
        <div className="border-t border-theme-border px-4 py-4 space-y-4">
          <div>
            <h4 className="text-sm font-medium text-theme-primary mb-1">Endpoint URL</h4>
            <code className="block rounded bg-theme-tertiary px-3 py-2 text-xs font-mono text-theme-primary">
              {endpointUrl}
            </code>
          </div>
          <div>
            <div className="flex items-center justify-between mb-1">
              <h4 className="text-sm font-medium text-theme-primary">Claude Code / Cursor config</h4>
              <button
                onClick={handleCopyConfig}
                className="inline-flex items-center gap-1 text-xs text-theme-accent hover:text-theme-accent-hover"
              >
                {guideCopied ? <Check size={12} /> : <Copy size={12} />}
                {guideCopied ? 'Copied' : 'Copy'}
              </button>
            </div>
            <pre className="rounded bg-theme-tertiary px-3 py-2 text-xs font-mono text-theme-primary overflow-x-auto">
              {configSnippet}
            </pre>
          </div>
          <p className="text-xs text-theme-tertiary">
            Replace <code className="font-mono">YOUR_TOKEN_HERE</code> with the token generated above.
            The token includes the <code className="font-mono">pnmcp_</code> prefix.
          </p>
        </div>
      )}
    </div>
  );
};
