# 🚀 Powernode Platform

> **A modern subscription management platform built for scale and developer happiness**

Welcome to Powernode! This is a comprehensive subscription lifecycle management platform designed with modern best practices, extensive testing, and developer-first experience.

## ✨ What is Powernode?

Powernode is a full-stack subscription platform that handles everything from user authentication to automated billing. Built with Rails 8, React TypeScript, and battle-tested patterns, it's designed to be both powerful and maintainable.

### 🎯 Key Features

- **🔐 Enterprise Authentication** - JWT-based auth with strong security (12+ char passwords, account lockout, rate limiting)
- **💳 Payment Processing** - Stripe & PayPal integration with PCI compliance
- **📊 Smart Analytics** - MRR/ARR calculations, churn analysis, and customer insights
- **🧪 Testing Excellence** - 628+ tests with 100% coverage across the stack
- **⚡ Real-time Features** - WebSocket integration for live updates
- **🎨 Modern UI** - React TypeScript with Tailwind CSS and theme support
- **🤖 Background Jobs** - Sidekiq-powered async processing
- **📝 Comprehensive Docs** - 47+ documentation files with specialist guides

## 🏗️ Architecture Overview

```
powernode-platform/
├── 🖥️  server/     - Rails 8 API (JWT, UUIDv7, PostgreSQL)
├── ⚛️  frontend/   - React TypeScript (Tailwind, Redux)  
├── ⚙️  worker/     - Sidekiq Background Jobs
├── 📚 docs/       - Comprehensive Documentation
└── 🛠️  scripts/   - Development Automation
```

### 🔧 Technology Stack

**Backend**: Rails 8 API • PostgreSQL • UUIDv7 • JWT Authentication • Redis  
**Frontend**: React 18 • TypeScript • Tailwind CSS • Redux • Vite  
**Background**: Sidekiq • Redis • API-first communication  
**Payments**: Stripe • PayPal • PCI DSS Compliance  
**Testing**: RSpec • Jest • Cypress • 628+ tests  

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

# One-command development startup (optimized!)
./scripts/auto-dev.sh ensure

# Or individual services
cd server && ./bin/dev      # Rails API (port 3000)
cd frontend && npm run dev  # React app (port 3001)
cd worker && ./bin/dev      # Background jobs
```

**That's it!** 🎉 Your platform is running:
- **Frontend**: http://localhost:3001
- **API**: http://localhost:3000
- **Background Jobs**: Running automatically

## 📊 Platform Status

The platform is **production-ready** with:

- ✅ **100% Test Coverage** - All 628+ tests passing
- ✅ **95%+ Pattern Consistency** - Standardized architecture
- ✅ **18+ Specialist Docs** - Comprehensive guides
- ✅ **Security First** - PCI compliance, strong auth
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
Visit: **[docs/testing/TESTING_DOCUMENTATION_MASTER.md](docs/testing/TESTING_DOCUMENTATION_MASTER.md)**

## 🎯 Specialist Documentation

Powernode uses MCP (Model Context Protocol) specialists for different areas:

### Backend Specialists
- **[Rails Architect](docs/backend/RAILS_ARCHITECT_SPECIALIST.md)** - API architecture & patterns
- **[Data Modeler](docs/backend/DATA_MODELER_SPECIALIST.md)** - Database & ActiveRecord
- **[Payment Integration](docs/backend/PAYMENT_INTEGRATION_SPECIALIST.md)** - Stripe/PayPal
- **[Billing Engine](docs/backend/BILLING_ENGINE_DEVELOPER_SPECIALIST.md)** - Subscription lifecycle

### Frontend Specialists  
- **[React Architect](docs/frontend/REACT_ARCHITECT_SPECIALIST.md)** - TypeScript architecture
- **[UI Components](docs/frontend/UI_COMPONENT_DEVELOPER_SPECIALIST.md)** - Design system
- **[Dashboard](docs/frontend/DASHBOARD_SPECIALIST.md)** - Analytics & charts
- **[Admin Panel](docs/frontend/ADMIN_PANEL_DEVELOPER_SPECIALIST.md)** - Management interfaces

### Infrastructure & Testing
- **[DevOps Engineer](docs/infrastructure/DEVOPS_ENGINEER_SPECIALIST.md)** - CI/CD & deployment
- **[Security Specialist](docs/infrastructure/SECURITY_SPECIALIST.md)** - Security & compliance
- **[Testing Engineers](docs/testing/)** - Comprehensive test strategies

## 🌟 Key Highlights

### 💪 **Built for Scale**
- **UUIDv7 Strategy**: Chronologically sortable IDs across 64+ models
- **Background Processing**: Async job handling with retry logic
- **API-First**: Clean separation between services
- **Theme System**: Dark/light mode with accessibility

### 🔒 **Security First**
- **Strong Authentication**: 12+ char passwords, complexity rules, lockout
- **PCI Compliance**: Secure payment data handling
- **Rate Limiting**: DDoS protection on all endpoints
- **Audit Logging**: Comprehensive activity tracking

### 🎨 **Developer Experience**
- **Pattern Consistency**: Standardized code patterns across the platform
- **Comprehensive Testing**: Every feature backed by tests
- **Rich Documentation**: 47+ docs covering every aspect
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

> 💡 **Pro Tip**: Use `./scripts/auto-dev.sh status` to check all services at once!