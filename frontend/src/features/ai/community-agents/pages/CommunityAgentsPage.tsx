import React, { useCallback, useState } from 'react';
import {
  Globe,
  RefreshCw,
  Users,
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/shared/components/ui/Tabs';
import { AgentDiscovery } from '../components/AgentDiscovery';
import { FederationPartnerList } from '../components/FederationPartnerList';
import { CreateFederationPartnerModal } from '../components/CreateFederationPartnerModal';
import type { CommunityAgentSummary, FederationPartnerSummary } from '@/shared/services/ai';

interface CommunityAgentsPageProps {
  onInvokeAgent?: (agent: CommunityAgentSummary) => void;
  onViewAgentDetails?: (agent: CommunityAgentSummary) => void;
  onViewPartnerDetails?: (partner: FederationPartnerSummary) => void;
}

export const CommunityAgentsPage: React.FC<CommunityAgentsPageProps> = ({
  onInvokeAgent,
  onViewAgentDetails,
  onViewPartnerDetails,
}) => {
  const [activeTab, setActiveTab] = useState('discover');
  const [refreshKey, setRefreshKey] = useState(0);
  const [showCreatePartnerModal, setShowCreatePartnerModal] = useState(false);

  const handleRefresh = useCallback(() => {
    setRefreshKey((k) => k + 1);
  }, []);

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'AI', href: '/app/ai' },
    { label: 'Community Agents' },
  ];

  const actions = [
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: handleRefresh,
      variant: 'secondary' as const,
      icon: RefreshCw,
    },
  ];

  return (
    <PageContainer
      title="Community Agents"
      description="Discover and invoke agents from the community"
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      {/* Tabs */}
      <Tabs value={activeTab} onValueChange={setActiveTab}>
        <TabsList>
          <TabsTrigger value="discover" className="flex items-center gap-2">
            <Globe className="w-4 h-4" />
            Discover
          </TabsTrigger>
          <TabsTrigger value="federation" className="flex items-center gap-2">
            <Users className="w-4 h-4" />
            Federation
          </TabsTrigger>
        </TabsList>

        <TabsContent value="discover" className="mt-4">
          <AgentDiscovery
            key={`discover-${refreshKey}`}
            onSelectAgent={onViewAgentDetails}
            onInvokeAgent={onInvokeAgent}
          />
        </TabsContent>

        <TabsContent value="federation" className="mt-4">
          <FederationPartnerList
            key={`federation-${refreshKey}`}
            onSelectPartner={onViewPartnerDetails}
            onCreatePartner={() => setShowCreatePartnerModal(true)}
          />
        </TabsContent>
      </Tabs>

      <CreateFederationPartnerModal
        isOpen={showCreatePartnerModal}
        onClose={() => setShowCreatePartnerModal(false)}
        onPartnerCreated={() => setRefreshKey((k) => k + 1)}
      />
    </PageContainer>
  );
};

// Extracted content component (everything inside PageContainer) for embedding in tabbed pages
export const CommunityAgentsContent: React.FC<CommunityAgentsPageProps> = ({
  onInvokeAgent,
  onViewAgentDetails,
  onViewPartnerDetails,
}) => {
  const [activeTab, setActiveTab] = useState('discover');
  const [refreshKey, setRefreshKey] = useState(0);
  const [showCreatePartnerModal, setShowCreatePartnerModal] = useState(false);

  return (
    <>
      <Tabs value={activeTab} onValueChange={setActiveTab}>
        <TabsList>
          <TabsTrigger value="discover" className="flex items-center gap-2">
            <Globe className="w-4 h-4" />
            Discover
          </TabsTrigger>
          <TabsTrigger value="federation" className="flex items-center gap-2">
            <Users className="w-4 h-4" />
            Federation
          </TabsTrigger>
        </TabsList>

        <TabsContent value="discover" className="mt-4">
          <AgentDiscovery
            key={`discover-${refreshKey}`}
            onSelectAgent={onViewAgentDetails}
            onInvokeAgent={onInvokeAgent}
          />
        </TabsContent>

        <TabsContent value="federation" className="mt-4">
          <FederationPartnerList
            key={`federation-${refreshKey}`}
            onSelectPartner={onViewPartnerDetails}
            onCreatePartner={() => setShowCreatePartnerModal(true)}
          />
        </TabsContent>
      </Tabs>

      <CreateFederationPartnerModal
        isOpen={showCreatePartnerModal}
        onClose={() => setShowCreatePartnerModal(false)}
        onPartnerCreated={() => setRefreshKey((k) => k + 1)}
      />
    </>
  );
};

export default CommunityAgentsPage;
