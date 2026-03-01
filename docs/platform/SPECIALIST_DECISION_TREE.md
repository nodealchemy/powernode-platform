---
Last Updated: 2026-01-17
Platform Version: 1.0.0
---

# Specialist Decision Tree

Quick reference for choosing the right specialist agent when using the Task tool.

## Quick Selection Flowchart

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        What are you working on?                              │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        │                           │                           │
        ▼                           ▼                           ▼
   [Backend]                   [Frontend]                [Infrastructure]
        │                           │                           │
        ▼                           ▼                           ▼
   See Backend                 See Frontend              See Infrastructure
   Decision Tree               Decision Tree             Decision Tree
```

## Backend Decision Tree

```
Working on Backend?
│
├── Payment/Billing related?
│   ├── Payment gateway integration ──────► Payment Integration (opus)
│   ├── Billing cycles, invoicing ────────► Billing Engine (opus)
│   └── Subscription logic ───────────────► Billing Engine (opus)
│
├── Database/Schema changes?
│   ├── New tables, migrations ───────────► Data Modeler (opus)
│   ├── Query optimization ───────────────► Data Modeler (opus)
│   └── Data relationships ───────────────► Data Modeler (opus)
│
├── API endpoint work?
│   ├── New endpoint ─────────────────────► API Developer (opus)
│   ├── Authentication/Authorization ─────► API Developer (opus)
│   └── API versioning ───────────────────► API Developer (opus)
│
├── Background job?
│   ├── Sidekiq job creation ─────────────► Background Jobs (opus)
│   ├── Job scheduling ───────────────────► Background Jobs (opus)
│   └── Queue management ─────────────────► Background Jobs (opus)
│
├── Architecture decision?
│   ├── Service design ───────────────────► Rails Architect (opus)
│   ├── Code organization ────────────────► Rails Architect (opus)
│   └── Pattern implementation ───────────► Rails Architect (opus)
│
└── Testing?
    └── Any backend test ─────────────────► Backend Testing (opus)
```

## Frontend Decision Tree

```
Working on Frontend?
│
├── UI Component?
│   ├── Simple/reusable component ────────► UI Components (opus)
│   ├── Form components ──────────────────► UI Components (opus)
│   └── Button, input, card, etc. ────────► UI Components (opus)
│
├── Feature/Page?
│   ├── Dashboard page ───────────────────► Dashboard (opus)
│   ├── Admin panel ──────────────────────► Admin Panel (opus)
│   └── Complex feature ──────────────────► React Architect (opus)
│
├── Architecture?
│   ├── State management ─────────────────► React Architect (opus)
│   ├── Routing ──────────────────────────► React Architect (opus)
│   └── Code organization ────────────────► React Architect (opus)
│
└── Testing?
    └── Any frontend test ────────────────► Frontend Testing (opus)
```

## Infrastructure Decision Tree

```
Working on Infrastructure?
│
├── Security related?
│   ├── Authentication ───────────────────► Security (opus)
│   ├── Authorization ────────────────────► Security (opus)
│   ├── Vulnerability fixes ──────────────► Security (opus)
│   └── Security audit ───────────────────► Security (opus)
│
├── Performance?
│   ├── Optimization ─────────────────────► Performance (opus)
│   ├── Caching ──────────────────────────► Performance (opus)
│   └── Load testing ─────────────────────► Performance (opus)
│
├── DevOps?
│   ├── Docker/Kubernetes ────────────────► DevOps Engineer (opus)
│   ├── CI/CD pipelines ──────────────────► DevOps Engineer (opus)
│   ├── Deployment ───────────────────────► DevOps Engineer (opus)
│   └── Monitoring ───────────────────────► DevOps Engineer (opus)
│
└── Analytics?
    ├── Metrics ──────────────────────────► Analytics Engineer (opus)
    ├── Reporting ────────────────────────► Analytics Engineer (opus)
    └── Data pipelines ───────────────────► Analytics Engineer (opus)
```

## Service Decision Tree

```
Working on Services?
│
├── Notifications?
│   ├── Email ────────────────────────────► Notification Engineer (opus)
│   ├── Push notifications ───────────────► Notification Engineer (opus)
│   └── In-app notifications ─────────────► Notification Engineer (opus)
│
├── Documentation?
│   ├── API docs ─────────────────────────► Documentation (opus)
│   ├── User guides ──────────────────────► Documentation (opus)
│   └── Technical docs ───────────────────► Documentation (opus)
│
└── Project planning?
    └── Task planning ────────────────────► Project Manager (opus)
```

## Model Selection Reference

### All Specialists Use Opus 4.5

| Specialist | Use For |
|------------|---------|
| Payment Integration | Stripe/PayPal integration, PCI compliance |
| Billing Engine | Complex billing logic, subscription management |
| Security | Authentication, authorization, vulnerability fixes |
| Performance | Critical optimizations, caching strategies |
| DevOps Engineer | Production deployments, infrastructure |
| Analytics Engineer | Complex data pipelines, reporting |
| Rails Architect | Architecture decisions, code organization |
| Data Modeler | Database design, migrations |
| API Developer | New endpoints, API changes |
| Background Jobs | Job creation, scheduling |
| React Architect | Frontend architecture, state management |
| Dashboard | Dashboard pages, widgets |
| Admin Panel | Admin interfaces |
| Backend Testing | RSpec tests |
| Notification Engineer | Notification systems |
| Project Manager | Task planning |
| UI Components | Simple components, forms |
| Frontend Testing | Jest tests |
| Documentation | Documentation updates |

## Task Tool Usage

```javascript
// Example: Payment integration
Task({
  description: "Implement Stripe checkout",
  subagent_type: "general-purpose",
  model: "opus",
  prompt: `You are a Payment Integration Specialist for Powernode.
Reference: docs/backend/PAYMENT_INTEGRATION_SPECIALIST.md
Task: Implement Stripe checkout flow
Follow patterns in specialist documentation.`
})

// Example: UI component
Task({
  description: "Create toggle switch component",
  subagent_type: "general-purpose",
  model: "opus",
  prompt: `You are a UI Component Developer for Powernode.
Reference: docs/frontend/UI_COMPONENT_DEVELOPER_SPECIALIST.md
Task: Create a theme-aware toggle switch component
Follow patterns in specialist documentation.`
})
```

## Quick Reference Table

| If working on... | Use Specialist | Model |
|------------------|----------------|-------|
| Stripe/PayPal | Payment Integration | opus |
| Billing logic | Billing Engine | opus |
| Auth/security | Security | opus |
| Performance | Performance Optimizer | opus |
| Docker/K8s | DevOps Engineer | opus |
| Data analytics | Analytics Engineer | opus |
| Rails architecture | Rails Architect | opus |
| Database schema | Data Modeler | opus |
| API endpoints | API Developer | opus |
| Background jobs | Background Jobs | opus |
| React architecture | React Architect | opus |
| Dashboard UI | Dashboard | opus |
| Admin pages | Admin Panel | opus |
| Backend tests | Backend Testing | opus |
| Notifications | Notification Engineer | opus |
| Project planning | Project Manager | opus |
| UI components | UI Components | opus |
| Frontend tests | Frontend Testing | opus |
| Documentation | Documentation | opus |

## Tips

1. **All specialists use Opus 4.5** - Maximum reasoning capability for all tasks
2. **Reference specialist docs** - Always include the path to the specialist documentation
3. **Be specific** - Clear, specific prompts get better results
4. **Parallel agents** - Spawn multiple agents in parallel when tasks are independent
5. **Check the index** - See `/docs/CLAUDE.md` for the full specialist index
