// AI Billing Page - Consolidated Credits, Outcome Billing, and FinOps
import React, { useState, useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import { Coins, Receipt, DollarSign } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { CreditsContent } from '@/pages/app/ai/CreditsPage';
import { OutcomeBillingContent } from '@/pages/app/ai/OutcomeBillingPage';
import { FinOpsContent } from '@/features/ai/finops';

const tabs = [
  { id: 'credits', label: 'Credits', icon: <Coins size={16} />, path: '/credits' },
  { id: 'outcome-billing', label: 'Outcome Billing', icon: <Receipt size={16} />, path: '/outcome-billing' },
  { id: 'finops', label: 'FinOps', icon: <DollarSign size={16} />, path: '/finops' },
];

export const AiBillingContent: React.FC = () => {
  const [activeTab, setActiveTab] = useState<string>('credits');

  const billingTabs = [
    { id: 'credits', label: 'Credits', Icon: Coins },
    { id: 'outcome-billing', label: 'Outcome Billing', Icon: Receipt },
    { id: 'finops', label: 'FinOps', Icon: DollarSign },
  ];

  return (
    <div className="space-y-6">
      <div className="flex gap-1 border-b border-theme-border">
        {billingTabs.map((tab) => (
          <button
            key={tab.id}
            onClick={() => setActiveTab(tab.id)}
            className={`flex items-center gap-2 px-4 py-2 text-sm font-medium border-b-2 transition-colors ${
              activeTab === tab.id
                ? 'border-theme-primary text-theme-primary'
                : 'border-transparent text-theme-muted hover:text-theme-secondary'
            }`}
          >
            <tab.Icon size={14} />
            {tab.label}
          </button>
        ))}
      </div>

      {activeTab === 'credits' && <CreditsContent />}
      {activeTab === 'outcome-billing' && <OutcomeBillingContent />}
      {activeTab === 'finops' && <FinOpsContent />}
    </div>
  );
};

export const AiBillingPage: React.FC = () => {
  const location = useLocation();

  const getActiveTab = () => {
    const path = location.pathname;
    if (path.includes('/billing/outcome-billing')) return 'outcome-billing';
    if (path.includes('/billing/finops')) return 'finops';
    return 'credits';
  };

  const [activeTab, setActiveTab] = useState(getActiveTab());

  useEffect(() => {
    const newTab = getActiveTab();
    if (newTab !== activeTab) setActiveTab(newTab);
  }, [location.pathname]);

  const getBreadcrumbs = () => {
    const base: Array<{ label: string; href?: string }> = [
      { label: 'Dashboard', href: '/app' },
      { label: 'AI', href: '/app/ai' },
    ];
    if (activeTab === 'credits') {
      base.push({ label: 'Billing' });
    } else {
      base.push({ label: 'Billing', href: '/app/ai/billing' });
      base.push({ label: 'Outcome Billing' });
    }
    return base;
  };

  return (
    <PageContainer
      title="AI Billing"
      description="Manage AI credits, purchases, and outcome-based billing"
      breadcrumbs={getBreadcrumbs()}
    >
      <TabContainer
        tabs={tabs}
        activeTab={activeTab}
        onTabChange={setActiveTab}
        basePath="/app/ai/billing"
        variant="underline"
        className="mb-6"
      >
        <TabPanel tabId="credits" activeTab={activeTab}>
          <CreditsContent />
        </TabPanel>
        <TabPanel tabId="outcome-billing" activeTab={activeTab}>
          <OutcomeBillingContent />
        </TabPanel>
        <TabPanel tabId="finops" activeTab={activeTab}>
          <FinOpsContent />
        </TabPanel>
      </TabContainer>
    </PageContainer>
  );
};

export default AiBillingPage;
