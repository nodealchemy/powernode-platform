import React from 'react';
import { Link } from 'react-router-dom';
import { Check, ArrowRight } from 'lucide-react';

import { PublicPageContainer } from '@/shared/components/layout/PublicPageContainer';

interface Tier {
  name: string;
  price: string;
  cadence: string;
  description: string;
  features: string[];
  cta: string;
  ctaLink: string;
  highlighted?: boolean;
}

const tiers: Tier[] = [
  {
    name: 'Free',
    price: '$0',
    cadence: '/forever',
    description: 'For evaluation, hobbyists, and homelab use.',
    features: [
      '3 agents',
      '10K MCP calls / mo',
      '100 KG nodes',
      'Single user',
      'Community support',
    ],
    cta: 'Start free',
    ctaLink: '/plans',
  },
  {
    name: 'Pro',
    price: '$49',
    cadence: '/month',
    description: 'For teams running production agent workloads.',
    features: [
      '25 agents (+$0.50/agent overage)',
      '250K MCP calls / mo (+$0.30/10K overage)',
      '10K KG nodes',
      '5 users',
      'Email support',
    ],
    cta: 'Try Pro',
    ctaLink: '/plans',
    highlighted: true,
  },
  {
    name: 'Team',
    price: '$299',
    cadence: '/month',
    description: 'For larger teams with serious traffic.',
    features: [
      '100 agents',
      '2.5M MCP calls / mo',
      '100K KG nodes',
      '25 users',
      'Priority support',
    ],
    cta: 'Try Team',
    ctaLink: '/plans',
  },
  {
    name: 'Enterprise',
    price: 'Custom',
    cadence: '',
    description: 'For organizations with custom requirements.',
    features: [
      'Unlimited agents',
      'Unlimited MCP calls',
      'SAML / OIDC SSO',
      'Compliance snapshots',
      'Dedicated support + SLA',
      'Cross-region federation',
    ],
    cta: 'Contact sales',
    ctaLink: '/pages/contact',
  },
];

export const PricingPage: React.FC = () => {
  return (
    <PublicPageContainer
      title="Pricing"
      description="Self-host the OSS for free, or use the managed Cloud. Same code; different operations model."
      mainNav={[
        { label: 'Pricing', path: '/pricing' },
        { label: 'Features', path: '/features' },
      ]}
    >
      <section className="py-12">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-8">
            {tiers.map(tier => (
              <div
                key={tier.name}
                className={`relative p-8 rounded-2xl ${tier.highlighted
                  ? 'bg-theme-info/5 border-2 border-theme-info-solid'
                  : 'bg-theme-background border border-theme'}`}
              >
                {tier.highlighted && (
                  <div className="absolute -top-3 left-1/2 -translate-x-1/2 px-3 py-1 bg-theme-info-solid text-white text-xs font-bold rounded-full uppercase tracking-wider">
                    Recommended
                  </div>
                )}
                <h3 className="text-2xl font-bold text-theme-primary mb-2">{tier.name}</h3>
                <div className="mb-4">
                  <span className="text-4xl font-extrabold text-theme-primary">{tier.price}</span>
                  <span className="text-theme-secondary">{tier.cadence}</span>
                </div>
                <p className="text-sm text-theme-secondary mb-6 leading-relaxed">{tier.description}</p>
                <ul className="space-y-3 mb-8">
                  {tier.features.map((feature, i) => (
                    <li key={i} className="flex items-start space-x-2 text-sm text-theme-primary">
                      <Check className="w-4 h-4 mt-0.5 text-theme-success-solid flex-shrink-0" />
                      <span>{feature}</span>
                    </li>
                  ))}
                </ul>
                <Link
                  to={tier.ctaLink}
                  className={`inline-flex items-center justify-center space-x-2 w-full px-6 py-3 rounded-xl font-semibold transition-all duration-200 ${tier.highlighted
                    ? 'bg-theme-info-solid hover:bg-theme-interactive-primary-hover text-white shadow-lg hover:shadow-xl'
                    : 'bg-theme-surface hover:bg-theme-background-secondary text-theme-primary border border-theme'}`}
                  data-testid={`pricing-cta-${tier.name.toLowerCase()}`}
                >
                  <span>{tier.cta}</span>
                  <ArrowRight className="w-4 h-4" />
                </Link>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section className="py-16 bg-theme-background-secondary mt-12">
        <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
          <h2 className="text-3xl md:text-4xl font-bold text-theme-primary mb-4">Or self-host the OSS</h2>
          <p className="text-lg text-theme-secondary mb-6 leading-relaxed">
            Same code we run on the Cloud, MIT-licensed. Bring your own infrastructure and ops.
            Optional commercial license + premium support contracts available for procurement-friendly buyers.
          </p>
          <a
            href="https://github.com/rett/powernode-system"
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center space-x-2 px-6 py-3 bg-theme-surface hover:bg-theme-background text-theme-primary font-semibold rounded-xl border border-theme transition-all duration-200"
          >
            <span>View on GitHub</span>
            <ArrowRight className="w-4 h-4" />
          </a>
        </div>
      </section>

      <section className="py-16">
        <div className="max-w-3xl mx-auto px-4 sm:px-6 lg:px-8">
          <h2 className="text-3xl md:text-4xl font-bold text-theme-primary text-center mb-12">Common questions</h2>
          <div className="space-y-6">
            <div className="p-6 bg-theme-background rounded-xl border border-theme">
              <h3 className="text-lg font-bold text-theme-primary mb-2">What counts as an agent?</h3>
              <p className="text-theme-secondary leading-relaxed">
                Any unique agent identity registered in your powernode instance &mdash; whether persistent (long-running)
                or ephemeral (per-task). Idle agents don&apos;t count toward your usage; only active agents that
                executed at least one MCP call in the billing period.
              </p>
            </div>
            <div className="p-6 bg-theme-background rounded-xl border border-theme">
              <h3 className="text-lg font-bold text-theme-primary mb-2">Can I switch between self-host and Cloud?</h3>
              <p className="text-theme-secondary leading-relaxed">
                Yes. Same codebase, same data formats. Migration tooling for export/import is on the roadmap.
              </p>
            </div>
            <div className="p-6 bg-theme-background rounded-xl border border-theme">
              <h3 className="text-lg font-bold text-theme-primary mb-2">Is the Cloud SOC 2 / HIPAA / GDPR compliant?</h3>
              <p className="text-theme-secondary leading-relaxed">
                Compliance certifications are on the Enterprise tier roadmap. Self-host gives you full data control
                today; the OSS code already includes audit-trail and compliance-snapshot infrastructure.
              </p>
            </div>
            <div className="p-6 bg-theme-background rounded-xl border border-theme">
              <h3 className="text-lg font-bold text-theme-primary mb-2">Why MIT and not AGPL?</h3>
              <p className="text-theme-secondary leading-relaxed">
                We&apos;re selling services, not code. MIT removes adoption friction for corporate procurement and
                aligns our incentives with the community: we get paid when you choose the Cloud, not because the
                license forces you.
              </p>
            </div>
          </div>
        </div>
      </section>
    </PublicPageContainer>
  );
};
