import React, { useState, useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import {
  Globe,
  Users,
} from 'lucide-react';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { AgentDiscovery } from '../components/AgentDiscovery';
import { FederationPartnerList } from '../components/FederationPartnerList';
import { CreateFederationPartnerModal } from '../components/CreateFederationPartnerModal';
import type { CommunityAgentSummary, FederationPartnerSummary } from '@/shared/services/ai';

interface CommunityAgentsPageProps {
  onInvokeAgent?: (agent: CommunityAgentSummary) => void;
  onViewAgentDetails?: (agent: CommunityAgentSummary) => void;
  onViewPartnerDetails?: (partner: FederationPartnerSummary) => void;
}

const COMMUNITY_AGENTS_BASE_PATH = '/app/ai/agents/community';

const communityAgentsTabs = [
  { id: 'discover', label: 'Discover', icon: <Globe className="w-4 h-4" />, path: '/' },
  { id: 'federation', label: 'Federation', icon: <Users className="w-4 h-4" />, path: '/federation' },
];

const getActiveCommunityAgentsTab = (pathname: string): string =>
  pathname.includes('/community/federation') ? 'federation' : 'discover';

// Embedded as the "Community" tab of AIAgentsPage — not a standalone routed
// page (there is no top-level route for it; AIAgentsPage owns the breadcrumb).
export const CommunityAgentsContent: React.FC<CommunityAgentsPageProps> = ({
  onInvokeAgent,
  onViewAgentDetails,
  onViewPartnerDetails,
}) => {
  const location = useLocation();
  const [activeTab, setActiveTab] = useState(getActiveCommunityAgentsTab(location.pathname));
  const [refreshKey, setRefreshKey] = useState(0);
  const [showCreatePartnerModal, setShowCreatePartnerModal] = useState(false);

  useEffect(() => {
    const newTab = getActiveCommunityAgentsTab(location.pathname);
    if (newTab !== activeTab) setActiveTab(newTab);
  }, [location.pathname]);

  return (
    <>
      <TabContainer
        tabs={communityAgentsTabs}
        activeTab={activeTab}
        onTabChange={setActiveTab}
        basePath={COMMUNITY_AGENTS_BASE_PATH}
        variant="underline"
      >
        <TabPanel tabId="discover" activeTab={activeTab} className="mt-4">
          <AgentDiscovery
            key={`discover-${refreshKey}`}
            onSelectAgent={onViewAgentDetails}
            onInvokeAgent={onInvokeAgent}
          />
        </TabPanel>

        <TabPanel tabId="federation" activeTab={activeTab} className="mt-4">
          <FederationPartnerList
            key={`federation-${refreshKey}`}
            onSelectPartner={onViewPartnerDetails}
            onCreatePartner={() => setShowCreatePartnerModal(true)}
          />
        </TabPanel>
      </TabContainer>

      <CreateFederationPartnerModal
        isOpen={showCreatePartnerModal}
        onClose={() => setShowCreatePartnerModal(false)}
        onPartnerCreated={() => setRefreshKey((k) => k + 1)}
      />
    </>
  );
};
