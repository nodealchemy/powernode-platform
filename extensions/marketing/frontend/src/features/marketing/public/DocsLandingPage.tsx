import React from 'react';
import { ExternalLink, BookOpen, Server, Layout, Brain, Cog, Cpu, ShieldCheck, TestTube } from 'lucide-react';
import { PublicPageContainer } from '@/shared/components/layout/PublicPageContainer';

const mainNav = [
  { label: 'Features', path: '/features' },
  { label: 'Pricing', path: '/pricing' },
  { label: 'Blog', path: '/blog' },
  { label: 'Docs', path: '/docs' },
];

const GITHUB_BASE = 'https://github.com/rett/powernode-platform/blob/develop';

interface DocSection {
  icon: React.ComponentType<{ className?: string }>;
  title: string;
  description: string;
  links: Array<{ label: string; path: string; description?: string }>;
}

const SECTIONS: DocSection[] = [
  {
    icon: BookOpen,
    title: 'Getting Started',
    description: 'Set up the platform locally and learn the architecture.',
    links: [
      { label: 'Quick Start', path: 'docs/QUICKSTART.md', description: 'Bootstrap a dev environment in ~10 minutes.' },
      { label: 'Development Guide', path: 'docs/DEVELOPMENT.md', description: 'Architecture, namespaces, and conventions.' },
      { label: 'Project Conventions', path: 'CLAUDE.md', description: 'Patterns enforced across the codebase.' },
      { label: 'Contributing', path: 'CONTRIBUTING.md', description: 'How to file issues and submit PRs.' },
    ],
  },
  {
    icon: Server,
    title: 'Backend (Rails)',
    description: 'Models, services, controllers, and API standards.',
    links: [
      { label: 'Rails Architect Specialist', path: 'docs/backend/RAILS_ARCHITECT_SPECIALIST.md' },
      { label: 'Service Architecture', path: 'docs/backend/BACKEND_SERVICE_ARCHITECTURE.md' },
      { label: 'Database Schema Reference', path: 'docs/backend/DATABASE_SCHEMA_REFERENCE.md' },
      { label: 'API Response Standards', path: 'docs/platform/API_RESPONSE_STANDARDS.md' },
    ],
  },
  {
    icon: Layout,
    title: 'Frontend (React + TypeScript)',
    description: 'Component patterns, theming, and state.',
    links: [
      { label: 'React Architect Specialist', path: 'docs/frontend/REACT_ARCHITECT_SPECIALIST.md' },
      { label: 'UI Components', path: 'docs/frontend/UI_COMPONENT_DEVELOPER_SPECIALIST.md' },
      { label: 'State Management Guide', path: 'docs/frontend/STATE_MANAGEMENT_GUIDE.md' },
      { label: 'Theme System Reference', path: 'docs/platform/THEME_SYSTEM_REFERENCE.md' },
    ],
  },
  {
    icon: Brain,
    title: 'AI Platform',
    description: 'Agent orchestration, memory, MCP tools, and autonomy.',
    links: [
      { label: 'AI Orchestration Guide', path: 'docs/platform/AI_ORCHESTRATION_GUIDE.md' },
      { label: 'Agent Autonomy Guide', path: 'docs/platform/AGENT_AUTONOMY_GUIDE.md' },
      { label: 'MCP Tool Catalog', path: 'docs/platform/MCP_TOOL_CATALOG.md', description: '430+ tool actions across 57 classes.' },
      { label: 'Memory System Architecture', path: 'docs/platform/MEMORY_SYSTEM_ARCHITECTURE.md' },
      { label: 'Knowledge Graph & RAG', path: 'docs/platform/RAG_SYSTEM_GUIDE.md' },
    ],
  },
  {
    icon: Cog,
    title: 'DevOps & CI/CD',
    description: 'Pipelines, container orchestration, and deployments.',
    links: [
      { label: 'DevOps Platform Guide', path: 'docs/platform/DEVOPS_PLATFORM_GUIDE.md' },
      { label: 'Docker Swarm Operations', path: 'docs/infrastructure/DOCKER_SWARM_OPERATIONS.md' },
      { label: 'Configuration Management', path: 'docs/infrastructure/CONFIGURATION_MANAGEMENT.md' },
      { label: 'Scripts Reference', path: 'docs/infrastructure/SCRIPTS_REFERENCE.md' },
    ],
  },
  {
    icon: Cpu,
    title: 'Worker System',
    description: 'Standalone Sidekiq architecture and job patterns.',
    links: [
      { label: 'Worker Architecture Overview', path: 'docs/worker/WORKER_ARCHITECTURE_OVERVIEW.md' },
      { label: 'Worker Operations Guide', path: 'docs/worker/WORKER_OPERATIONS_GUIDE.md' },
      { label: 'CI/CD Architecture', path: 'docs/worker/CI_CD_ARCHITECTURE.md' },
    ],
  },
  {
    icon: ShieldCheck,
    title: 'Security & Permissions',
    description: 'RBAC, supply chain security, and platform safety.',
    links: [
      { label: 'Permission System Reference', path: 'docs/platform/PERMISSION_SYSTEM_REFERENCE.md' },
      { label: 'Security Specialist', path: 'docs/infrastructure/SECURITY_SPECIALIST.md' },
      { label: 'Supply Chain Security', path: 'docs/platform/SUPPLY_CHAIN_SECURITY.md' },
      { label: 'AI Security Guardrails', path: 'docs/platform/AI_SECURITY_GUARDRAILS.md' },
    ],
  },
  {
    icon: TestTube,
    title: 'Testing',
    description: 'Backend, frontend, and end-to-end test patterns.',
    links: [
      { label: 'Backend Testing', path: 'docs/testing/BACKEND_TEST_ENGINEER_SPECIALIST.md' },
      { label: 'Frontend Testing', path: 'docs/testing/FRONTEND_TEST_ENGINEER_SPECIALIST.md' },
      { label: 'E2E Testing (Playwright)', path: 'docs/testing/PLAYWRIGHT_E2E_TESTING.md' },
    ],
  },
];

export const DocsLandingPage: React.FC = () => {
  return (
    <PublicPageContainer
      title="Documentation"
      description="Curated entry points into the Powernode codebase. Documentation lives in the GitHub repository and is rendered there — links below jump to the canonical markdown."
      mainNav={mainNav}
    >
      <section className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
        <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-6">
          {SECTIONS.map(section => {
            const Icon = section.icon;
            return (
              <div
                key={section.title}
                className="bg-theme-surface rounded-xl p-6 border border-theme"
                data-testid={`docs-section-${section.title.toLowerCase().replace(/\s+/g, '-')}`}
              >
                <div className="flex items-center gap-3 mb-3">
                  <div className="w-10 h-10 rounded-lg bg-theme-info/10 flex items-center justify-center">
                    <Icon className="w-5 h-5 text-theme-info" />
                  </div>
                  <h2 className="text-lg font-bold text-theme-primary">{section.title}</h2>
                </div>
                <p className="text-sm text-theme-secondary mb-4">{section.description}</p>
                <ul className="space-y-2">
                  {section.links.map(link => (
                    <li key={link.path}>
                      <a
                        href={`${GITHUB_BASE}/${link.path}`}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="group flex items-start gap-2 text-sm text-theme-secondary hover:text-theme-primary"
                      >
                        <ExternalLink className="w-3.5 h-3.5 mt-0.5 flex-shrink-0 text-theme-tertiary group-hover:text-theme-info" />
                        <span>
                          <span className="font-semibold group-hover:underline">{link.label}</span>
                          {link.description && (
                            <span className="block text-xs text-theme-tertiary mt-0.5">{link.description}</span>
                          )}
                        </span>
                      </a>
                    </li>
                  ))}
                </ul>
              </div>
            );
          })}
        </div>

        <div className="mt-12 p-6 rounded-xl bg-theme-info/5 border border-theme-info/20 text-center">
          <h3 className="text-lg font-bold text-theme-primary mb-2">Looking for something specific?</h3>
          <p className="text-sm text-theme-secondary mb-4">
            The full documentation tree is organized under <code className="text-theme-info">docs/</code> in the repository.
          </p>
          <a
            href={`${GITHUB_BASE}/docs`}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-2 px-5 py-2.5 bg-theme-info-solid hover:bg-theme-interactive-primary-hover text-white font-semibold rounded-lg transition-colors text-sm"
          >
            Browse all docs on GitHub <ExternalLink className="w-4 h-4" />
          </a>
        </div>
      </section>
    </PublicPageContainer>
  );
};
