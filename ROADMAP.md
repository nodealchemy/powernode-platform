# Roadmap

What we're planning, organized by quarter rather than by date. This is **directional, not committed** — a single-maintainer project (see [`GOVERNANCE.md`](GOVERNANCE.md)) reprioritizes as reality demands, items move between quarters, and some won't happen. Roadmap discussion happens in the open in **[GitHub Discussions](https://github.com/nodealchemy/powernode-platform/discussions)**; that's the place to push back or suggest something missing.

Items tagged **`Commercial`** relate to the business extension (multi-tenant SaaS, billing, enterprise) maintained by Node Alchemy LLC and are not part of the MIT open-source release — see the open-core boundary in [`README.md`](README.md). Everything else is core/community work under MIT.

Distilled and grouped from the auto-generated project status in [`docs/reference/auto/todo.md`](docs/reference/auto/todo.md) — that file is the live source; this is the human-readable, deduplicated view.

## This quarter (near term)

- **Production deployment baseline** — Stand up production hosting for the API, frontend, and worker, with PostgreSQL + pgvector tuned (pooling, backups). _(todo.md: production hosting + production database)_
- **Core test coverage** — Auth controller tests, comprehensive model tests, full factory coverage, and integration tests for critical flows (signup, subscription lifecycle). _(todo.md: Phase 1 backend foundation)_
- **Security monitoring & incident response** — Monitoring, alerting, and a written incident-response procedure across services. _(todo.md: security monitoring and incident response)_
- **Pre-launch security audit** — A final security audit and penetration test before any production launch. _(todo.md: final security audit and penetration testing)_

## Next quarter

- **Operational visibility** — Centralized log aggregation and analysis for all platform services. _(todo.md: log aggregation and analysis)_
- **Frontend performance & delivery** — CDN for static assets to cut load times and server load. _(todo.md: configure CDN)_
- **Accessibility & cross-browser** — WCAG compliance work and cross-browser testing (Chrome, Firefox, Safari, Edge). _(todo.md: accessibility + cross-browser)_
- **Frontend test hardening** — Continue lifting frontend test pass-rate toward a stable high bar. _(todo.md: test optimization session 4)_

## Later / directional

- **Compliance documentation** — Buyer-credible security, privacy, and regulatory documentation, building on the existing [`SECURITY.md`](SECURITY.md) posture. _(todo.md: compliance documentation)_
- **`Commercial` — Hosted multi-tenant beta** — Run Powernode as a hosted service on the business extension (tenant isolation, billing in test mode, signup/waitlist). Gated on the deployment and security work above.
- **`Commercial` — Enterprise compliance packs** — Enterprise compliance tier, including the PCI DSS certification path for payment processing. _(todo.md: PCI DSS compliance certification)_
- **`Commercial` — Module marketplace groundwork (year-two option)** — Explore signed third-party module distribution with revenue share. Not started; revisited only if external module authors appear organically.

---

_Have a view on priorities? Open a thread in [GitHub Discussions](https://github.com/nodealchemy/powernode-platform/discussions)._
