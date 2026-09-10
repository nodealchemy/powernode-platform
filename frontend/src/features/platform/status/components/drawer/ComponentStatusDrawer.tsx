import React, { useEffect, useMemo, useState } from 'react';
import { icons } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/shared/components/ui/Tabs';
import { VerdictBadge } from '@/shared/components/ui/VerdictBadge';
import { featureRegistry } from '@/shared/services/featureRegistry';
import { formatRelativeTimeCompact } from '@/shared/utils/formatters';
import ErrorAlert from '@/shared/components/ui/ErrorAlert';
import { useComponentStatusDetail } from '@/features/platform/status/hooks/useComponentStatusDetail';
import { ConditionsTab } from '@/features/platform/status/components/drawer/ConditionsTab';
import { DependenciesTab } from '@/features/platform/status/components/drawer/DependenciesTab';
import { RemediationTab } from '@/features/platform/status/components/drawer/RemediationTab';
import { ActionsTab } from '@/features/platform/status/components/drawer/ActionsTab';
import type { ComponentStatusSummary } from '@/shared/types/platformStatus';

// The component drawer (design §6). One panel answering, for one component,
// what is wrong, what depends on it, what the platform is doing, and what a
// person may do about it.
//
// ── THE RICH PANEL IS RESOLVED BY A DERIVED SLOT ID ────────────────────────
//
// `platform.status.drawer.<component_kind>`. Core does not enumerate kinds and
// does not import anything an extension owns: an extension registers a
// component under the id its own kind derives, and this drawer renders it if it
// is there. Nothing happens if it is not — an absent rich panel is the ordinary
// case, not a missing feature, so there is no placeholder and no error.
//
// The registry is a mutable singleton, so resolution is re-run on every version
// bump (the CostPage precedent). Without that, an extension that finishes
// loading after the drawer opened would have registered a panel nobody looks
// for again.
//
// ── WHAT IS DELIBERATELY NOT HERE YET ──────────────────────────────────────
//
// Runbook, Investigations and Events are C3 part 2, waiting on A9's REST
// surface. They are absent rather than stubbed: a tab that opens on "coming
// soon" teaches an operator to stop clicking tabs.

/** The slot id a kind's rich panel registers under. Derived, never enumerated. */
export const drawerSlotId = (componentKind: string) =>
  `platform.status.drawer.${componentKind}`;

const resolveIcon = (name?: string): React.ComponentType<{ className?: string }> => {
  if (!name) return icons.Puzzle;
  return icons[name as keyof typeof icons] ?? icons.Puzzle;
};

export interface ComponentStatusDrawerProps {
  /** The summary row the grid already has, so the header renders before the detail read lands. */
  row: ComponentStatusSummary | null;
  onClose: () => void;
  /** Selecting a downstream or root-cause component from inside the drawer. */
  onSelect?: (row: ComponentStatusSummary) => void;
}

export const ComponentStatusDrawer: React.FC<ComponentStatusDrawerProps> = ({
  row,
  onClose,
  onSelect,
}) => {
  const { detail, impact, loading, error, refresh } = useComponentStatusDetail(row?.id ?? null);
  const [tab, setTab] = useState('conditions');

  // Back to the first tab when the component changes. Keeping the previous tab
  // would show, say, an empty Actions panel for a component whose interesting
  // half is its conditions — and worse, would look like that component has no
  // actions rather than like a tab nobody moved.
  useEffect(() => setTab('conditions'), [row?.id]);

  const [registryVersion, setRegistryVersion] = useState(() => featureRegistry.getVersion());
  useEffect(
    () => featureRegistry.subscribe(() => setRegistryVersion(featureRegistry.getVersion())),
    []
  );

  const RichPanel = useMemo(() => {
    if (!row) return undefined;
    return featureRegistry.getComponentSlot(drawerSlotId(row.component_kind));
    // registryVersion is the dependency that matters: the registry is a mutable
    // singleton, so its identity never changes and only the version tells us to
    // look again.
  }, [row, registryVersion]);

  if (!row) return null;

  const Icon = resolveIcon(row.presentation?.icon);
  const name = row.display_name || row.component_ref;

  return (
    <Modal
      isOpen
      onClose={onClose}
      variant="drawer"
      closeOnEscape
      title={
        <span className="flex items-center gap-2 min-w-0">
          <Icon className="w-4 h-4 shrink-0 text-theme-secondary" />
          <span className="truncate">{name}</span>
        </span>
      }
      subtitle={row.presentation?.label || row.component_kind}
    >
      <div className="flex flex-col gap-4" data-drawer-component={row.component_ref}>
        <div className="flex flex-wrap items-center gap-3">
          <VerdictBadge verdict={row.verdict} labelPrefix={name} />
          {row.observed_at && (
            <span
              className="text-xs text-theme-tertiary"
              title={`Observed at ${row.observed_at} — the source's measurement time, not the sweep's.`}
            >
              observed {formatRelativeTimeCompact(row.observed_at)}
            </span>
          )}
          {row.scope === 'shared' && (
            <span
              className="text-xs text-theme-tertiary"
              title="Process-wide infrastructure with no tenant. Never counted in this account's operational verdict."
            >
              shared infrastructure
            </span>
          )}
        </div>

        {error && <ErrorAlert message={error} />}
        {loading && !detail && <p className="text-sm text-theme-secondary">Loading detail…</p>}

        {detail && (
          <Tabs value={tab} onValueChange={setTab}>
            <TabsList>
              <TabsTrigger value="conditions">Conditions</TabsTrigger>
              <TabsTrigger value="dependencies">Dependencies</TabsTrigger>
              <TabsTrigger value="remediation">Remediation</TabsTrigger>
              <TabsTrigger value="actions">Actions</TabsTrigger>
              {RichPanel && <TabsTrigger value="details">Details</TabsTrigger>}
            </TabsList>

            <TabsContent value="conditions" className="pt-3">
              <ConditionsTab conditions={detail.conditions} />
            </TabsContent>

            <TabsContent value="dependencies" className="pt-3">
              <DependenciesTab
                dependencies={detail.dependencies}
                impact={impact}
                onSelect={onSelect}
              />
            </TabsContent>

            <TabsContent value="remediation" className="pt-3">
              <RemediationTab
                remediation={detail.remediation}
                state={detail.remediation_state}
              />
            </TabsContent>

            <TabsContent value="actions" className="pt-3">
              <ActionsTab
                actions={detail.actions}
                componentName={name}
                onCompleted={refresh}
              />
            </TabsContent>

            {RichPanel && (
              <TabsContent value="details" className="pt-3">
                {/* The extension's own panel. Core passes the row and nothing
                    else: it does not know what this kind's panel needs, and a
                    prop contract invented here would constrain every future
                    kind to the first one that registered. */}
                <RichPanel {...({ row: detail } as Record<string, unknown>)} />
              </TabsContent>
            )}
          </Tabs>
        )}

        {detail && detail.links.length > 0 && (
          <div className="flex flex-wrap gap-3 border-t border-theme pt-3">
            {detail.links.map((link) => (
              <a key={link.path} href={link.path} className="text-xs text-theme-info-fg underline">
                {link.label}
              </a>
            ))}
          </div>
        )}
      </div>
    </Modal>
  );
};

export default ComponentStatusDrawer;
