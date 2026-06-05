import React, { useState, useEffect, useCallback } from 'react';
import { Trash2, ChevronDown, ChevronRight } from 'lucide-react';
import { useMcpSessions, useRevokeMcpSession } from '../hooks/useMcpServer';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { EntityLink } from '@/shared/components/entity';
import type { PageAction } from '@/shared/components/layout/PageContainer';
import type { McpSession } from '../types';

interface McpSessionsTabProps {
  onActionsReady?: (actions: PageAction[]) => void;
}

export const McpSessionsTab: React.FC<McpSessionsTabProps> = ({ onActionsReady }) => {
  const { data: sessions, isLoading, refetch } = useMcpSessions();
  const revokeSession = useRevokeMcpSession();
  const { addNotification } = useNotifications();
  const [revokeConfirmId, setRevokeConfirmId] = useState<string | null>(null);
  const [expandedRows, setExpandedRows] = useState<Set<string>>(new Set());

  const toggleExpand = useCallback((id: string) => {
    setExpandedRows((prev) => {
      const next = new Set(prev);
      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }
      return next;
    });
  }, []);

  useEffect(() => {
    onActionsReady?.([
      {
        label: 'Refresh',
        onClick: () => refetch(),
        variant: 'outline',
      },
    ]);
  }, [onActionsReady, refetch]);

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
      expired: 'bg-theme-background-secondary/20 text-theme-tertiary',
      revoked: 'bg-theme-error/10 text-theme-error',
    };
    return styles[status] || styles.expired;
  };

  const getClientName = (clientInfo: Record<string, unknown>) => {
    if (clientInfo?.name) return String(clientInfo.name);
    return 'Unknown client';
  };

  const getClientVersion = (clientInfo: Record<string, unknown>) => {
    if (clientInfo?.version) return String(clientInfo.version);
    return '—';
  };

  if (isLoading) {
    return <div className="text-theme-secondary p-8 text-center">Loading sessions...</div>;
  }

  return (
    <div className="space-y-4">
      <div className="overflow-hidden rounded-lg bg-theme-surface border border-theme">
        <table className="w-full text-sm">
          <thead className="bg-theme-background border-b border-theme">
            <tr className="text-left">
              <th className="w-8 px-2 py-3" />
              <th className="px-4 py-3 text-xs font-medium text-theme-tertiary uppercase tracking-wider">User</th>
              <th className="px-4 py-3 text-xs font-medium text-theme-tertiary uppercase tracking-wider">Client</th>
              <th className="px-4 py-3 text-xs font-medium text-theme-tertiary uppercase tracking-wider">Protocol</th>
              <th className="px-4 py-3 text-xs font-medium text-theme-tertiary uppercase tracking-wider">IP</th>
              <th className="px-4 py-3 text-xs font-medium text-theme-tertiary uppercase tracking-wider">Last Activity</th>
              <th className="px-4 py-3 text-xs font-medium text-theme-tertiary uppercase tracking-wider">Status</th>
              <th className="px-4 py-3 text-xs font-medium text-theme-tertiary uppercase tracking-wider">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-theme">
            {(!sessions || sessions.length === 0) ? (
              <tr>
                <td colSpan={8} className="px-4 py-8 text-center text-theme-tertiary">
                  No active MCP sessions.
                </td>
              </tr>
            ) : (
              sessions.map((session) => {
                const isExpanded = expandedRows.has(session.id);
                return (
                  <React.Fragment key={session.id}>
                    <tr
                      className="hover:bg-theme-surface transition-colors cursor-pointer"
                      onClick={() => toggleExpand(session.id)}
                    >
                      <td className="px-2 py-3">
                        <button
                          type="button"
                          onClick={(e) => { e.stopPropagation(); toggleExpand(session.id); }}
                          className="p-1 text-theme-secondary hover:text-theme-primary"
                          aria-label={isExpanded ? 'Collapse session detail' : 'Expand session detail'}
                        >
                          {isExpanded ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
                        </button>
                      </td>
                      <td className="px-4 py-3 text-theme-primary font-medium">
                        <EntityLink type="user" id={session.user_id} label={session.user_name} />
                      </td>
                      <td className="px-4 py-3 text-theme-secondary">{getClientName(session.client_info)}</td>
                      <td className="px-4 py-3 font-mono text-xs text-theme-secondary">{session.protocol_version}</td>
                      <td className="px-4 py-3 font-mono text-xs text-theme-secondary">{session.ip_address || '—'}</td>
                      <td className="px-4 py-3 text-theme-secondary">{formatDate(session.last_activity_at)}</td>
                      <td className="px-4 py-3">
                        <span className={`inline-flex rounded-full px-2 py-0.5 text-xs font-medium ${getStatusBadge(session.status)}`}>
                          {session.status}
                        </span>
                      </td>
                      <td className="px-4 py-3" onClick={(e) => e.stopPropagation()}>
                        {session.status === 'active' && (
                          revokeConfirmId === session.id ? (
                            <div className="flex items-center gap-2">
                              <button
                                onClick={() => handleRevoke(session.id)}
                                className="rounded px-2 py-1 text-xs bg-theme-error text-white hover:bg-theme-error"
                              >
                                Confirm
                              </button>
                              <button
                                onClick={() => setRevokeConfirmId(null)}
                                className="rounded px-2 py-1 text-xs bg-theme-background text-theme-secondary"
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
                    {isExpanded && (
                      <SessionExpandedRow session={session} clientVersion={getClientVersion(session.client_info)} formatDate={formatDate} />
                    )}
                  </React.Fragment>
                );
              })
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
};

interface SessionExpandedRowProps {
  session: McpSession;
  clientVersion: string;
  formatDate: (date: string | null) => string;
}

const SessionExpandedRow: React.FC<SessionExpandedRowProps> = ({ session, clientVersion, formatDate }) => (
  <tr className="bg-theme-background border-b border-theme">
    <td className="px-2 py-3" />
    <td colSpan={7} className="px-4 py-3">
      <div className="grid grid-cols-2 md:grid-cols-3 gap-3 text-sm">
        <DetailField label="User">
          <EntityLink type="user" id={session.user_id} label={session.user_name} />
        </DetailField>
        <DetailField label="Client Version">{clientVersion}</DetailField>
        <DetailField label="Protocol">{session.protocol_version}</DetailField>
        <DetailField label="IP Address">{session.ip_address || '—'}</DetailField>
        <DetailField label="Last Activity">{formatDate(session.last_activity_at)}</DetailField>
        <DetailField label="Created">{formatDate(session.created_at)}</DetailField>
        <DetailField label="Expires">{formatDate(session.expires_at)}</DetailField>
        <DetailField label="Session ID">
          <span className="font-mono text-xs break-all">{session.id}</span>
        </DetailField>
        <DetailField label="User Agent" className="col-span-2 md:col-span-3">
          <span className="break-all">{session.user_agent || '—'}</span>
        </DetailField>
      </div>
    </td>
  </tr>
);

const DetailField: React.FC<{ label: string; className?: string; children: React.ReactNode }> = ({ label, className, children }) => (
  <div className={className}>
    <div className="text-xs font-medium text-theme-tertiary uppercase tracking-wider mb-0.5">{label}</div>
    <div className="text-theme-primary">{children}</div>
  </div>
);
