import React, { useState } from 'react';
import {
  Globe,
  Users,
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/shared/components/ui/Tabs';
import { AgentDiscovery } from '../components/AgentDiscovery';
import { FederationPartnerList } from '../components/FederationPartnerList';
import type { CommunityAgentSummary, FederationPartnerSummary } from '@/shared/services/ai';

interface CommunityAgentsPageProps {
  onInvokeAgent?: (agent: CommunityAgentSummary) => void;
  onViewAgentDetails?: (agent: CommunityAgentSummary) => void;
  onCreateFederationPartner?: () => void;
  onViewPartnerDetails?: (partner: FederationPartnerSummary) => void;
}

export const CommunityAgentsPage: React.FC<CommunityAgentsPageProps> = ({
  onInvokeAgent,
  onViewAgentDetails,
  onCreateFederationPartner,
  onViewPartnerDetails,
}) => {
  const [activeTab, setActiveTab] = useState('discover');

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'AI', href: '/app/ai' },
    { label: 'Community Agents' },
  ];

  return (
    <PageContainer
      title="Community Agents"
      description="Discover and invoke agents from the community"
      breadcrumbs={breadcrumbs}
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
            onSelectAgent={onViewAgentDetails}
            onInvokeAgent={onInvokeAgent}
          />
        </TabsContent>

        <TabsContent value="federation" className="mt-4">
          <FederationPartnerList
            onSelectPartner={onViewPartnerDetails}
            onCreatePartner={onCreateFederationPartner}
          />
        </TabsContent>
      </Tabs>
    </PageContainer>
  );
};

export default CommunityAgentsPage;
