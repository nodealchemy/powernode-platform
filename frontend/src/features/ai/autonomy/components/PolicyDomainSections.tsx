import React, { useCallback, useEffect, useMemo, useRef, useState, useSyncExternalStore } from 'react';
import { Settings } from 'lucide-react';
import { AutonomyPolicyGroup } from '@/shared/components/autonomy/AutonomyPolicyGroup';
import { useAutonomyConfig } from '@/shared/hooks/useAutonomyConfig';
import { featureRegistry, type PolicyDomainPresentation } from '@/shared/services/featureRegistry';
import type { AutonomyDomainPolicy } from '@/shared/types/autonomy';
import { interventionPolicyConfigSource } from '../api/interventionPolicyConfigSource';
import { policyBucket } from '../policyBucket';

/**
 * The server's catch-all domain: core's own statics and any category no
 * registered domain claims. GET /ai/intervention_policies/grouped is an
 * ACCOUNT-WIDE view and ships it populated; a panel scoped to one extension's
 * namespace leaves it out, the unscoped core page shows it last.
 */
const OTHER_DOMAIN_KEY = 'other';

const OTHER_PRESENTATION: PolicyDomainPresentation = {
  key: OTHER_DOMAIN_KEY,
  label: 'Other policies',
  description: 'Core policies, and any category no registered policy domain claims.',
  icon: Settings,
};

interface PolicyDomainSectionsProps {
  /**
   * Show only this namespace's domains: every server domain except the
   * catch-all and those ANOTHER namespace presents. A domain nothing presents
   * still renders (humanised) — a server domain the frontend has not caught up
   * with must not vanish, which is how the old literal list lost 28 categories.
   */
  namespace?: string;
  /** Changing this refetches the rows (a sibling view wrote to them). Drops unsaved edits. */
  refreshKey?: number;
  /** Called after a save lands, so a sibling view of the same rows can refetch. */
  onSaved?: () => void;
}

interface AgentGroup {
  bucket: string;
  actions: string[];
}

interface DomainSection extends PolicyDomainPresentation {
  actionCount: number;
  groups: AgentGroup[];
  /**
   * Categories whose rows could not be placed in a group. Kept apart from
   * `groups` so nothing renders them through an editor by accident, and so they
   * cannot collide with a group key (an agent's NAME, which validates no format).
   */
  unreadableActions: string[];
}

function humanizeDomainKey(key: string): string {
  return key
    .split('_')
    .filter(Boolean)
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ');
}

/**
 * One editor group per agent bucket present in the domain: a policy row is per
 * (category, scope, agent), and the same category is commonly seeded twice —
 * agent-scoped and for the operator path — with different verbs.
 *
 * `policyBucket` is the single authority for a row's bucket; the hook reads
 * verbs and row identities with the same function, so a group here always has a
 * verb there. Unplaceable rows are RETURNED, not dropped: dropping them would
 * show a complete-looking panel that omits real policy.
 */
function buildGroups(rows: AutonomyDomainPolicy[]): { groups: AgentGroup[]; unreadable: string[] } {
  const byBucket = new Map<string, string[]>();
  const unreadable: string[] = [];

  rows.forEach((row) => {
    const bucket = policyBucket(row);
    if (bucket === null) {
      if (!unreadable.includes(row.action_category)) unreadable.push(row.action_category);
      return;
    }
    const actions = byBucket.get(bucket) || [];
    if (!actions.includes(row.action_category)) actions.push(row.action_category);
    byBucket.set(bucket, actions);
  });

  return { groups: Array.from(byBucket, ([bucket, actions]) => ({ bucket, actions })), unreadable };
}

/**
 * Presentation for the domains to show, in section order: presented domains in
 * registration order, then server keys nothing presents (server order), then —
 * unscoped only — the catch-all.
 */
function orderedPresentations(serverKeys: string[], namespace?: string): PolicyDomainPresentation[] {
  const all = featureRegistry.getPolicyDomains();
  const own = namespace === undefined ? all : featureRegistry.getPolicyDomains(namespace);
  const ownKeys = new Set(own.map((d) => d.key));
  const presentedKeys = new Set(all.map((d) => d.key));

  const presented = own.filter((d) => serverKeys.includes(d.key));
  const unpresented = serverKeys
    .filter((key) => key !== OTHER_DOMAIN_KEY && !presentedKeys.has(key) && !ownKeys.has(key))
    .map((key) => ({ key, label: humanizeDomainKey(key), icon: Settings,
                     description: 'Policies the server groups under this domain.' }));
  const other = namespace === undefined && serverKeys.includes(OTHER_DOMAIN_KEY) ? [OTHER_PRESENTATION] : [];

  return [...presented, ...unpresented, ...other];
}

/**
 * The degraded, honest rendering of rows whose group could not be read. NOT an
 * editor (an editable control asserts a current verb and a row to write it to,
 * and there is neither) and NOT hidden (that trades a visible wrong answer for
 * an invisible one). The rest of the panel stays editable.
 */
function UnreadablePolicyGroup({ label, actions }: { label: string; actions: string[] }) {
  return (
    <div className="rounded-lg border border-theme-warning-border overflow-hidden">
      <div className="px-4 py-2.5 bg-theme-warning-bg flex items-center justify-between">
        <span className="text-xs font-semibold text-theme-warning-fg">{label}</span>
        <span className="text-[10px] text-theme-warning-fg">{actions.length} actions</span>
      </div>
      <div className="p-3 space-y-2">
        <p className="text-[11px] text-theme-secondary">
          The server did not say which agent owns these policy rows, so this panel cannot show
          their current setting and will not offer to change it. Their policies are unchanged and
          still in force. Update the server to configure them here.
        </p>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-3 gap-y-1">
          {actions.map((action) => (
            <div key={action} className="flex items-center gap-1.5 py-0.5">
              <span className="text-xs text-theme-primary truncate flex-1 min-w-0">{action}</span>
              <span className="text-[11px] text-theme-tertiary shrink-0 w-[100px]">Unknown</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

/**
 * Intervention policies grouped by DOMAIN, then by agent, from the server's own
 * grouping (GET /ai/intervention_policies/grouped). Edits are held locally and
 * saved in one bulk request, each addressed to the row it was rendered from.
 */
export const PolicyDomainSections: React.FC<PolicyDomainSectionsProps> = ({ namespace, refreshKey, onSaved }) => {
  const autonomy = useAutonomyConfig(interventionPolicyConfigSource);
  const [activeKey, setActiveKey] = useState<string>('');

  // The mount already fetched; refetch only when the key moves after that.
  const { reload } = autonomy;
  const seenRefreshKey = useRef(refreshKey);
  useEffect(() => {
    if (seenRefreshKey.current === refreshKey) return;
    seenRefreshKey.current = refreshKey;
    reload();
  }, [refreshKey, reload]);

  const { save } = autonomy;
  const saveAndNotify = useCallback(async () => {
    await save();
    onSaved?.();
  }, [save, onSaved]);
  // An extension registering its domains after mount re-sorts the sections.
  const registryVersion = useSyncExternalStore(
    (listener) => featureRegistry.subscribe(listener),
    () => featureRegistry.getVersion()
  );

  const sections = useMemo<DomainSection[]>(() => {
    const nonEmpty = Object.entries(autonomy.domains).filter(([, rows]) => Array.isArray(rows) && rows.length > 0);
    const rowsByKey = new Map(nonEmpty);

    return orderedPresentations(nonEmpty.map(([key]) => key), namespace).map((presentation) => {
      const { groups, unreadable } = buildGroups(rowsByKey.get(presentation.key) || []);
      return {
        ...presentation,
        // Rows LISTED, unreadable ones included, so the badge matches the screen.
        actionCount: groups.reduce((sum, g) => sum + g.actions.length, 0) + unreadable.length,
        groups,
        unreadableActions: unreadable,
      };
    });
    // registryVersion is read only to invalidate: presentations come from the registry.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [autonomy.domains, namespace, registryVersion]);

  const activeSection = sections.find((s) => s.key === activeKey) || sections[0];

  // Whether ANY section holds rows the panel could not place, not just the one
  // on screen: an operator who never opens the affected section would otherwise
  // read the panel as complete.
  const hasUnreadableRows = sections.some((s) => s.unreadableActions.length > 0);

  if (autonomy.loading) {
    return <p className="text-sm text-theme-tertiary py-6 text-center">Loading…</p>;
  }

  if (!activeSection) {
    return (
      <p className="text-sm text-theme-tertiary py-6 text-center">
        No intervention policies are configured for this account yet.
      </p>
    );
  }

  return (
    <div className="flex gap-4 min-h-[50vh]">
      <nav className="w-56 shrink-0 border-r border-theme pr-2 -mr-2">
        <ul className="space-y-0.5">
          {sections.map((s) => {
            const Icon = s.icon || Settings;
            const isActive = activeSection.key === s.key;
            return (
              <li key={s.key}>
                <button
                  type="button"
                  onClick={() => setActiveKey(s.key)}
                  className={
                    'w-full flex items-center gap-2 px-3 py-2 rounded text-sm text-left transition-colors ' +
                    (isActive
                      ? 'bg-theme-surface-selected text-theme-primary font-medium'
                      : 'text-theme-secondary hover:bg-theme-surface-hover hover:text-theme-primary')
                  }
                >
                  <Icon size={16} className={isActive ? 'text-theme-info-fg' : 'text-theme-tertiary'} />
                  <span className="flex-1 truncate">{s.label}</span>
                  <span className="text-[10px] text-theme-tertiary tabular-nums">{s.actionCount}</span>
                </button>
              </li>
            );
          })}
        </ul>
      </nav>

      <div className="flex-1 min-w-0 space-y-3">
        {hasUnreadableRows && (
          <div
            data-testid="autonomy-skew-warning"
            className="rounded border border-theme-warning-border bg-theme-warning-bg px-3 py-2"
          >
            <p className="text-xs text-theme-warning-fg">
              This view is incomplete. The server returned policy rows without the agent they belong
              to — a sign it is older than this interface. Those rows are listed as{' '}
              <span className="font-semibold">Posture unknown</span> and cannot be read or changed
              here; everything else on this screen is accurate and safe to save.
            </p>
          </div>
        )}

        {autonomy.isDirty && (
          <p data-testid="policy-unsaved-changes" className="text-xs text-theme-warning-fg">
            You have unsaved changes. Save them from any group below.
          </p>
        )}

        <div>
          <h3 className="text-sm font-semibold text-theme-primary">{activeSection.label}</h3>
          <p className="text-xs text-theme-tertiary mt-1">{activeSection.description}</p>
        </div>

        {activeSection.groups.map((group) => (
          <AutonomyPolicyGroup
            key={group.bucket}
            label={`${activeSection.label} · ${group.bucket}`}
            agentName={group.bucket}
            actions={group.actions}
            getPolicy={autonomy.getPolicy}
            updatePolicy={autonomy.updatePolicy}
            onSave={saveAndNotify}
            isDirty={autonomy.isDirty}
          />
        ))}

        {/* Outside the map, so no key it uses can collide with an agent's name. */}
        {activeSection.unreadableActions.length > 0 && (
          <UnreadablePolicyGroup
            label={`${activeSection.label} · Posture unknown`}
            actions={activeSection.unreadableActions}
          />
        )}
      </div>
    </div>
  );
};
