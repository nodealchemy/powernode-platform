// Approval Chains — routed at /app/ai/approval-chains.
//
// `ApprovalChainList` and `ApprovalChainEditor` were built and shipped but had
// no core route (only the System Settings tab in the system extension reached
// them). This page gives them a first-class home in the AI section.
//
// Composition note: `ApprovalChainList` is the single data owner — it calls
// `useApprovalChains` and renders `ApprovalChainEditor` for both create and
// edit. A second `useApprovalChains()` instance at page level would issue a
// duplicate GET and drift out of sync with the table after any write, so this
// page deliberately stays thin chrome around it.
//
// Access is gated at the route (`ai.approval_chains.manage`, matching
// `Api::V1::Ai::ApprovalChainsController`); the backend enforces it again.
import React from 'react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { ApprovalChainList } from '@/shared/components/approval-chains/ApprovalChainList';

const breadcrumbs = [
  { label: 'Dashboard', href: '/app' },
  { label: 'AI', href: '/app/ai' },
  { label: 'Approval Chains' }
];

export const ApprovalChainsPage: React.FC = () => (
  <PageContainer
    title="Approval Chains"
    description="Ordered, multi-step approval workflows that high-risk agent actions must clear before they run."
    breadcrumbs={breadcrumbs}
  >
    <ApprovalChainList />
  </PageContainer>
);

export default ApprovalChainsPage;
