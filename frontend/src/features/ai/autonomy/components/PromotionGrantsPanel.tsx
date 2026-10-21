import React, { useMemo, useState } from 'react';
import { KeyRound, AlertTriangle, Plus, Ban } from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useAccountAgentOptions } from '@/shared/hooks/useAccountAgentOptions';
import { getErrorMessage } from '@/shared/utils/apiErrors';
import {
  usePromotionGrants,
  usePromotionGrantOptions,
  useCreatePromotionGrant,
  useRevokePromotionGrant,
} from '../api/autonomyApi';
import type { PromotionGrant, PromotionGrantStatus } from '../types/autonomy';

const MANAGE = 'ai.promotion_grants.manage';
const DEFAULT_PRESETS = [1, 4, 8, 24];

const STATUS_CLASS: Record<PromotionGrantStatus, string> = {
  active: 'bg-theme-success-bg text-theme-success-fg',
  expired: 'bg-theme-surface text-theme-tertiary',
  exhausted: 'bg-theme-surface text-theme-tertiary',
  revoked: 'bg-theme-error-bg text-theme-error-fg',
};

export function formatTimeLeft(seconds: number): string {
  if (seconds <= 0) return '—';
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  return hours > 0 ? `${hours}h ${minutes}m` : `${minutes}m`;
}

/**
 * The create form. Expiry is a preset lifetime, the agent picker lists (and
 * searches, server-side) the account's agents rather than trust scores, which
 * hide MCP-client agents, and the reason is required. A strict plane (the
 * server's `strict` flag: supervised, or tier 3 and up) shows the limits the
 * server enforces there: max uses, at least one module, at most 4 hours.
 */
export const PromotionGrantForm: React.FC<{ onDone: () => void }> = ({ onDone }) => {
  const { data: options, isLoading: optionsLoading } = usePromotionGrantOptions();
  const [agentSearch, setAgentSearch] = useState('');
  const { data: agents } = useAccountAgentOptions({ scope: 'custom', search: agentSearch });
  const createGrant = useCreatePromotionGrant();
  const { addNotification } = useNotifications();

  const [agentId, setAgentId] = useState('');
  const [environmentId, setEnvironmentId] = useState('');
  const [moduleIds, setModuleIds] = useState<string[]>([]);
  const [maxUses, setMaxUses] = useState('');
  const [hours, setHours] = useState(4);
  const [reason, setReason] = useState('');
  const [granterOnly, setGranterOnly] = useState(false);

  const presets = options?.expiry_presets_hours ?? DEFAULT_PRESETS;
  const environment = options?.environments.find((e) => e.id === environmentId);
  const strict = environment?.strict === true;
  const lifetimeLimit = environment?.max_lifetime_hours ?? options?.max_lifetime_hours ?? 24;
  const usesLimit = environment?.max_uses_limit ?? null;
  const effectiveHours = Math.min(hours, lifetimeLimit);
  const usesValue = maxUses ? Number(maxUses) : null;
  const strictBoundsMet = !strict ||
    (usesValue !== null && usesValue >= 1 && (usesLimit === null || usesValue <= usesLimit) && moduleIds.length > 0);
  const grantable = Boolean(options?.required_permission);
  const canSubmit = grantable && agentId && environmentId && reason.trim().length > 0 && strictBoundsMet &&
    !createGrant.isPending;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!canSubmit) return;
    try {
      await createGrant.mutateAsync({
        ai_agent_id: agentId,
        environment_id: environmentId,
        action_category: options?.categories?.[0] ?? 'release.promote',
        module_ids: moduleIds,
        max_uses: usesValue,
        expires_in_hours: effectiveHours,
        reason: reason.trim(),
        granter_driven_only: granterOnly,
      });
      addNotification({ type: 'success', message: 'Promotion grant issued' });
      onDone();
    } catch (error) {
      addNotification({ type: 'error', message: getErrorMessage(error, 'Failed to issue promotion grant') });
    }
  };

  if (optionsLoading) return <LoadingSpinner size="sm" message="Loading..." />;

  const fieldClass = 'w-full px-3 py-1.5 text-sm rounded-md border border-theme bg-theme-surface text-theme-primary';
  const agentList = agents ?? [];

  return (
    <form onSubmit={handleSubmit} className="p-4 bg-theme-background border border-theme rounded-lg space-y-3"
      aria-label="Issue promotion grant">
      {!grantable && (
        <div className="p-3 rounded-md bg-theme-warning-bg text-theme-warning-fg text-sm">
          No installed extension declares a grantable promotion verb, so no grant can be issued here
          (core mode).
        </div>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
        <div className="text-sm text-theme-secondary space-y-1">
          <label className="block space-y-1">
            <span>Search agents</span>
            <input aria-label="Search agents" type="search" value={agentSearch}
              onChange={(e) => setAgentSearch(e.target.value)} placeholder="Name contains..." className={fieldClass} />
          </label>
          <label className="block space-y-1">
            <span>Agent</span>
            <select aria-label="Agent" value={agentId} onChange={(e) => setAgentId(e.target.value)} className={fieldClass}>
              <option value="">Select an agent</option>
              {agentList.map((a) => (
                <option key={a.id} value={a.id}>{a.name}</option>
              ))}
            </select>
          </label>
        </div>
        <label className="text-sm text-theme-secondary space-y-1">
          <span>Environment</span>
          <select aria-label="Environment" value={environmentId} onChange={(e) => setEnvironmentId(e.target.value)}
            className={fieldClass}>
            <option value="">Select an environment</option>
            {(options?.environments ?? []).map((env) => (
              <option key={env.id} value={env.id}>
                {env.name} ({env.slug}){env.is_protected ? ' — protected' : ''}
              </option>
            ))}
          </select>
        </label>
      </div>

      {strict && environment && (
        <div role="alert" className="flex items-start gap-2 p-3 rounded-md bg-theme-error-bg text-theme-error-fg text-sm">
          <AlertTriangle className="h-4 w-4 mt-0.5 shrink-0" />
          <span>
            {environment.name} is a strict plane (tier {environment.tier}
            {environment.is_protected ? ', protected' : ''}). This grant lets the agent promote into it without a
            person approving each promotion. The server allows at most 4 hours, max uses (1-{usesLimit ?? 10}) and
            named modules only.
          </span>
        </div>
      )}
      {!strict && environment?.is_protected && (
        <p className="text-sm text-theme-warning-fg">
          {environment.name} is protected: promotions there normally need a person.
        </p>
      )}

      <label className="block text-sm text-theme-secondary space-y-1">
        <span>Modules ({strict ? 'required' : 'optional — none selected means any module'})</span>
        <select aria-label="Modules" multiple value={moduleIds}
          onChange={(e) => setModuleIds(Array.from(e.target.selectedOptions).map((o) => o.value))}
          className={`${fieldClass} min-h-[6rem]`}>
          {(options?.modules ?? []).map((m) => (
            <option key={m.id} value={m.id}>{m.name}</option>
          ))}
        </select>
      </label>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
        <div className="text-sm text-theme-secondary space-y-1">
          <span>Expires after</span>
          <div className="flex gap-2" role="group" aria-label="Expiry">
            {presets.map((h) => (
              <button key={h} type="button" onClick={() => setHours(h)} aria-pressed={effectiveHours === h}
                disabled={h > lifetimeLimit}
                className={`btn-theme btn-theme-sm ${effectiveHours === h ? 'btn-theme-primary' : 'btn-theme-secondary'}`}>
                {h}h
              </button>
            ))}
          </div>
        </div>
        <label className="text-sm text-theme-secondary space-y-1">
          <span>Max uses ({strict ? `required, 1-${usesLimit ?? 10}` : 'optional'})</span>
          <input aria-label="Max uses" type="number" min={1} max={usesLimit ?? undefined} value={maxUses}
            onChange={(e) => setMaxUses(e.target.value)} className={fieldClass} />
        </label>
      </div>
      {strict && !strictBoundsMet && (
        <p className="text-sm text-theme-error-fg">
          A strict plane needs max uses (1-{usesLimit ?? 10}) and at least one module.
        </p>
      )}

      <label className="block text-sm text-theme-secondary space-y-1">
        <span>Reason (required)</span>
        <textarea aria-label="Reason" value={reason} onChange={(e) => setReason(e.target.value)} rows={2}
          className={fieldClass} />
      </label>

      <div className="text-sm text-theme-secondary space-y-1">
        <p>
          A grant belongs to the agent: anyone who can drive this agent can spend it, and a failed promotion still
          spends a use.
        </p>
        <label className="flex items-center gap-2">
          <input type="checkbox" checked={granterOnly} onChange={(e) => setGranterOnly(e.target.checked)} />
          <span>Only when I drive the agent</span>
        </label>
      </div>

      <div className="flex justify-end gap-2">
        <button type="button" onClick={onDone} className="btn-theme btn-theme-secondary btn-theme-sm">Cancel</button>
        <button type="submit" disabled={!canSubmit} className="btn-theme btn-theme-primary btn-theme-sm">
          Issue grant
        </button>
      </div>
    </form>
  );
};

const GrantRow: React.FC<{ grant: PromotionGrant; canManage: boolean }> = ({ grant, canManage }) => {
  const revoke = useRevokePromotionGrant();
  const { addNotification } = useNotifications();

  const handleRevoke = async () => {
    try {
      await revoke.mutateAsync(grant.id);
      addNotification({ type: 'success', message: 'Promotion grant revoked' });
    } catch (error) {
      addNotification({ type: 'error', message: getErrorMessage(error, 'Failed to revoke promotion grant') });
    }
  };

  return (
    <tr className="border-t border-theme" data-testid={`grant-${grant.id}`}>
      <td className="py-2 pr-3 text-theme-primary">{grant.agent?.name ?? '—'}</td>
      <td className="py-2 pr-3 text-theme-primary">
        {grant.environment?.slug ?? '—'}
        {grant.strict_plane && (
          <AlertTriangle className="inline h-3 w-3 ml-1 text-theme-error-fg" aria-label="strict plane" />
        )}
      </td>
      <td className="py-2 pr-3 text-theme-secondary">
        {grant.module_ids.length === 0 ? 'any' : `${grant.module_ids.length} module(s)`}
      </td>
      <td className="py-2 pr-3 text-theme-secondary">{grant.uses_count}/{grant.max_uses ?? '∞'}</td>
      <td className="py-2 pr-3 text-theme-secondary">{formatTimeLeft(grant.seconds_remaining)}</td>
      <td className="py-2 pr-3 text-theme-secondary">{grant.granted_by?.name || grant.granted_by?.email || '—'}</td>
      <td className="py-2 pr-3">
        <span className={`px-2 py-0.5 rounded text-xs ${STATUS_CLASS[grant.status]}`}>{grant.status}</span>
      </td>
      <td className="py-2 text-right">
        {canManage && grant.status === 'active' && (
          <button onClick={handleRevoke} disabled={revoke.isPending}
            className="btn-theme btn-theme-danger btn-theme-sm inline-flex items-center gap-1">
            <Ban className="h-3 w-3" /> Revoke
          </button>
        )}
      </td>
    </tr>
  );
};

/**
 * Promotion grants: a person's time-boxed standing permission for one agent
 * to promote into one environment. Lists active then recent grants; issuing
 * and revoking need ai.promotion_grants.manage (the server also requires the
 * promote verb's own permission and the person's own session to issue).
 */
export const PromotionGrantsPanel: React.FC = () => {
  const { hasPermission } = usePermissions();
  const canManage = hasPermission(MANAGE);
  const { data: grants, isLoading } = usePromotionGrants();
  const [showCreate, setShowCreate] = useState(false);

  const sorted = useMemo(() => grants ?? [], [grants]);

  return (
    <Card>
      <CardContent className="space-y-4">
        <div className="flex items-center justify-between">
          <h3 className="text-base font-semibold text-theme-primary flex items-center gap-2">
            <KeyRound className="h-4 w-4" /> Promotion grants
          </h3>
          {canManage && !showCreate && (
            <button onClick={() => setShowCreate(true)} className="btn-theme btn-theme-primary btn-theme-sm inline-flex items-center gap-1">
              <Plus className="h-3 w-3" /> New grant
            </button>
          )}
        </div>
        <p className="text-sm text-theme-tertiary">
          While a grant is active, the agent it names may promote into its environment without a per-promotion
          approval. Anyone who can drive that agent can spend the grant (unless it is granter-only), and a failed
          promotion still spends a use. A grant never overrides a block or the kill switch, and lasts at most 24
          hours (4 on a strict plane such as prod).
        </p>

        {showCreate && canManage && <PromotionGrantForm onDone={() => setShowCreate(false)} />}

        {isLoading ? (
          <LoadingSpinner size="md" message="Loading grants..." />
        ) : sorted.length === 0 ? (
          <p className="text-sm text-theme-secondary">No promotion grants yet.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-theme-tertiary">
                  <th className="pb-2 pr-3 font-medium">Agent</th>
                  <th className="pb-2 pr-3 font-medium">Environment</th>
                  <th className="pb-2 pr-3 font-medium">Modules</th>
                  <th className="pb-2 pr-3 font-medium">Uses</th>
                  <th className="pb-2 pr-3 font-medium">Time left</th>
                  <th className="pb-2 pr-3 font-medium">Granted by</th>
                  <th className="pb-2 pr-3 font-medium">Status</th>
                  <th className="pb-2" />
                </tr>
              </thead>
              <tbody>
                {sorted.map((g) => <GrantRow key={g.id} grant={g} canManage={canManage} />)}
              </tbody>
            </table>
          </div>
        )}
      </CardContent>
    </Card>
  );
};

export default PromotionGrantsPanel;
