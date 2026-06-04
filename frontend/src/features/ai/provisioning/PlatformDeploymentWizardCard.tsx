import React, { useMemo, useState } from 'react';
import { Server, AlertCircle, CheckCircle2, Copy, Check, KeyRound, Rocket, HardDrive } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { logger } from '@/shared/utils/logger';
import { useNotifications } from '@/shared/hooks/useNotifications';
import type { ChatCard } from '@/shared/types/ai';
import { provisioningApi, type CreateVolumeRequest } from './services/provisioningApi';

/**
 * Renders the `platform_deployment_wizard` ChatCard inline in concierge
 * chat. Two payload shapes:
 *
 *   - Form phase (no `mode` supplied):
 *     {
 *       card: { kind, phase: "form", fields, modes, templates, spawn_modes, defaults },
 *     }
 *
 *   - Done phase (mode supplied, deployment ran):
 *     {
 *       mode, node_instance_id, platform_deployment_id,
 *       acceptance_token?, spawn_payload?, next_steps[]
 *     }
 *
 * Plan reference: D3 (chat-driven platform deployment).
 */

interface PlatformDeploymentWizardCardProps {
  card: ChatCard;
  className?: string;
}

interface AvailableVolume {
  id: string;
  name: string;
  size_gb: number;
  provider_region_id?: string | null;
  created_at?: string;
}

interface WizardStoragePayload {
  stateful_roles: string[];
  mount_points: Record<string, string>;
  recommended_size_gb_by_role: Record<string, number>;
  available_volumes: AvailableVolume[];
  updated_at?: string | null;
}

interface WizardFormPayload {
  card: {
    kind: string;
    phase: 'form';
    fields: Array<{ name: string; type: string; required: boolean; help?: string; options?: string[] }>;
    modes: Array<{ value: string; label: string; help: string }>;
    templates: Array<{ value: string; label: string; description?: string }>;
    spawn_modes: Array<{ value: string; label: string }>;
    defaults: Record<string, unknown>;
    storage?: WizardStoragePayload;
  };
}

interface AttachedVolumeBinding {
  volume_id: string;
  volume_name?: string;
  size_gb?: number;
  device_name?: string;
  mount_point?: string;
  role?: string;
  attached_at?: string;
  error?: string;
}

interface WizardDonePayload {
  mode: 'standalone' | 'federated';
  node_instance_id: string | null;
  platform_deployment_id: string | null;
  federation_peer_id?: string | null;
  acceptance_token?: string | null;
  spawn_payload?: Record<string, unknown> | null;
  storage_volume?: AttachedVolumeBinding | null;
  next_steps?: string[];
}

export const PlatformDeploymentWizardCard: React.FC<PlatformDeploymentWizardCardProps> = ({
  card,
  className = '',
}) => {
  // Done phase: deployment already happened
  if (isDonePayload(card.payload)) {
    return (
      <DoneCard payload={card.payload as unknown as WizardDonePayload} className={className} />
    );
  }
  // Form phase: render the wizard
  if (isFormPayload(card.payload)) {
    return (
      <FormCard payload={card.payload as unknown as WizardFormPayload} className={className} />
    );
  }
  // Unexpected shape — show a safe fallback rather than crashing
  return (
    <Card className={`mt-3 p-3 ${className}`.trim()}>
      <div className="text-sm text-theme-secondary">Platform deployment wizard (unrecognized payload)</div>
    </Card>
  );
};

function isFormPayload(payload: unknown): payload is WizardFormPayload {
  return (
    typeof payload === 'object' &&
    payload !== null &&
    'card' in payload &&
    typeof (payload as { card?: { phase?: string } }).card === 'object' &&
    (payload as { card: { phase: string } }).card.phase === 'form'
  );
}

function isDonePayload(payload: unknown): payload is WizardDonePayload {
  return (
    typeof payload === 'object' &&
    payload !== null &&
    'mode' in payload &&
    'platform_deployment_id' in payload
  );
}

// ── Form phase ───────────────────────────────────────────────────────

const FormCard: React.FC<{ payload: WizardFormPayload; className: string }> = ({
  payload,
  className,
}) => {
  const { card } = payload;
  const defaults = card.defaults || {};
  const [mode, setMode] = useState<string>((defaults.mode as string) || 'standalone');
  const [name, setName] = useState('');
  const [templateSlug, setTemplateSlug] = useState((defaults.template_slug as string) || 'powernode-hub');
  const [serviceRole, setServiceRole] = useState('api');
  const [publicDns, setPublicDns] = useState('');
  const [spawnMode, setSpawnMode] = useState((defaults.spawn_mode as string) || 'managed_child');
  const [parentUrl, setParentUrl] = useState(window.location.origin);
  const [submitting, setSubmitting] = useState(false);
  const [result, setResult] = useState<WizardDonePayload | null>(null);
  // VOL.3 — storage state. volumeId='' + skipVolume=false means
  // "auto-pick a matching volume if available"; volumeId='__skip__'
  // means "deploy without persistent storage"; volumeId='__create__'
  // means "show inline form to register a new ProviderVolume now";
  // volumeId=<uuid> means "use this specific volume".
  const [volumeChoice, setVolumeChoice] = useState<string>('');
  // E6 — Inline volume creation state.
  const [newVolume, setNewVolume] = useState<{
    name: string;
    size_gb: string;
    transport: 'nfs' | 'block';
    nfs_server: string;
    nfs_export_path: string;
  }>({
    name: '',
    size_gb: '',
    transport: 'nfs',
    nfs_server: '',
    nfs_export_path: '',
  });
  const [creatingVolume, setCreatingVolume] = useState(false);
  const [createVolumeError, setCreateVolumeError] = useState<string | null>(null);
  // Local list lets us inject newly-created volumes without refetching the wizard payload.
  const [extraVolumes, setExtraVolumes] = useState<AvailableVolume[]>([]);
  const { addNotification } = useNotifications();

  const isFederated = mode === 'federated';
  const storage = card.storage;
  const isStatefulRole = useMemo(
    () => !!storage?.stateful_roles?.includes(serviceRole),
    [storage, serviceRole],
  );
  const recommendedSize = storage?.recommended_size_gb_by_role?.[serviceRole];
  const mountPoint = storage?.mount_points?.[serviceRole];
  const compatibleVolumes = useMemo(() => {
    const base = storage?.available_volumes ?? [];
    const all = [...base, ...extraVolumes];
    if (!recommendedSize) return all;
    return all.filter((v) => v.size_gb >= recommendedSize);
  }, [storage, recommendedSize, extraVolumes]);

  const handleCreateVolume = async () => {
    const sizeGb = parseInt(newVolume.size_gb, 10);
    if (!newVolume.name.trim() || !Number.isFinite(sizeGb) || sizeGb < 1) {
      setCreateVolumeError('Name and size (≥1 GB) are required.');
      return;
    }
    if (newVolume.transport === 'nfs' && (!newVolume.nfs_server.trim() || !newVolume.nfs_export_path.trim())) {
      setCreateVolumeError('NFS transport requires server + export path.');
      return;
    }
    setCreatingVolume(true);
    setCreateVolumeError(null);
    try {
      const body: CreateVolumeRequest = {
        name: newVolume.name.trim(),
        size_gb: sizeGb,
        transport: newVolume.transport,
      };
      if (newVolume.transport === 'nfs') {
        body.nfs_server = newVolume.nfs_server.trim();
        body.nfs_export_path = newVolume.nfs_export_path.trim();
      }
      const created = await provisioningApi.createPlatformVolume(body);
      if (!created?.id) {
        setCreateVolumeError('Volume created but no id returned — check the volumes list.');
        return;
      }
      setExtraVolumes((prev) => [
        ...prev,
        {
          id: created.id,
          name: created.name,
          size_gb: created.size_gb,
          provider_region_id: created.provider_region_id ?? null,
        },
      ]);
      setVolumeChoice(created.id);
      // Reset the create form
      setNewVolume({ name: '', size_gb: '', transport: 'nfs', nfs_server: '', nfs_export_path: '' });
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Volume create failed';
      logger.error('PlatformDeploymentWizard create volume failed', { err });
      setCreateVolumeError(msg);
    } finally {
      setCreatingVolume(false);
    }
  };
  const validation = useMemo(() => {
    const errs: string[] = [];
    if (!name.trim()) errs.push('name is required');
    if (isFederated && !parentUrl.trim()) errs.push('parent_url is required for federated mode');
    if (isFederated && !spawnMode) errs.push('spawn_mode is required for federated mode');
    return { ok: errs.length === 0, errs };
  }, [name, parentUrl, spawnMode, isFederated]);

  const handleSubmit = async () => {
    if (!validation.ok) {
      addNotification({ type: 'error', message: validation.errs[0] ?? 'Form invalid' });
      return;
    }
    setSubmitting(true);
    try {
      const body: Record<string, unknown> = {
        mode,
        name: name.trim(),
        template_slug: templateSlug,
        service_role: serviceRole,
      };
      if (publicDns.trim()) body.public_dns_hostname = publicDns.trim();
      if (isFederated) {
        body.spawn_mode = spawnMode;
        body.parent_url = parentUrl.trim();
      }
      // VOL.3 — pass volume choice through. '__skip__' = ephemeral
      // deploy, '' = auto-pick (only relevant for stateful roles),
      // '__create__' = operator chose "create new" but didn't submit
      // the form — treat same as auto-pick, <uuid> = use this volume.
      if (isStatefulRole) {
        if (volumeChoice === '__skip__') {
          body.skip_volume = true;
        } else if (volumeChoice && volumeChoice !== '__create__') {
          body.volume_id = volumeChoice;
        }
        // else: auto-pick (orchestrator selects smallest matching)
      }
      const payload = await provisioningApi.createPlatformDeployment(body);
      const data = ((payload as { data?: WizardDonePayload } | undefined)?.data || payload) as WizardDonePayload;
      setResult(data);
      addNotification({ type: 'success', message: `Platform deployment queued — ${data.mode}` });
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Deploy failed';
      logger.error('PlatformDeploymentWizard submit failed', { err });
      addNotification({ type: 'error', message: msg });
    } finally {
      setSubmitting(false);
    }
  };

  if (result) {
    return <DoneCard payload={result} className={className} />;
  }

  return (
    <Card className={`mt-3 p-4 ${className}`.trim()}>
      <div className="flex items-center gap-2 mb-3">
        <Rocket className="w-5 h-5 text-theme-info" />
        <h3 className="font-semibold text-theme-primary">Deploy a New Platform</h3>
      </div>

      <div className="space-y-3">
        <Field label="Mode">
          <div className="space-y-2">
            {card.modes.map((m) => (
              <label
                key={m.value}
                className={`block p-2 rounded border cursor-pointer transition-colors ${
                  mode === m.value
                    ? 'border-theme-info bg-theme-info'
                    : 'border-theme bg-theme-background-secondary hover:bg-theme-surface-hover'
                }`}
              >
                <input
                  type="radio"
                  name="deployment_mode"
                  value={m.value}
                  checked={mode === m.value}
                  onChange={() => setMode(m.value)}
                  className="mr-2"
                />
                <span className="font-medium text-theme-primary">{m.label}</span>
                <span className="block text-xs text-theme-secondary mt-0.5">{m.help}</span>
              </label>
            ))}
          </div>
        </Field>

        <Field label="Name *" help="Human-readable name for the deployment">
          <input
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            disabled={submitting}
            placeholder="e.g. west-hub-1"
            className="w-full px-2 py-1.5 border border-theme rounded bg-theme-background-secondary text-theme-primary font-mono text-sm disabled:opacity-50"
          />
        </Field>

        <div className="grid grid-cols-2 gap-3">
          <Field label="Template">
            <select
              value={templateSlug}
              onChange={(e) => setTemplateSlug(e.target.value)}
              disabled={submitting}
              className="w-full px-2 py-1.5 border border-theme rounded bg-theme-background-secondary text-theme-primary text-sm disabled:opacity-50"
            >
              {card.templates.map((t) => (
                <option key={t.value} value={t.value}>
                  {t.label}
                </option>
              ))}
            </select>
          </Field>
          <Field label="Service Role">
            <select
              value={serviceRole}
              onChange={(e) => setServiceRole(e.target.value)}
              disabled={submitting}
              className="w-full px-2 py-1.5 border border-theme rounded bg-theme-background-secondary text-theme-primary text-sm disabled:opacity-50"
            >
              {['api', 'worker', 'frontend', 'postgres', 'redis', 'reverse-proxy', 'satellite-runtime'].map((r) => (
                <option key={r} value={r}>{r}</option>
              ))}
            </select>
          </Field>
        </div>

        <Field label="Public DNS Hostname (optional)" help="ACME cert is issued automatically post-boot if set">
          <input
            type="text"
            value={publicDns}
            onChange={(e) => setPublicDns(e.target.value.trim())}
            disabled={submitting}
            placeholder="e.g. hub.example.org"
            className="w-full px-2 py-1.5 border border-theme rounded bg-theme-background-secondary text-theme-primary font-mono text-sm disabled:opacity-50"
          />
        </Field>

        {isStatefulRole && (
          <div className="p-3 bg-theme-background-secondary border border-theme rounded space-y-2">
            <div className="flex items-center gap-2 text-sm text-theme-primary font-medium">
              <HardDrive className="w-4 h-4 text-theme-info" />
              <span>Persistent Storage</span>
              <span className="text-xs text-theme-secondary font-normal">
                ({serviceRole} is stateful — recommended ≥{recommendedSize ?? '?'} GB
                {mountPoint && `, mount at ${mountPoint}`})
              </span>
            </div>

            <Field label="Volume">
              <select
                value={volumeChoice}
                onChange={(e) => setVolumeChoice(e.target.value)}
                disabled={submitting || creatingVolume}
                className="w-full px-2 py-1.5 border border-theme rounded bg-theme-surface text-theme-primary text-sm disabled:opacity-50"
              >
                <option value="">
                  Auto-pick {compatibleVolumes.length > 0
                    ? `(${compatibleVolumes.length} candidate${compatibleVolumes.length === 1 ? '' : 's'})`
                    : '(no candidates — ephemeral)'}
                </option>
                {compatibleVolumes.map((v) => (
                  <option key={v.id} value={v.id}>
                    {v.name} ({v.size_gb} GB)
                  </option>
                ))}
                <option value="__create__">+ Create new volume…</option>
                <option value="__skip__">Skip — deploy without persistent storage</option>
              </select>
              <p className="text-xs text-theme-secondary mt-1">
                {volumeChoice === '__skip__' ? (
                  <span className="text-theme-warning">
                    ⚠ Stateful role with ephemeral storage — data lost on instance termination.
                  </span>
                ) : volumeChoice === '__create__' ? (
                  <span>Fill in the form below — the new volume will be created + selected automatically.</span>
                ) : volumeChoice ? (
                  <span>Volume will attach at {mountPoint || 'default mount'} on first boot.</span>
                ) : compatibleVolumes.length === 0 ? (
                  <span className="text-theme-warning">
                    No volumes ≥{recommendedSize ?? '?'} GB are available — choose "Create new volume…" above or proceed ephemeral.
                  </span>
                ) : (
                  <span>Orchestrator will pick the smallest matching unattached volume.</span>
                )}
              </p>
            </Field>

            {volumeChoice === '__create__' && (
              <div className="p-3 bg-theme-surface border border-theme rounded space-y-2">
                <div className="text-xs font-medium text-theme-primary">Create new volume</div>
                {createVolumeError && (
                  <div className="p-2 bg-theme-danger text-theme-danger text-xs rounded flex items-start gap-2">
                    <AlertCircle className="w-3 h-3 mt-0.5 flex-shrink-0" />
                    <span>{createVolumeError}</span>
                  </div>
                )}
                <div className="grid grid-cols-2 gap-2">
                  <input
                    type="text"
                    value={newVolume.name}
                    onChange={(e) => setNewVolume((prev) => ({ ...prev, name: e.target.value }))}
                    disabled={creatingVolume}
                    placeholder={`e.g. ${serviceRole}-${name || 'dev'}-vol`}
                    className="px-2 py-1 border border-theme rounded bg-theme-background-secondary text-theme-primary font-mono text-xs disabled:opacity-50"
                  />
                  <input
                    type="number"
                    min={1}
                    value={newVolume.size_gb}
                    onChange={(e) => setNewVolume((prev) => ({ ...prev, size_gb: e.target.value }))}
                    disabled={creatingVolume}
                    placeholder={`Size (GB) ≥ ${recommendedSize ?? 10}`}
                    className="px-2 py-1 border border-theme rounded bg-theme-background-secondary text-theme-primary font-mono text-xs disabled:opacity-50"
                  />
                </div>
                <select
                  value={newVolume.transport}
                  onChange={(e) =>
                    setNewVolume((prev) => ({ ...prev, transport: e.target.value as 'nfs' | 'block' }))
                  }
                  disabled={creatingVolume}
                  className="w-full px-2 py-1 border border-theme rounded bg-theme-background-secondary text-theme-primary text-xs disabled:opacity-50"
                >
                  <option value="nfs">NFS — network filesystem (multi-tenant)</option>
                  <option value="block">Block — exclusive device</option>
                </select>
                {newVolume.transport === 'nfs' && (
                  <div className="grid grid-cols-2 gap-2">
                    <input
                      type="text"
                      value={newVolume.nfs_server}
                      onChange={(e) =>
                        setNewVolume((prev) => ({ ...prev, nfs_server: e.target.value }))
                      }
                      disabled={creatingVolume}
                      placeholder="NFS server (e.g. dsm.local)"
                      className="px-2 py-1 border border-theme rounded bg-theme-background-secondary text-theme-primary font-mono text-xs disabled:opacity-50"
                    />
                    <input
                      type="text"
                      value={newVolume.nfs_export_path}
                      onChange={(e) =>
                        setNewVolume((prev) => ({ ...prev, nfs_export_path: e.target.value }))
                      }
                      disabled={creatingVolume}
                      placeholder="Export path (e.g. /volume1/share)"
                      className="px-2 py-1 border border-theme rounded bg-theme-background-secondary text-theme-primary font-mono text-xs disabled:opacity-50"
                    />
                  </div>
                )}
                <div className="flex justify-end">
                  <Button
                    variant="primary"
                    onClick={handleCreateVolume}
                    disabled={creatingVolume}
                  >
                    {creatingVolume ? 'Creating…' : 'Create + Select'}
                  </Button>
                </div>
              </div>
            )}
          </div>
        )}

        {isFederated && (
          <>
            <Field label="Spawn Mode *">
              <select
                value={spawnMode}
                onChange={(e) => setSpawnMode(e.target.value)}
                disabled={submitting}
                className="w-full px-2 py-1.5 border border-theme rounded bg-theme-background-secondary text-theme-primary text-sm disabled:opacity-50"
              >
                {card.spawn_modes.map((sm) => (
                  <option key={sm.value} value={sm.value}>{sm.label}</option>
                ))}
              </select>
            </Field>

            <Field label="Parent URL *" help="This platform's reachable URL (the child posts back here)">
              <input
                type="text"
                value={parentUrl}
                onChange={(e) => setParentUrl(e.target.value.trim())}
                disabled={submitting}
                placeholder="https://this-platform.example.org"
                className="w-full px-2 py-1.5 border border-theme rounded bg-theme-background-secondary text-theme-primary font-mono text-sm disabled:opacity-50"
              />
            </Field>
          </>
        )}
      </div>

      <div className="flex items-center justify-end gap-2 mt-4">
        <Button
          variant="primary"
          onClick={handleSubmit}
          disabled={submitting || !validation.ok}
        >
          <Rocket className="w-4 h-4" />
          {submitting ? 'Deploying…' : 'Deploy'}
        </Button>
      </div>
    </Card>
  );
};

// ── Done phase ───────────────────────────────────────────────────────

const DoneCard: React.FC<{ payload: WizardDonePayload; className: string }> = ({
  payload,
  className,
}) => {
  const [tokenCopied, setTokenCopied] = useState(false);
  const isFederated = payload.mode === 'federated';

  const handleCopyToken = async () => {
    if (!payload.acceptance_token) return;
    try {
      await navigator.clipboard.writeText(payload.acceptance_token);
      setTokenCopied(true);
      setTimeout(() => setTokenCopied(false), 2000);
    } catch {
      // ignore
    }
  };

  return (
    <Card className={`mt-3 p-4 ${className}`.trim()}>
      <div className="flex items-center gap-2 mb-3">
        <CheckCircle2 className="w-5 h-5 text-theme-success" />
        <h3 className="font-semibold text-theme-primary">Deployment Queued</h3>
        <span className="text-xs text-theme-secondary font-mono">({payload.mode})</span>
      </div>

      <div className="grid grid-cols-2 gap-3 text-sm mb-3">
        <KV label="Node Instance ID" value={payload.node_instance_id ?? '—'} />
        <KV label="Deployment ID" value={payload.platform_deployment_id ?? '—'} />
        {payload.federation_peer_id && (
          <KV label="Federation Peer ID" value={payload.federation_peer_id} />
        )}
      </div>

      {payload.storage_volume && !payload.storage_volume.error && payload.storage_volume.volume_id && (
        <div className="mb-3 p-2 bg-theme-background-secondary border border-theme rounded text-xs">
          <div className="flex items-center gap-2 text-theme-primary mb-1">
            <HardDrive className="w-3 h-3 text-theme-success" />
            <strong>Volume attached</strong>
          </div>
          <div className="text-theme-secondary">
            <span className="font-mono">{payload.storage_volume.volume_name}</span>
            {payload.storage_volume.size_gb && <> ({payload.storage_volume.size_gb} GB)</>}
            {payload.storage_volume.device_name && (
              <> at <code className="font-mono">{payload.storage_volume.device_name}</code></>
            )}
            {payload.storage_volume.mount_point && (
              <> → <code className="font-mono">{payload.storage_volume.mount_point}</code></>
            )}
          </div>
        </div>
      )}

      {payload.storage_volume?.error && (
        <div className="mb-3 p-2 bg-theme-warning text-theme-warning rounded text-xs">
          <strong>Storage attach failed:</strong> {payload.storage_volume.error}
        </div>
      )}

      {isFederated && payload.acceptance_token && (
        <div className="mb-3">
          <div className="p-2 bg-theme-warning text-theme-warning text-xs rounded flex items-start gap-2 mb-2">
            <KeyRound className="w-4 h-4 mt-0.5 flex-shrink-0" />
            <span>
              <strong>Capture this token NOW.</strong> The plaintext is shown only
              once. If lost, the child cannot complete the handshake.
            </span>
          </div>
          <div className="flex items-stretch gap-2">
            <input
              type="text"
              readOnly
              value={payload.acceptance_token}
              className="flex-1 px-2 py-1.5 border border-theme rounded bg-theme-background-secondary text-theme-primary font-mono text-xs select-all"
            />
            <button
              type="button"
              onClick={handleCopyToken}
              className="px-3 py-1.5 border border-theme rounded bg-theme-info-solid text-white text-xs inline-flex items-center gap-1 hover:opacity-90 transition-opacity"
            >
              {tokenCopied ? <Check className="w-3.5 h-3.5" /> : <Copy className="w-3.5 h-3.5" />}
              {tokenCopied ? 'Copied' : 'Copy'}
            </button>
          </div>
        </div>
      )}

      {Array.isArray(payload.next_steps) && payload.next_steps.length > 0 && (
        <div className="mt-3">
          <div className="text-xs text-theme-tertiary uppercase mb-1">Next Steps</div>
          <ul className="space-y-1 text-xs text-theme-secondary">
            {payload.next_steps.map((step, idx) => (
              <li key={idx} className="flex items-start gap-1.5">
                <Server className="w-3 h-3 mt-0.5 flex-shrink-0" />
                <span>{step}</span>
              </li>
            ))}
          </ul>
        </div>
      )}
    </Card>
  );
};

// ── Helpers ──────────────────────────────────────────────────────────

const Field: React.FC<{ label: string; help?: string; children: React.ReactNode }> = ({
  label,
  help,
  children,
}) => (
  <div>
    <label className="block text-xs font-medium text-theme-secondary mb-1">{label}</label>
    {children}
    {help && <p className="text-xs text-theme-tertiary mt-0.5">{help}</p>}
  </div>
);

const KV: React.FC<{ label: string; value: string }> = ({ label, value }) => (
  <div>
    <div className="text-xs text-theme-tertiary uppercase">{label}</div>
    <div className="font-mono text-theme-primary text-xs break-all">{value}</div>
  </div>
);

export default PlatformDeploymentWizardCard;
