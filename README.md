# 🚀 Powernode Platform

> **A modern subscription management platform with integrated AI orchestration, built for scale and developer happiness**

Welcome to Powernode! This is a comprehensive subscription lifecycle management platform with powerful AI capabilities, designed with modern best practices, extensive testing, and developer-first experience.

## ✨ What is Powernode?

Powernode is a full-stack subscription platform that handles everything from user authentication to automated billing, enhanced with AI-powered automation and agent orchestration. Built with Rails 8, React TypeScript, and battle-tested patterns, it's designed to be both powerful and maintainable.

### 🎯 Key Features

#### Core Platform
- **🔐 Enterprise Authentication** - JWT-based auth with strong security (12+ char passwords, account lockout, rate limiting)
- **💳 Payment Processing** - Stripe & PayPal integration with PCI compliance
- **📊 Smart Analytics** - MRR/ARR calculations, churn analysis, and customer insights
- **⚡ Real-time Features** - WebSocket integration for live updates
- **🎨 Modern UI** - React TypeScript with Tailwind CSS and theme support
- **🤖 Background Jobs** - Sidekiq-powered async processing
- **🔑 Permission-Based Access** - Granular permission system (no role-based checks)

#### AI & Automation
- **🤖 AI Agents** - Create and manage intelligent automation agents
- **🔗 A2A Protocol** - Agent-to-Agent communication for distributed AI workflows
- **🪪 Agent Cards** - A2A-compliant agent discovery and capability declaration
- **👥 Agent Teams** - CrewAI-style multi-agent orchestration
- **🔌 MCP Servers** - Model Context Protocol integration for tool access
- **💬 AI Conversations** - Persistent AI-powered chat with context
- **⚡ AI Workflows** - Visual workflow builder for AI orchestration
- **📝 Prompt Templates** - Reusable, versioned prompt management
- **🧠 Agent Memory** - Persistent context and learning for agents
- **📈 AI Monitoring** - Real-time metrics, alerts, and performance tracking

#### DevOps & Infrastructure
- **🔧 Git Integration** - GitHub, GitLab, Gitea provider support
- **📦 Supply Chain Security** - SBOM generation, attestations, license compliance
- **🛡️ Audit Logging** - Comprehensive activity tracking and compliance
- **⚙️ Worker Management** - Background job monitoring and control

#### Quality & Testing
- **🧪 Testing Excellence** - 20,600+ tests with comprehensive coverage
- **📝 Comprehensive Docs** - 90+ documentation files with specialist guides

## 🏗️ Architecture Overview

```
powernode-platform/
├── 🖥️  server/     - Rails 8 API (JWT, UUIDv7, PostgreSQL)
│   ├── app/models/ai/    - 30+ AI models (Agents, A2A, Workflows)
│   ├── app/services/ai/  - AI orchestration services
│   └── app/controllers/  - RESTful API endpoints
├── ⚛️  frontend/   - React TypeScript (Tailwind, Redux)
│   └── src/features/ai/  - AI UI components & pages
├── ⚙️  worker/     - Sidekiq Background Jobs
├── 📚 docs/       - Comprehensive Documentation (90+ files)
└── 🛠️  scripts/   - Development Automation
```

### 🔧 Technology Stack

- **Backend**: Rails 8 API • PostgreSQL • UUIDv7 • JWT Authentication • Redis
- **Frontend**: React 18 • TypeScript • Tailwind CSS • Redux • Vite
- **Background**: Sidekiq • Redis • API-first communication
- **Payments**: Stripe • PayPal • PCI DSS Compliance
- **AI/ML**: OpenAI • Anthropic • MCP Protocol • A2A Protocol
- **Testing**: RSpec • Jest • Cypress • 20,600+ tests  

## 🚀 Quick Start

### Prerequisites
- Ruby 3.3+
- Node.js 18+
- PostgreSQL 15+
- Redis 7+

### 🏃‍♂️ Get Running in 60 Seconds

```bash
# Clone and setup
git clone <repository>
cd powernode-platform

# Install systemd services (one-time)
sudo scripts/systemd/powernode-installer.sh install

# Start all services
sudo systemctl start powernode.target

# Check status
sudo scripts/systemd/powernode-installer.sh status
```

**That's it!** 🎉 Your platform is running:
- **Frontend**: http://localhost:3001
- **API**: http://localhost:3000
- **Worker Web UI**: http://localhost:4567
- **Background Jobs**: Running automatically

## 📊 Platform Status

The platform is **production-ready** with:

- ✅ **Comprehensive Testing** - 20,600+ tests (14,500 backend, 6,100 frontend)
- ✅ **95%+ Pattern Consistency** - Standardized architecture
- ✅ **90+ Documentation Files** - Comprehensive guides and specialist docs
- ✅ **Security First** - PCI compliance, strong auth, permission-based access
- ✅ **AI-Powered** - Full AI orchestration with A2A protocol support
- ✅ **Performance Optimized** - Sub-second response times
- ✅ **Modern DevOps** - Git-flow, semantic versioning, CI/CD ready

## 🗺️ Navigation Guide

### 📚 **New to the Project?**
Start here: **[docs/README.md](docs/README.md)** - Complete documentation index

### 🛠️ **Want to Develop?**
Check out: **[CLAUDE.md](CLAUDE.md)** - Development guidance and patterns

### 📋 **Track Progress?**
See: **[docs/TODO.md](docs/TODO.md)** - Current status and roadmap

### 🧪 **Testing & Quality?**
See specialists: **[Backend Test Engineer](docs/testing/BACKEND_TEST_ENGINEER_SPECIALIST.md)** | **[Frontend Test Engineer](docs/testing/FRONTEND_TEST_ENGINEER_SPECIALIST.md)**

## 🎯 Specialist Documentation

Powernode uses MCP (Model Context Protocol) specialists for different areas:

### Backend Specialists
- **[Rails Architect](docs/backend/RAILS_ARCHITECT_SPECIALIST.md)** - API architecture & patterns
- **[Data Modeler](docs/backend/DATA_MODELER_SPECIALIST.md)** - Database & ActiveRecord
- **[Payment Integration](docs/backend/PAYMENT_INTEGRATION_SPECIALIST.md)** - Stripe/PayPal
- **[Billing Engine](docs/backend/BILLING_ENGINE_DEVELOPER_SPECIALIST.md)** - Subscription lifecycle
- **[Background Jobs](docs/backend/BACKGROUND_JOB_ENGINEER_SPECIALIST.md)** - Sidekiq & async processing

### Frontend Specialists
- **[React Architect](docs/frontend/REACT_ARCHITECT_SPECIALIST.md)** - TypeScript architecture
- **[UI Components](docs/frontend/UI_COMPONENT_DEVELOPER_SPECIALIST.md)** - Design system
- **[Dashboard](docs/frontend/DASHBOARD_SPECIALIST.md)** - Analytics & charts
- **[Admin Panel](docs/frontend/ADMIN_PANEL_DEVELOPER_SPECIALIST.md)** - Management interfaces

### Infrastructure & Testing
- **[DevOps Engineer](docs/infrastructure/DEVOPS_ENGINEER_SPECIALIST.md)** - CI/CD & deployment
- **[Security Specialist](docs/infrastructure/SECURITY_SPECIALIST.md)** - Security & compliance
- **[Performance Optimizer](docs/infrastructure/PERFORMANCE_OPTIMIZER.md)** - Performance tuning
- **[Testing Engineers](docs/testing/)** - Comprehensive test strategies

### Platform References
- **[Permission System](docs/platform/PERMISSION_SYSTEM_REFERENCE.md)** - Access control guide
- **[Theme System](docs/platform/THEME_SYSTEM_REFERENCE.md)** - UI theming
- **[API Standards](docs/platform/API_RESPONSE_STANDARDS.md)** - API conventions
- **[UUID System](docs/platform/UUID_SYSTEM_IMPLEMENTATION.md)** - UUIDv7 implementation

## 🌟 Key Highlights

### 💪 **Built for Scale**
- **UUIDv7 Strategy**: Chronologically sortable IDs across 64+ models
- **Background Processing**: Async job handling with retry logic
- **API-First**: Clean separation between services
- **Theme System**: Dark/light mode with accessibility
- **Multi-tenant**: Account-based isolation with permission controls

### 🤖 **AI-Powered**
- **Agent Orchestration**: Create, deploy, and manage AI agents
- **A2A Protocol**: Industry-standard agent-to-agent communication
- **MCP Integration**: Model Context Protocol for tool access
- **Multi-Provider**: OpenAI, Anthropic, and custom provider support
- **Workflow Builder**: Visual AI workflow orchestration

### 🔒 **Security First**
- **Strong Authentication**: 12+ char passwords, complexity rules, lockout
- **Permission-Based Access**: Granular permissions, no role-based checks
- **PCI Compliance**: Secure payment data handling
- **Rate Limiting**: DDoS protection on all endpoints
- **Audit Logging**: Comprehensive activity tracking

### 🎨 **Developer Experience**
- **Pattern Consistency**: Standardized code patterns across the platform
- **Comprehensive Testing**: 20,600+ tests covering every feature
- **Rich Documentation**: 90+ docs covering every aspect
- **Development Scripts**: Automated setup and management

## 🚀 What's Next?

The platform is currently in **Phase 6: DevOps & Production**, focusing on:
- Production deployment automation
- Performance monitoring
- Advanced CI/CD pipelines
- Scalability optimizations

## 🤝 Contributing

This platform follows strict architectural patterns and testing requirements. Before contributing:

1. Read **[CLAUDE.md](CLAUDE.md)** for development guidelines
2. Check **[docs/TODO.md](docs/TODO.md)** for current priorities  
3. Review specialist documentation for your area of contribution
4. Ensure all tests pass before submitting changes

## 📄 License

See **[LICENSE](LICENSE)** for licensing information.

---

**Happy coding!** 🎉 Welcome to the Powernode platform - where subscription management meets modern development practices.

> 💡 **Pro Tip**: Use `sudo scripts/systemd/powernode-installer.sh status` to check all services at once!