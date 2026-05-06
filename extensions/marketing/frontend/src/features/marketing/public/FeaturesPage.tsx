import React from 'react';
import { Link } from 'react-router-dom';
import {
  ShieldAlert, Network, Workflow, Plug, Server, Lock,
  Activity, GitBranch, Cpu, Zap, ArrowRight,
} from 'lucide-react';

import { PublicPageContainer } from '@/shared/components/layout/PublicPageContainer';

interface Feature {
  icon: React.ReactNode;
  iconBg: string;
  title: string;
  description: string;
}

const features: Feature[] = [
  {
    icon: <ShieldAlert className="w-6 h-6 text-white" />,
    iconBg: 'bg-theme-danger',
    title: 'Kill switch + intervention policies',
    description: 'Trust-scored agents with per-action approval chains, collusion detection, and platform-wide emergency halt. Audit trails for every decision.',
  },
  {
    icon: <Network className="w-6 h-6 text-white" />,
    iconBg: 'bg-theme-info',
    title: 'Knowledge graph context',
    description: '71,824+ nodes of structured context. Semantic navigation, blast-radius analysis, feature hub linking. Your agents stop hallucinating; they look it up.',
  },
  {
    icon: <Workflow className="w-6 h-6 text-white" />,
    iconBg: 'bg-theme-success',
    title: 'Stigmergic coordination',
    description: 'Agents leave pressure signals for each other to perceive. Multi-agent systems coordinate without explicit messaging or central scheduler.',
  },
  {
    icon: <Plug className="w-6 h-6 text-white" />,
    iconBg: 'bg-theme-warning',
    title: 'MCP-native runtime',
    description: '280+ MCP tool actions out of the box. Permission-gated. Adapters for Claude Agent SDK, LangGraph, Mastra. Production-grade catalog.',
  },
  {
    icon: <Server className="w-6 h-6 text-white" />,
    iconBg: 'bg-theme-info',
    title: 'Fleet management',
    description: 'Bare-metal, VM, and container lifecycle. Multi-arch boot (amd64 + arm64). Pre-warmed instance pools with atomic claim. Cosign + SLSA L3+ signed module supply chain.',
  },
  {
    icon: <Lock className="w-6 h-6 text-white" />,
    iconBg: 'bg-theme-danger',
    title: 'mTLS + Vault PKI',
    description: 'Internal CA with mTLS enrollment, automatic certificate rotation, OCI image verification with cosign + fs-verity. Zero-trust between agents.',
  },
  {
    icon: <Activity className="w-6 h-6 text-white" />,
    iconBg: 'bg-theme-success',
    title: 'Compound learning loop',
    description: 'System gets better over time. Auto-evolves skills after recurring patterns. Decay, reinforcement, and contradiction resolution built in.',
  },
  {
    icon: <GitBranch className="w-6 h-6 text-white" />,
    iconBg: 'bg-theme-info',
    title: 'GitOps drift detection',
    description: 'Declarative module definitions in Git. Drift detection compares running state to desired state. Auto-remediation policies per module.',
  },
  {
    icon: <Cpu className="w-6 h-6 text-white" />,
    iconBg: 'bg-theme-warning',
    title: 'Ralph loops',
    description: 'Sidekiq-style autonomous task execution for agents. Schedule recurring duty cycles, perceive signals, take actions, log decisions.',
  },
  {
    icon: <Zap className="w-6 h-6 text-white" />,
    iconBg: 'bg-theme-success',
    title: 'SDWAN + WireGuard mesh',
    description: 'First-class virtual IPs, iBGP/FRR routing, JSONB route policies, federation peers, access grants. Tailscale UX with FRR routing depth.',
  },
];

export const FeaturesPage: React.FC = () => {
  return (
    <PublicPageContainer
      title="Features"
      description="Everything you need to run a production AI agent fleet — control, coordination, governance, and the infrastructure to host it."
      mainNav={[
        { label: 'Pricing', path: '/pricing' },
        { label: 'Features', path: '/features' },
      ]}
    >
      <section className="py-12">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-8">
            {features.map(feature => (
              <div
                key={feature.title}
                className="p-8 bg-theme-background rounded-2xl border border-theme hover:border-theme-info-solid transition-all duration-200"
              >
                <div className={`w-12 h-12 mb-4 rounded-xl ${feature.iconBg} flex items-center justify-center`}>
                  {feature.icon}
                </div>
                <h3 className="text-xl font-bold text-theme-primary mb-3">{feature.title}</h3>
                <p className="text-theme-secondary text-sm leading-relaxed">{feature.description}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section className="py-16 bg-theme-background-secondary">
        <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
          <h2 className="text-3xl md:text-4xl font-bold text-theme-primary mb-4">
            Want to see it work?
          </h2>
          <p className="text-lg text-theme-secondary mb-8 leading-relaxed">
            Try the managed Cloud free, or self-host the OSS today.
          </p>
          <div className="flex flex-col sm:flex-row items-center justify-center gap-4">
            <Link
              to="/plans"
              className="inline-flex items-center space-x-2 px-8 py-4 bg-theme-info-solid hover:bg-theme-interactive-primary-hover text-white font-semibold rounded-xl transition-all duration-200 transform hover:scale-105 shadow-lg hover:shadow-xl"
            >
              <span>Try the Cloud — Free</span>
              <ArrowRight className="w-4 h-4" />
            </Link>
            <a
              href="https://github.com/rett/powernode-system"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center space-x-2 px-8 py-4 bg-theme-surface hover:bg-theme-background text-theme-primary font-semibold rounded-xl border border-theme transition-all duration-200"
            >
              <span>View on GitHub</span>
              <ArrowRight className="w-4 h-4" />
            </a>
          </div>
        </div>
      </section>
    </PublicPageContainer>
  );
};
