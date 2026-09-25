// Budgets — routed at /app/ai/control/budgets (the AI → Control home fc-41
// will build around it).
//
// The one surface for agent budgets: it replaced Autonomy's Budgets section and
// FinOps' Budget tab, which showed the same Ai::AgentBudget rows twice. All the
// behaviour lives in the self-contained BudgetsPanel; this page is chrome.
//
// Access is gated at the route on ai.agents.read, the permission
// GET /api/v1/ai/autonomy/budgets checks; the panel gates its write controls on
// ai.autonomy.manage, which the budget writes check.
import React from 'react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { BudgetsPanel } from '@/features/ai/budgets';

const breadcrumbs = [
  { label: 'Dashboard', href: '/app' },
  { label: 'AI', href: '/app/ai' },
  { label: 'Budgets' },
];

export const BudgetsPage: React.FC = () => (
  <PageContainer
    title="Budgets"
    description="What each agent may spend, how much of it is used, and what has been allocated on to other agents."
    breadcrumbs={breadcrumbs}
  >
    <BudgetsPanel />
  </PageContainer>
);

export default BudgetsPage;
