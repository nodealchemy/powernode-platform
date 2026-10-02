import React, { useState } from 'react';
import { ShieldAlert } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Checkbox } from '@/shared/components/ui/Checkbox';
import { Textarea } from '@/shared/components/ui/Textarea';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useMcpSecurityServers, useUpdateMcpServerSecurity } from '../hooks/useMcpServer';
import type { McpSecurityServer, McpServerSecurity } from '../types';

// IMP-cdda895b07a8 — the stdio sandbox capabilities (allow_network,
// allow_extended_commands, egress_allowlist) of each stdio MCP server. Visible
// to mcp.servers.read; editable only with mcp.servers.security_manage (a
// permission, never a role). The server's own validations are the rules, so
// this form shows their message verbatim instead of re-implementing them; the
// one client-side rule is the mutual exclusion, only to avoid a round trip.
// See docs/operations/mcp-stdio-sandbox.md.

export const SECURITY_MANAGE_PERMISSION = 'mcp.servers.security_manage';

const parseAllowlist = (text: string): string[] =>
  text
    .split(/[\n,]/)
    .map((entry) => entry.trim())
    .filter((entry) => entry.length > 0);

const errorMessage = (error: unknown): string => {
  const response = (error as { response?: { data?: { error?: string; errors?: unknown } } })?.response?.data;
  if (typeof response?.error === 'string') return response.error;
  if (Array.isArray(response?.errors)) return response.errors.map(String).join('; ');
  if (response?.errors && typeof response.errors === 'object') {
    return Object.values(response.errors as Record<string, unknown>).flat().map(String).join('; ');
  }
  return error instanceof Error ? error.message : 'Failed to update sandbox settings';
};

interface EditorProps {
  server: McpSecurityServer;
  onClose: () => void;
}

const SecurityEditor: React.FC<EditorProps> = ({ server, onClose }) => {
  const update = useUpdateMcpServerSecurity();
  const { addNotification } = useNotifications();
  const [allowNetwork, setAllowNetwork] = useState(server.security.allow_network);
  const [allowExtended, setAllowExtended] = useState(server.security.allow_extended_commands);
  const [allowlistText, setAllowlistText] = useState(server.security.egress_allowlist.join('\n'));
  const [error, setError] = useState<string | null>(null);

  const allowlist = parseAllowlist(allowlistText);
  const conflict = allowNetwork && allowlist.length > 0;

  const handleSave = async () => {
    setError(null);
    try {
      await update.mutateAsync({
        serverId: server.id,
        security: { allow_network: allowNetwork, allow_extended_commands: allowExtended, egress_allowlist: allowlist },
      });
      addNotification({ type: 'success', message: `Sandbox settings saved for ${server.name}` });
      onClose();
    } catch (e) {
      setError(errorMessage(e));
    }
  };

  return (
    <div className="mt-3 space-y-4 rounded-md border border-theme bg-theme-background p-4" data-testid={`security-editor-${server.id}`}>
      <p className="flex items-start gap-2 text-xs text-theme-secondary">
        <ShieldAlert size={14} className="mt-0.5 shrink-0 text-theme-warning-fg" />
        <span>
          These widen what a sandboxed child may do. Every change is audited and applies to the next spawn of this server.
        </span>
      </p>

      <Checkbox
        label="Allow network access"
        description="Unrestricted outbound network, except loopback, link-local, the cloud metadata address and this host's own addresses. Prefer an egress allowlist."
        checked={allowNetwork}
        onCheckedChange={setAllowNetwork}
      />

      <Textarea
        label="Egress allowlist"
        description="One hostname, IP or CIDR per line (at most 20). The child may reach only these. Cannot be combined with allow network."
        value={allowlistText}
        onChange={(e) => setAllowlistText(e.target.value)}
        rows={4}
      />

      <Checkbox
        label="Allow extended commands"
        description="Widens only the command whitelist for this server's launcher; argument checks and package pinning still apply."
        checked={allowExtended}
        onCheckedChange={setAllowExtended}
      />

      {conflict && (
        <p role="alert" className="text-sm text-theme-warning-fg">
          Allow network and an egress allowlist cannot both be set. Clear one of them.
        </p>
      )}
      {error && (
        <p role="alert" className="text-sm text-theme-error-fg">
          {error}
        </p>
      )}

      <div className="flex gap-2">
        <Button size="sm" onClick={handleSave} disabled={conflict || update.isPending} loading={update.isPending}>
          Save
        </Button>
        <Button size="sm" variant="outline" onClick={onClose} disabled={update.isPending}>
          Cancel
        </Button>
      </div>
    </div>
  );
};

const Summary: React.FC<{ security: McpServerSecurity }> = ({ security }) => {
  const parts: string[] = [];
  if (security.allow_network) parts.push('Network: unrestricted (host and metadata denied)');
  else if (security.egress_allowlist.length > 0) parts.push(`Network: allowlist (${security.egress_allowlist.length})`);
  else parts.push('Network: none');
  parts.push(`Extended commands: ${security.allow_extended_commands ? 'allowed' : 'no'}`);
  return <span className="text-sm text-theme-secondary">{parts.join(' · ')}</span>;
};

export const McpSecurityTab: React.FC = () => {
  const { data: servers, isLoading, error } = useMcpSecurityServers();
  const { hasPermission } = usePermissions();
  const canManage = hasPermission(SECURITY_MANAGE_PERMISSION);
  const [editingId, setEditingId] = useState<string | null>(null);

  if (isLoading) {
    return <div className="p-8 text-center text-theme-secondary">Loading sandbox settings...</div>;
  }
  if (error) {
    return <div className="p-8 text-center text-theme-error-fg">Failed to load MCP servers.</div>;
  }

  return (
    <div className="space-y-4">
      <p className="text-sm text-theme-secondary">
        Sandbox settings for stdio MCP servers: network access, the egress allowlist and extended commands.
        {canManage ? '' : ' You can view these settings; changing them needs the "Set a stdio MCP server\'s sandbox capabilities" permission.'}
      </p>

      {!servers || servers.length === 0 ? (
        <div className="rounded-lg border border-theme bg-theme-surface px-4 py-8 text-center text-theme-tertiary">
          No stdio MCP servers.
        </div>
      ) : (
        <ul className="divide-y divide-theme overflow-hidden rounded-lg border border-theme bg-theme-surface">
          {servers.map((server) => (
            <li key={server.id} className="px-4 py-3" data-testid={`security-row-${server.id}`}>
              <div className="flex items-center justify-between gap-4">
                <div className="min-w-0">
                  <div className="font-medium text-theme-primary">{server.name}</div>
                  <div className="truncate font-mono text-xs text-theme-tertiary">{server.command || '—'}</div>
                  <Summary security={server.security} />
                  {server.security.egress_allowlist.length > 0 && (
                    <div className="mt-1 font-mono text-xs text-theme-tertiary">{server.security.egress_allowlist.join(', ')}</div>
                  )}
                </div>
                {canManage && editingId !== server.id && (
                  <Button size="sm" variant="outline" onClick={() => setEditingId(server.id)}>
                    Edit
                  </Button>
                )}
              </div>
              {canManage && editingId === server.id && (
                <SecurityEditor server={server} onClose={() => setEditingId(null)} />
              )}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
};

export default McpSecurityTab;
