// Automation Feature - Consolidates AI Pipelines and CI/CD

// Pages
export { AutomationOverview } from './pages/AutomationOverview';
export { PipelinesPage } from './pages/PipelinesPage';
export { PipelineDetailPage } from './pages/PipelineDetailPage';
export { CreatePipelinePage } from './pages/CreatePipelinePage';
export { RunDetailPage } from './pages/RunDetailPage';

// Re-export existing pages from cicd that we're consolidating
// These will be gradually migrated to the automation feature
export { RunsPage } from '@/features/cicd/pages/RunsPage';
export { RunnersPage } from '@/features/cicd/pages/RunnersPage';
export { PromptsPage as TemplatesPage } from '@/features/cicd/pages/PromptsPage';
