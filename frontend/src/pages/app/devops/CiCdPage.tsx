import React, { useState, useEffect, useCallback, useMemo } from 'react';
import { useLocation } from 'react-router-dom';
import { Workflow, Server, FileText, Puzzle } from 'lucide-react';
import { PageContainer, type PageAction } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel, type Tab } from '@/shared/components/layout/TabContainer';
import { featureRegistry } from '@/shared/services/featureRegistry';
import { PipelinesPage } from '@/pages/app/devops/PipelinesPage';
import { RunnersPage as AiPipelinesRunnersPage } from '@/features/devops/pipelines';
import { RunnerHealthPanel } from '@/features/devops/pipelines/components/RunnerHealthPanel';
import { TemplatesContent } from '@/pages/app/ai/DevOpsTemplatesPage';

// fc-34 review fix: an extension-contributed CI/CD tab (e.g. the system
// extension's Module Builds) mounts through this generic slot prefix rather
// than a hardcoded tab entry — core never imports or names the extension.
// Mirrors ComponentStatusDrawer.tsx's `platform.status.drawer.<kind>.<view>`
// pattern: `featureRegistry.registerComponentSlots({'devops.ci-cd.tab.<id>':
// Component})`, discovered here via `getComponentSlotIds(prefix)`. The `<id>`
// segment becomes the tab's id/path (`/app/devops/ci-cd/<id>`). The label and
// gating permissions come from the slot's optional metadata
// (featureRegistry.registerSlotMeta / getSlotMeta) — falling back to a
// title-cased derivation of `<id>` and no permission restriction when a slot
// registers no metadata — and every slot tab shows the same generic icon:
// there is still no icon channel in ComponentSlot or ComponentSlotMeta.
const CI_CD_TAB_SLOT_PREFIX = 'devops.ci-cd.tab.';

/** `module-builds` / `module_builds` -> `Module builds`. */
const slotTabLabel = (id: string): string => {
  const words = id.replace(/[_-]+/g, ' ').trim();
  return words.charAt(0).toUpperCase() + words.slice(1);
};

interface SlotTab {
  id: string;
  label: string;
  permissions?: string[];
  Component: React.ComponentType<{ onActionsReady?: (actions: PageAction[]) => void }>;
}

// Pipelines is the default tab: the bare /app/devops/ci-cd URL opens it.
const staticTabs: Tab[] = [
  { id: 'pipelines', label: 'Pipelines', icon: <Workflow size={16} />, path: '/pipelines' },
  { id: 'runners', label: 'Runners', icon: <Server size={16} />, path: '/runners' },
  { id: 'templates', label: 'Pipeline Templates', icon: <FileText size={16} />, path: '/templates', permissions: ['ai.devops.read'] },
];

export const CiCdPage: React.FC = () => {
  const location = useLocation();

  // The registry is a mutable singleton whose identity never changes —
  // subscribe to its version so a slot registered after this page's first
  // render (e.g. an extension loading asynchronously) still shows up.
  const [registryVersion, setRegistryVersion] = useState(() => featureRegistry.getVersion());
  useEffect(
    () => featureRegistry.subscribe(() => setRegistryVersion(featureRegistry.getVersion())),
    []
  );

  const slotTabs = useMemo<SlotTab[]>(() => {
    return featureRegistry.getComponentSlotIds(CI_CD_TAB_SLOT_PREFIX).flatMap((slotId) => {
      const id = slotId.slice(CI_CD_TAB_SLOT_PREFIX.length);
      const Component = featureRegistry.getComponentSlot(slotId) as SlotTab['Component'] | undefined;
      if (!id || !Component) return [];
      const meta = featureRegistry.getSlotMeta(slotId);
      return [{ id, label: meta?.label ?? slotTabLabel(id), permissions: meta?.permissions, Component }];
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps -- registryVersion is the real dependency (see comment above); the registry itself is a stable singleton.
  }, [registryVersion]);

  const tabs = useMemo<Tab[]>(
    () => [
      ...staticTabs,
      ...slotTabs.map((t) => ({ id: t.id, label: t.label, icon: <Puzzle size={16} />, path: `/${t.id}`, permissions: t.permissions })),
    ],
    [slotTabs]
  );

  const getActiveTab = useCallback(() => {
    const path = location.pathname;
    if (path.includes('/ci-cd/runners')) return 'runners';
    if (path.includes('/ci-cd/templates')) return 'templates';
    const slotMatch = slotTabs.find((t) => path.includes(`/ci-cd/${t.id}`));
    if (slotMatch) return slotMatch.id;
    return 'pipelines';
  }, [location.pathname, slotTabs]);

  const [activeTab, setActiveTab] = useState(getActiveTab());
  const [actions, setActions] = useState<PageAction[]>([]);

  useEffect(() => {
    const newTab = getActiveTab();
    if (newTab !== activeTab) {
      setActiveTab(newTab);
      setActions([]);
    }
  }, [getActiveTab, activeTab]);

  const handleTabChange = useCallback((tabId: string) => {
    setActiveTab(tabId);
    setActions([]);
  }, []);

  const handleActionsReady = useCallback((newActions: PageAction[]) => {
    setActions(newActions);
  }, []);

  const getBreadcrumbs = () => {
    const base: Array<{ label: string; href?: string }> = [
      { label: 'Dashboard', href: '/app' },
      { label: 'DevOps', href: '/app/devops' },
    ];
    if (activeTab === 'pipelines') {
      base.push({ label: 'CI/CD' });
    } else {
      base.push({ label: 'CI/CD', href: '/app/devops/ci-cd' });
      const activeTabInfo = tabs.find(t => t.id === activeTab);
      if (activeTabInfo) base.push({ label: activeTabInfo.label });
    }
    return base;
  };

  return (
    <PageContainer
      title="CI/CD"
      description="Pipelines and runner management"
      breadcrumbs={getBreadcrumbs()}
      actions={actions}
    >
      <TabContainer
        tabs={tabs}
        activeTab={activeTab}
        onTabChange={handleTabChange}
        basePath="/app/devops/ci-cd"
        variant="underline"
        className="mb-6"
      >
        <TabPanel tabId="pipelines" activeTab={activeTab}>
          <PipelinesPage onActionsReady={handleActionsReady} />
        </TabPanel>
        <TabPanel tabId="runners" activeTab={activeTab}>
          <RunnerHealthPanel />
          <AiPipelinesRunnersPage onActionsReady={handleActionsReady} />
        </TabPanel>
        <TabPanel tabId="templates" activeTab={activeTab}>
          <TemplatesContent onActionsReady={handleActionsReady} />
        </TabPanel>
        {slotTabs.map((t) => (
          <TabPanel key={t.id} tabId={t.id} activeTab={activeTab}>
            <t.Component onActionsReady={handleActionsReady} />
          </TabPanel>
        ))}
      </TabContainer>
    </PageContainer>
  );
};

export default CiCdPage;
