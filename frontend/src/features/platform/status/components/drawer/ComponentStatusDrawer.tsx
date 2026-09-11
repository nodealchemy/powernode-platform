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
import { RunbookTab } from '@/features/platform/status/components/drawer/RunbookTab';
import { InvestigationsTab } from '@/features/platform/status/components/drawer/InvestigationsTab';
import { EventsTab } from '@/features/platform/status/components/drawer/EventsTab';
import { useComponentDrawerExtras } from '@/features/platform/status/hooks/useComponentDrawerExtras';
import type { ComponentStatusSummary } from '@/shared/types/platformStatus';

// The component drawer (design §6). One panel answering, for one component,
// what is wrong, what depends on it, what the platform is doing, and what a
// person may do about it.
//
// ── EXTENSION VIEWS ARE FOUND UNDER A DERIVED PREFIX ───────────────────────
//
// `platform.status.drawer.<component_kind>.<view>` — one registration per view,
// one tab per view. Core does not enumerate kinds or views and imports nothing
// an extension owns: an extension registers each view under an id its own kind
// derives, and this drawer lists whatever sits under that kind's prefix. None
// is the ordinary case, not a missing feature, so there is no placeholder and
// no error.
//
// One id per VIEW, not per kind: a slot id holds one component, and a second
// registration under the same id silently replaces the first. With one id per
// kind, two views of one kind (boot replay and signals for node_instance) would
// have to be fused into a single component, or the later one would erase the
// earlier. Each tab is labelled from its `<view>` segment and the tabs are
// ordered by id, so the order never depends on which extension loaded first.
// There is no single-id `<kind>` form.
//
// The registry is a mutable singleton, so the listing is re-run on every
// version bump (the CostPage precedent). Without that, an extension that
// finishes loading after the drawer opened would have registered a view nobody
// looks for again.
//
// ── SEVEN CORE TABS, FROM TWO SETS OF READS ────────────────────────────────
//
// Conditions, Dependencies, Remediation and Actions come from the detail +
// impact reads. Runbook, Investigations and Events (C3 part 2) come from A9's
// four doors, loaded independently so the least important panel failing never
// blanks the rest. The remediation route — including the lane's own
// `lane_reason` — is folded into the Remediation tab rather than given a tab of
// its own, because "what is the platform doing" and "which lane, under which
// budget" are one question.

/** The prefix every view of one kind registers under. Derived, never enumerated. */
export const drawerViewPrefix = (componentKind: string) =>
  `platform.status.drawer.${componentKind}.`;

/** A view's tab label, from the `<view>` segment of its id: `boot_replay` → "Boot replay". */
export const drawerViewLabel = (view: string) => {
  const words = view.replace(/[_-]+/g, ' ').trim();
  return words.charAt(0).toUpperCase() + words.slice(1);
};

type DrawerViewComponent = NonNullable<ReturnType<typeof featureRegistry.getComponentSlot>>;

interface DrawerView {
  id: string;
  /** The tab value, namespaced so a view named like a core tab cannot collide with it. */
  value: string;
  label: string;
  Component: DrawerViewComponent;
}

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
  const extras = useComponentDrawerExtras(row?.id ?? null);
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

  const views = useMemo<DrawerView[]>(() => {
    if (!row) return [];
    const prefix = drawerViewPrefix(row.component_kind);
    return featureRegistry.getComponentSlotIds(prefix).flatMap((id) => {
      const view = id.slice(prefix.length);
      const Component = featureRegistry.getComponentSlot(id);
      return view && Component
        ? [{ id, value: `view:${view}`, label: drawerViewLabel(view), Component }]
        : [];
    });
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
              <TabsTrigger value="runbook">Runbook</TabsTrigger>
              <TabsTrigger value="investigations">Investigations</TabsTrigger>
              <TabsTrigger value="events">Events</TabsTrigger>
              {views.map((view) => (
                <TabsTrigger key={view.id} value={view.value}>
                  {view.label}
                </TabsTrigger>
              ))}
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
                route={extras.route}
                routeFailed={extras.routeFailed}
              />
            </TabsContent>

            <TabsContent value="actions" className="pt-3">
              <ActionsTab
                actions={detail.actions}
                componentName={name}
                onCompleted={refresh}
              />
            </TabsContent>

            <TabsContent value="runbook" className="pt-3">
              <RunbookTab data={extras.runbook} loading={extras.loading} />
            </TabsContent>

            <TabsContent value="investigations" className="pt-3">
              <InvestigationsTab
                data={extras.investigations}
                loading={extras.loading}
                componentStatusId={row.id}
                beginRefresh={extras.beginInvestigationRefresh}
              />
            </TabsContent>

            <TabsContent value="events" className="pt-3">
              <EventsTab
                events={extras.events}
                loading={extras.loading}
                totalCount={extras.eventsTotal}
                failed={extras.eventsFailed}
              />
            </TabsContent>

            {views.map(({ id, value, label, Component }) => (
              <TabsContent key={id} value={value} className="pt-3">
                {/* The extension's own view. Core passes the row and nothing
                    else: it does not know what this kind's view needs, and a
                    prop contract invented here would constrain every future
                    view to the first one that registered. */}
                {/* Suspense HERE, per view, not somewhere up the tree:
                    extensions register lazy views, and without a boundary of
                    its own a lazy view suspends to the nearest one above — the
                    page's, which would blank the whole status screen while one
                    tab's code loads. */}
                <React.Suspense
                  fallback={
                    <p className="text-sm text-theme-secondary">{`Loading ${label.toLowerCase()}…`}</p>
                  }
                >
                  <Component {...({ row: detail } as Record<string, unknown>)} />
                </React.Suspense>
              </TabsContent>
            ))}
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
