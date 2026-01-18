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
│   ├── New tables, migrations ───────────► Data Modeler (sonnet)
│   ├── Query optimization ───────────────► Data Modeler (sonnet)
│   └── Data relationships ───────────────► Data Modeler (sonnet)
│
├── API endpoint work?
│   ├── New endpoint ─────────────────────► API Developer (sonnet)
│   ├── Authentication/Authorization ─────► API Developer (sonnet)
│   └── API versioning ───────────────────► API Developer (sonnet)
│
├── Background job?
│   ├── Sidekiq job creation ─────────────► Background Jobs (sonnet)
│   ├── Job scheduling ───────────────────► Background Jobs (sonnet)
│   └── Queue management ─────────────────► Background Jobs (sonnet)
│
├── Architecture decision?
│   ├── Service design ───────────────────► Rails Architect (sonnet)
│   ├── Code organization ────────────────► Rails Architect (sonnet)
│   └── Pattern implementation ───────────► Rails Architect (sonnet)
│
└── Testing?
    └── Any backend test ─────────────────► Backend Testing (sonnet)
```

## Frontend Decision Tree

```
Working on Frontend?
│
├── UI Component?
│   ├── Simple/reusable component ────────► UI Components (haiku)
│   ├── Form components ──────────────────► UI Components (haiku)
│   └── Button, input, card, etc. ────────► UI Components (haiku)
│
├── Feature/Page?
│   ├── Dashboard page ───────────────────► Dashboard (sonnet)
│   ├── Admin panel ──────────────────────► Admin Panel (sonnet)
│   └── Complex feature ──────────────────► React Architect (sonnet)
│
├── Architecture?
│   ├── State management ─────────────────► React Architect (sonnet)
│   ├── Routing ──────────────────────────► React Architect (sonnet)
│   └── Code organization ────────────────► React Architect (sonnet)
│
└── Testing?
    └── Any frontend test ────────────────► Frontend Testing (haiku)
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
│   ├── Email ────────────────────────────► Notification Engineer (sonnet)
│   ├── Push notifications ───────────────► Notification Engineer (sonnet)
│   └── In-app notifications ─────────────► Notification Engineer (sonnet)
│
├── Documentation?
│   ├── API docs ─────────────────────────► Documentation (haiku)
│   ├── User guides ──────────────────────► Documentation (haiku)
│   └── Technical docs ───────────────────► Documentation (haiku)
│
└── Project planning?
    └── Task planning ────────────────────► Project Manager (sonnet)
```

## Model Selection Reference

### When to Use Opus (Complex/Critical Tasks)

| Specialist | Use For |
|------------|---------|
| Payment Integration | Stripe/PayPal integration, PCI compliance |
| Billing Engine | Complex billing logic, subscription management |
| Security | Authentication, authorization, vulnerability fixes |
| Performance | Critical optimizations, caching strategies |
| DevOps Engineer | Production deployments, infrastructure |
| Analytics Engineer | Complex data pipelines, reporting |

### When to Use Sonnet (Standard Tasks)

| Specialist | Use For |
|------------|---------|
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

### When to Use Haiku (Simple/Routine Tasks)

| Specialist | Use For |
|------------|---------|
| UI Components | Simple components, forms |
| Frontend Testing | Jest tests |
| Documentation | Documentation updates |

## Task Tool Usage

```javascript
// Example: Complex payment integration
Task({
  description: "Implement Stripe checkout",
  subagent_type: "general-purpose",
  model: "opus",
  prompt: `You are a Payment Integration Specialist for Powernode.
Reference: docs/backend/PAYMENT_INTEGRATION_SPECIALIST.md
Task: Implement Stripe checkout flow
Follow patterns in specialist documentation.`
})

// Example: Simple UI component
Task({
  description: "Create toggle switch component",
  subagent_type: "general-purpose",
  model: "haiku",
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
| Rails architecture | Rails Architect | sonnet |
| Database schema | Data Modeler | sonnet |
| API endpoints | API Developer | sonnet |
| Background jobs | Background Jobs | sonnet |
| React architecture | React Architect | sonnet |
| Dashboard UI | Dashboard | sonnet |
| Admin pages | Admin Panel | sonnet |
| Backend tests | Backend Testing | sonnet |
| Notifications | Notification Engineer | sonnet |
| Project planning | Project Manager | sonnet |
| UI components | UI Components | haiku |
| Frontend tests | Frontend Testing | haiku |
| Documentation | Documentation | haiku |

## Tips

1. **Start with the right model** - Use opus for critical/complex tasks, sonnet for standard work, haiku for routine tasks
2. **Reference specialist docs** - Always include the path to the specialist documentation
3. **Be specific** - Clear, specific prompts get better results
4. **Parallel agents** - Spawn multiple agents in parallel when tasks are independent
5. **Check the index** - See `/docs/CLAUDE.md` for the full specialist index
