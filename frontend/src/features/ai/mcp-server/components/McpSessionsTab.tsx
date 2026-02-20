import React, { useState } from 'react';
import { Trash2, RefreshCw } from 'lucide-react';
import { useMcpSessions, useRevokeMcpSession } from '../hooks/useMcpServer';
import { useNotifications } from '@/shared/hooks/useNotifications';

export const McpSessionsTab: React.FC = () => {
  const { data: sessions, isLoading, refetch } = useMcpSessions();
  const revokeSession = useRevokeMcpSession();
  const { addNotification } = useNotifications();
  const [revokeConfirmId, setRevokeConfirmId] = useState<string | null>(null);

  const handleRevoke = async (id: string) => {
    try {
      await revokeSession.mutateAsync(id);
      setRevokeConfirmId(null);
      addNotification({ type: 'success', message: 'Session revoked' });
    } catch {
      addNotification({ type: 'error', message: 'Failed to revoke session' });
    }
  };

  const formatDate = (date: string | null) => {
    if (!date) return '—';
    return new Date(date).toLocaleDateString(undefined, {
      month: 'short', day: 'numeric',
      hour: '2-digit', minute: '2-digit',
    });
  };

  const getStatusBadge = (status: string) => {
    const styles: Record<string, string> = {
      active: 'bg-theme-success/10 text-theme-success',
      expired: 'bg-theme-tertiary/20 text-theme-tertiary',
      revoked: 'bg-theme-error/10 text-theme-error',
    };
    return styles[status] || styles.expired;
  };

  const getClientName = (clientInfo: Record<string, unknown>) => {
    if (clientInfo?.name) return String(clientInfo.name);
    return 'Unknown client';
  };

  if (isLoading) {
    return <div className="text-theme-secondary p-8 text-center">Loading sessions...</div>;
  }

  return (
    <div className="space-y-4">
      <div className="flex justify-end">
        <button
          onClick={() => refetch()}
          className="inline-flex items-center gap-1.5 rounded px-3 py-1.5 text-sm bg-theme-tertiary text-theme-secondary hover:bg-theme-secondary"
        >
          <RefreshCw size={14} />
          Refresh
        </button>
      </div>

      <div className="overflow-hidden rounded-lg border border-theme-border">
        <table className="w-full text-sm">
          <thead className="bg-theme-secondary">
            <tr className="text-left text-theme-secondary">
              <th className="px-4 py-3 font-medium">User</th>
              <th className="px-4 py-3 font-medium">Client</th>
              <th className="px-4 py-3 font-medium">Protocol</th>
              <th className="px-4 py-3 font-medium">IP</th>
              <th className="px-4 py-3 font-medium">Last Activity</th>
              <th className="px-4 py-3 font-medium">Status</th>
              <th className="px-4 py-3 font-medium">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-theme-border">
            {(!sessions || sessions.length === 0) ? (
              <tr>
                <td colSpan={7} className="px-4 py-8 text-center text-theme-tertiary">
                  No active MCP sessions.
                </td>
              </tr>
            ) : (
              sessions.map((session) => (
                <tr key={session.id} className="bg-theme-primary hover:bg-theme-secondary/50">
                  <td className="px-4 py-3 text-theme-primary font-medium">{session.user_name}</td>
                  <td className="px-4 py-3 text-theme-secondary">{getClientName(session.client_info)}</td>
                  <td className="px-4 py-3 font-mono text-xs text-theme-secondary">{session.protocol_version}</td>
                  <td className="px-4 py-3 font-mono text-xs text-theme-secondary">{session.ip_address || '—'}</td>
                  <td className="px-4 py-3 text-theme-secondary">{formatDate(session.last_activity_at)}</td>
                  <td className="px-4 py-3">
                    <span className={`inline-flex rounded-full px-2 py-0.5 text-xs font-medium ${getStatusBadge(session.status)}`}>
                      {session.status}
                    </span>
                  </td>
                  <td className="px-4 py-3">
                    {session.status === 'active' && (
                      revokeConfirmId === session.id ? (
                        <div className="flex items-center gap-2">
                          <button
                            onClick={() => handleRevoke(session.id)}
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
                          onClick={() => setRevokeConfirmId(session.id)}
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
    </div>
  );
};
