# frozen_string_literal: true

# Minimal production seed data
# This file contains only essential data needed for all environments

puts "🌱 Seeding Powernode platform..."

# Sync permissions and roles from configuration
puts "📝 Creating permissions and roles from configuration..."
Permission.sync_from_config!
puts "✅ Created #{Permission.count} permissions"

Role.sync_from_config!
puts "✅ Created #{Role.count} roles"

# Validate permission system integrity
puts "\n🔍 Validating permission system integrity..."
validation_issues = []

# Check for super_admin role
super_admin_role = Role.find_by(name: 'super_admin')
if super_admin_role.nil?
  validation_issues << "Critical: super_admin role not found!"
else
  # Verify super_admin has system.admin permission
  unless super_admin_role.permissions.exists?(name: 'system.admin')
    validation_issues << "Critical: super_admin role missing system.admin permission!"
  end
end

# Check for system.admin permission
system_admin_perm = Permission.find_by(name: 'system.admin')
if system_admin_perm.nil?
  validation_issues << "Critical: system.admin permission not found!"
end

# Check permission categories
permission_categories = Permission.pluck(:name).map { |name| name.split('.').first }.uniq
expected_categories = [ 'users', 'admin', 'billing', 'system', 'analytics', 'pages', 'storage' ]
missing_categories = expected_categories - permission_categories

if missing_categories.any?
  validation_issues << "Warning: Missing permission categories: #{missing_categories.join(', ')}"
end

# Report validation results
if validation_issues.empty?
  puts "✅ Permission system validation passed"
  puts "   Total Permissions: #{Permission.count}"
  puts "   Total Roles: #{Role.count}"
  puts "   Permission Categories: #{permission_categories.count} (#{permission_categories.join(', ')})"
else
  puts "⚠️  Permission system validation found #{validation_issues.count} issues:"
  validation_issues.each { |issue| puts "   - #{issue}" }
  if validation_issues.any? { |i| i.start_with?('Critical:') }
    puts "\n❌ Critical validation errors found. Please check permissions.rb configuration!"
  end
end

# Plans are seeded by the business extension (extensions/business/server/db/seeds/saas_plans_seed.rb)
# In core-only mode, no Plan model exists — all features are unlocked via FeatureGateService.

# Create system worker (required for worker-backend communication)
puts "🔧 Creating system worker..."

begin
  # Check if WORKER_TOKEN is set in environment
  worker_token = ENV['WORKER_TOKEN']
  if worker_token.blank?
    puts "⚠️ WORKER_TOKEN not found in environment - generating new token"
    worker_token = "swt_#{SecureRandom.urlsafe_base64(32)}"
    puts "💡 Set this token in your environment: WORKER_TOKEN=#{worker_token}"
  end

  system_worker = Worker.find_by(name: 'System Worker')
  # Workers should always belong to an account; system worker uses the admin account
  admin_account = Account.first

  if system_worker
    # Ensure system worker belongs to the admin account and is flagged as system
    updates = {}
    updates[:account_id] = admin_account&.id if system_worker.account_id != admin_account&.id
    updates[:is_system] = true unless system_worker.is_system?
    if updates.any?
      system_worker.update_columns(updates)
      puts "🔧 Updated system worker: #{updates.keys.join(', ')}"
    end
    puts "✅ System worker already exists"
  else
    system_worker = Worker.create_worker!(
      name: 'System Worker',
      description: 'System worker for background processing and API communication',
      account: admin_account,
      is_system: true,
      roles: [ 'system_worker' ],
      token: worker_token
    )
  end

  puts "✅ System worker created successfully"
  puts "   Token: #{system_worker.masked_token}"
  puts "   Roles: #{system_worker.role_names.join(', ')}"

rescue => e
  puts "❌ Failed to create system worker: #{e.message}"
  puts "   This may cause worker authentication issues"
end

# Only create admin account in development/test environments (or when SEED_ADMIN_USERS=true for Docker dev deploys)
if Rails.env.development? || Rails.env.test? || ENV['SEED_ADMIN_USERS'] == 'true'
  puts "\n🏢 Creating development/test accounts and users..."

  # Load the unified test user seed which handles all user creation
  # and writes credentials to test-credentials.json
  load Rails.root.join('db', 'seeds', 'cypress_test_users.rb')
end

# 📄 Create public pages
puts "\n📄 Creating public pages..."

# Get admin user as author
admin_user = User.find_by(email: 'admin@powernode.org')

# Welcome page
Page.find_or_create_by!(slug: 'welcome') do |page|
  page.title = 'Welcome to Powernode'
  page.author = admin_user
  page.status = 'published'
  page.meta_description = 'Streamline your subscription business with AI orchestration, DevOps integration, supply chain security, and automated billing.'
  page.meta_keywords = 'subscription management, billing automation, recurring revenue, SaaS platform, AI orchestration, DevOps, supply chain security'
  page.content = <<~MARKDOWN
    # Welcome to Powernode

    ## AI Orchestration & DevOps Platform

    Powernode is an integrated platform for AI agent orchestration, DevOps automation, and intelligent workflow management. Build, deploy, and manage AI-powered operations with confidence.

    ### 🤖 AI Orchestration

    - **Multi-Provider Support**: Connect OpenAI, Anthropic Claude, Grok, and local Ollama models
    - **AI Agents**: Build intelligent agents with custom prompts and workflows
    - **Workflow Automation**: Create visual workflows that orchestrate AI-powered tasks
    - **Agent Teams**: Compose multi-agent teams with role-based coordination
    - **Compound Learning**: AI systems that learn and improve from operational feedback

    ### 🔌 MCP (Model Context Protocol)

    - **Tool Registry**: 79+ platform tools accessible to AI agents via MCP
    - **Knowledge Graph**: Entity-aware reasoning across your entire platform
    - **RAG Integration**: Document ingestion, chunking, and semantic retrieval
    - **Shared Memory**: Tiered memory system (working, short-term, long-term, shared) for agent coordination
    - **Skill Discovery**: Agents discover and reuse capabilities across teams

    ### 🔧 DevOps Integration

    - **Git Providers**: Connect GitHub, GitLab, Gitea, and Bitbucket repositories
    - **CI/CD Pipelines**: Build, test, and deploy with automated pipelines
    - **Webhooks**: Real-time event notifications for 60+ event types
    - **API Keys**: Secure authentication for all integrations

    ### 📊 Analytics & Monitoring

    - **Real-time Dashboards**: Monitor AI agent performance and system health
    - **Workflow Metrics**: Track execution times, success rates, and resource usage
    - **Audit Logging**: Complete activity tracking across all operations

    ### 🛡️ Security & Compliance

    - **Role-Based Access**: Granular permissions and roles
    - **AI Safety**: OWASP-aligned agent anomaly detection and PII redaction
    - **Audit Trails**: Full traceability for all AI and DevOps operations

    ### 🎯 Get Started

    [Sign in](/login) to start building with Powernode.

    ---

    *Explore our [Knowledge Base](/kb) for detailed guides, or [contact our team](/pages/contact) for assistance.*
  MARKDOWN
end


# Terms of Service page
Page.find_or_create_by!(slug: 'terms') do |page|
  page.title = 'Terms of Service'
  page.author = admin_user
  page.status = 'published'
  page.meta_description = 'Terms of Service for Powernode subscription management platform including AI services, DevOps, and supply chain security.'
  page.meta_keywords = 'terms of service, legal, agreement, user agreement, AI terms, data processing'
  page.content = <<~MARKDOWN
    # Terms of Service

    **Last updated: #{Date.current.strftime('%B %d, %Y')}**

    ## 1. Acceptance of Terms

    By accessing and using Powernode ("Service"), you accept and agree to be bound by the terms and provision of this agreement.

    ## 2. Use License

    Permission is granted to temporarily access Powernode for personal, non-commercial transitory viewing only. This is the grant of a license, not a transfer of title, and under this license you may not:

    - Modify or copy the materials
    - Use the materials for any commercial purpose or for any public display
    - Attempt to reverse engineer any software contained on the website
    - Remove any copyright or other proprietary notations from the materials

    ## 3. Subscription Services

    ### 3.1 Service Availability
    We strive to maintain 99.9% uptime but do not guarantee uninterrupted service availability.

    ### 3.2 Billing and Payment
    - Subscription fees are billed in advance on a monthly or annual basis
    - All payments are non-refundable except as required by law
    - We reserve the right to change pricing with 30 days notice

    ### 3.3 Account Termination
    We may terminate accounts that violate these terms or engage in fraudulent activity.

    ## 4. AI Services and Usage

    ### 4.1 AI Provider Integration
    Powernode integrates with third-party AI providers (OpenAI, Anthropic, xAI, Ollama). Your use of AI features is subject to:
    - The respective AI provider's terms of service and usage policies
    - Token usage limits based on your subscription plan
    - Content policies prohibiting harmful, illegal, or abusive content

    ### 4.2 AI Data Processing
    - Prompts and responses may be processed by third-party AI providers
    - We do not use your AI interactions to train models without explicit consent
    - AI-generated content is provided "as is" without warranty of accuracy
    - You are responsible for reviewing and validating AI-generated outputs

    ### 4.3 AI Agents and Workflows
    - You retain ownership of AI agent configurations and workflows you create
    - Shared or marketplace-published agents are subject to licensing terms
    - We reserve the right to disable agents that violate usage policies

    ## 5. DevOps and Repository Integration

    ### 5.1 Git Provider Access
    - Repository access is limited to explicitly authorized repositories
    - Credentials are encrypted and stored securely
    - We do not access repository content beyond authorized operations

    ### 5.2 CI/CD Pipelines
    - Pipeline execution is subject to resource limits based on your plan
    - You are responsible for securing pipeline secrets and credentials
    - We are not liable for pipeline failures or deployment issues

    ## 6. Supply Chain Security Data

    ### 6.1 SBOM and Security Data
    - SBOM data you upload remains your property
    - Vulnerability data is sourced from public databases (NVD, OSV)
    - We do not guarantee completeness or accuracy of vulnerability detection

    ### 6.2 Vendor Information
    - Vendor risk assessments are based on information you provide
    - We are not liable for vendor compliance status accuracy

    ## 7. Privacy

    Your privacy is important to us. Please review our Privacy Policy, which also governs your use of the Service.

    ## 8. Data Security

    We implement industry-standard security measures to protect your data. However, no method of transmission over the Internet is 100% secure.

    ## 9. Limitation of Liability

    In no event shall Powernode be liable for any damages arising out of the use or inability to use the Service, including but not limited to AI-generated content, pipeline failures, or security vulnerabilities.

    ## 10. Governing Law

    These terms shall be governed by and construed in accordance with applicable laws.

    ## 11. Changes to Terms

    We reserve the right to modify these terms at any time. Users will be notified of significant changes.

    ## Contact Information

    Questions about these Terms of Service should be sent to: legal@powernode.org
  MARKDOWN
end

# Privacy Policy page
Page.find_or_create_by!(slug: 'privacy') do |page|
  page.title = 'Privacy Policy'
  page.author = admin_user
  page.status = 'published'
  page.meta_description = 'Privacy Policy for Powernode - learn how we collect, use, and protect your personal information including AI data processing.'
  page.meta_keywords = 'privacy policy, data protection, GDPR, personal information, cookies, AI privacy, data processing'
  page.content = <<~MARKDOWN
    # Privacy Policy

    **Last updated: #{Date.current.strftime('%B %d, %Y')}**

    ## Introduction

    Powernode ("we," "our," or "us") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our subscription management platform.

    ## Information We Collect

    ### Personal Information
    - Name and contact information
    - Billing and payment information
    - Account credentials
    - Usage data and analytics

    ### Automatically Collected Information
    - IP addresses and device information
    - Browser type and operating system
    - Pages visited and time spent
    - Cookies and similar technologies

    ### AI and Workflow Data
    - AI prompts and agent configurations
    - Workflow execution logs
    - AI provider API interactions
    - Context and memory data for AI agents

    ### DevOps and Repository Data
    - Repository metadata and commit information
    - CI/CD pipeline configurations
    - Webhook event data
    - Integration credentials (encrypted)

    ### Supply Chain Security Data
    - Software Bill of Materials (SBOM) content
    - Vulnerability scan results
    - Vendor information and risk assessments
    - Container image metadata and attestations

    ## How We Use Your Information

    We use your information to:
    - Provide and maintain our services
    - Process payments and billing
    - Send important account notifications
    - Improve our platform and user experience
    - Comply with legal obligations
    - Execute AI workflows and agent operations
    - Process supply chain security scans
    - Facilitate DevOps integrations

    ## AI Data Processing and Third-Party Providers

    ### AI Provider Data Sharing
    When you use AI features, certain data is processed by third-party AI providers:

    | Provider | Data Shared | Purpose |
    |----------|-------------|---------|
    | OpenAI | Prompts, context | GPT model inference |
    | Anthropic | Prompts, context | Claude model inference |
    | xAI | Prompts, context | Grok model inference |
    | Ollama (self-hosted) | Prompts, context | Local model inference |

    ### AI Data Retention
    - AI prompts and responses are logged for 90 days by default
    - You can configure retention periods in your account settings
    - AI providers may have their own retention policies
    - Deleted data is purged within 30 days

    ### AI Data Controls
    - You can disable AI logging in your account settings
    - You can request deletion of AI interaction history
    - Context data can be cleared per agent or globally

    ## Information Sharing

    We do not sell your personal information. We may share information with:
    - AI providers for model inference (with your consent)
    - Service providers and business partners
    - Legal authorities when required by law
    - In connection with business transfers or mergers

    ## Data Security

    We implement appropriate technical and organizational measures to protect your information against unauthorized access, alteration, disclosure, or destruction.

    ### Security Measures Include:
    - Encryption in transit and at rest
    - Regular security audits and updates
    - Access controls and authentication
    - PCI DSS compliance for payment data
    - API key encryption and secure storage
    - SBOM and vulnerability data isolation

    ## Your Rights

    Depending on your location, you may have the following rights:
    - Access your personal information
    - Correct inaccurate information
    - Delete your information (including AI data)
    - Data portability
    - Opt-out of marketing communications
    - Opt-out of AI data processing

    ## Cookies and Tracking

    We use cookies and similar technologies to enhance your experience. You can control cookie preferences through your browser settings.

    ## International Transfers

    Your information may be processed in countries other than your own. We ensure appropriate safeguards are in place for such transfers, including for AI processing.

    ## Children's Privacy

    Our services are not directed to children under 13. We do not knowingly collect personal information from children under 13.

    ## Changes to Privacy Policy

    We may update this Privacy Policy from time to time. We will notify you of any significant changes.

    ## Contact Us

    Questions about this Privacy Policy should be directed to: privacy@powernode.org

    For EU residents: You may also contact our Data Protection Officer at dpo@powernode.org
  MARKDOWN
end

# Help/Support page
Page.find_or_create_by!(slug: 'help') do |page|
  page.title = 'Help & Support'
  page.author = admin_user
  page.status = 'published'
  page.meta_description = 'Get help with Powernode - guides for billing, AI orchestration, DevOps, supply chain security, and more.'
  page.meta_keywords = 'help, support, FAQ, documentation, guides, customer support, AI, DevOps, supply chain'
  page.content = <<~MARKDOWN
    # Help & Support

    ## Get the Most Out of Powernode

    Welcome to our Help Center! Find answers to common questions and learn how to maximize your subscription business with Powernode.

    ## 🚀 Getting Started

    ### Quick Setup Guide
    1. **Create Your Account** - Sign up and verify your email
    2. **Set Up Billing** - Configure your payment gateway
    3. **Create Your First Plan** - Define your subscription offerings
    4. **Connect AI Providers** - Set up OpenAI, Claude, or local models
    5. **Invite Team Members** - Collaborate with your team
    6. **Launch Your Service** - Start accepting subscribers

    ### Platform Overview
    - **Dashboard** - Monitor key metrics at a glance
    - **Billing & Subscriptions** - Manage plans, payments, and invoices
    - **AI Orchestration** - Build agents and automated workflows
    - **DevOps** - Connect repositories and run CI/CD pipelines
    - **Supply Chain** - Manage SBOMs, vulnerabilities, and vendor risk
    - **Analytics** - Track MRR, churn, and customer insights

    ## 🤖 AI Orchestration

    ### Getting Started with AI
    **Q: Which AI providers are supported?**
    A: OpenAI (GPT-4), Anthropic (Claude), xAI (Grok), and local Ollama models.

    **Q: How do I create an AI agent?**
    A: Navigate to AI > Agents, click "New Agent", configure the model and system prompt, then test and deploy.

    **Q: What are AI workflows?**
    A: Visual automation sequences that chain AI agents with triggers, conditions, and actions.

    **Q: What is MCP (Model Context Protocol)?**
    A: A standard for connecting AI models to external tools and data sources for enhanced capabilities.

    ## 🔧 DevOps Integration

    ### Repository & Pipeline Setup
    **Q: How do I connect a Git repository?**
    A: Go to DevOps > Git Providers, click "Add Provider", authorize access, and select repositories to sync.

    **Q: Which Git providers are supported?**
    A: GitHub, GitLab, Gitea, and Bitbucket with OAuth or token authentication.

    **Q: How do CI/CD pipelines work?**
    A: Define pipeline stages and steps in YAML, trigger on commits or manually, and view execution logs in real-time.

    **Q: How do webhooks work?**
    A: Create webhook endpoints, subscribe to events (60+ types), and receive real-time HTTP notifications.

    ## 🛡️ Supply Chain Security

    ### SBOM and Vulnerability Management
    **Q: What is an SBOM?**
    A: A Software Bill of Materials - a complete inventory of components in your software.

    **Q: How do I import an SBOM?**
    A: Upload SPDX or CycloneDX files via the dashboard, API, or CI/CD integration.

    **Q: How are vulnerabilities detected?**
    A: Components are matched against NVD, OSV, and other vulnerability databases.

    **Q: How do vendor risk assessments work?**
    A: Add vendors, complete risk questionnaires, upload compliance documents, and track scores over time.

    ## 💰 Billing & Subscriptions

    ### Common Questions
    **Q: How do I change my subscription plan?**
    A: Visit your account settings and select "Change Plan" to upgrade or downgrade.

    **Q: When am I charged?**
    A: Billing occurs on your subscription anniversary date each month or year.

    **Q: Can I cancel anytime?**
    A: Yes, cancel from account settings. No long-term contracts required.

    **Q: What payment methods are accepted?**
    A: Credit cards via Stripe, PayPal, and bank transfers for Enterprise plans.

    ## 🔌 API & Integrations

    ### Developer Resources
    - **REST API** - Full CRUD access to all resources
    - **Webhooks** - Real-time event notifications
    - **Rate Limits** - Based on your subscription plan

    ## 📞 Contact Support

    Can't find what you're looking for? Our support team is here to help!

    ### Support Channels
    - **Email Support**: support@powernode.org
    - **Live Chat**: Available 24/7 for paid plans
    - **Phone Support**: Available for Business and Enterprise plans
    - **Help Desk**: Submit a ticket through your dashboard

    ### Response Times
    | Plan | Support Level |
    |------|---------------|
    | Starter | Email support |
    | Professional | Priority email |
    | Business | Priority email + chat |
    | Enterprise | Dedicated support |

    ## 📚 Knowledge Base Categories

    - [Getting Started](/kb/getting-started) - Setup guides and tutorials
    - [Billing & Subscriptions](/kb/billing-subscriptions) - Payment and plan management
    - [AI Orchestration](/kb/ai-orchestration) - Agents, workflows, and MCP
    - [DevOps](/kb/devops) - Git, pipelines, and webhooks
    - [Supply Chain Security](/kb/supply-chain-security) - SBOMs, CVEs, and vendors
    - [API & Integrations](/kb/api-integrations) - REST API and webhook guides
    - [Troubleshooting](/kb/troubleshooting) - Common issues and solutions

    ---

    **Still need help?** [Contact our support team](mailto:support@powernode.org) - we're here to ensure your success!
  MARKDOWN
end

# About page
Page.find_or_create_by!(slug: 'about') do |page|
  page.title = 'About Powernode'
  page.author = admin_user
  page.status = 'published'
  page.meta_description = 'Learn about Powernode - our mission to simplify subscription management with AI orchestration and supply chain security.'
  page.meta_keywords = 'about, company, mission, team, subscription management, SaaS, AI, supply chain security'
  page.content = <<~MARKDOWN
    # About Powernode

    ## The Modern Platform for Subscription Businesses

    Founded with the mission to democratize subscription business management, Powernode combines powerful billing automation with AI orchestration, DevOps integration, and supply chain security to help businesses of all sizes build, manage, and scale with confidence.

    ## Our Mission

    **To empower businesses to focus on what they do best while we handle the complexity of subscription management, AI operations, and software security.**

    We believe that every business should have access to enterprise-grade tools, regardless of their size or technical expertise.

    ## Our Story

    Powernode was born from the frustration of managing subscriptions across multiple platforms, dealing with complex billing scenarios, and lacking actionable insights into customer behavior.

    As software businesses evolved, so did their needs. We expanded our vision to address:
    - Subscription billing and lifecycle management
    - AI-powered automation and intelligent agents
    - DevOps integration for modern development workflows
    - Supply chain security for compliance and risk management

    ## What Sets Us Apart

    ### 🎯 Customer-Centric Design
    Every feature is built with the end-user in mind, ensuring intuitive experiences for both businesses and their customers.

    ### 🤖 AI-First Architecture
    Native AI orchestration with support for OpenAI, Anthropic Claude, Grok, and local Ollama models. Build intelligent agents and automated workflows without writing code.

    ### 🔧 Developer-Friendly
    Comprehensive APIs, webhooks, Git integration, and CI/CD pipelines make integration and automation straightforward for technical teams.

    ### 🛡️ Supply Chain Security
    Built-in SBOM management, vulnerability detection, and vendor risk assessment to help you ship secure software and maintain compliance.

    ### 📈 Growth-Oriented
    Our platform grows with your business, from first subscriber to IPO and beyond.

    ### 🔐 Security-First
    Enterprise-grade security and compliance built into every aspect of our platform.

    ## Our Values

    **Transparency** - Clear pricing, open communication, and honest business practices.

    **Innovation** - Continuously improving our platform based on customer feedback and industry trends.

    **Reliability** - Building robust, scalable infrastructure that businesses can depend on.

    **Security** - Protecting your data and helping you ship secure software.

    **Support** - Providing exceptional customer service and resources for success.

    ## Platform Capabilities

    | Area | Features |
    |------|----------|
    | **Billing** | Subscriptions, invoicing, payment gateways, dunning |
    | **Analytics** | MRR, ARR, churn, cohort analysis, forecasting |
    | **AI** | Agents, workflows, MCP servers, multi-provider support |
    | **DevOps** | Git providers, CI/CD pipelines, webhooks |
    | **Security** | SBOMs, vulnerability scanning, vendor risk, attestations |

    ## The Team

    Our diverse team combines expertise in subscription business models, financial technology, AI systems, security engineering, and user experience design. We're passionate about helping businesses succeed in the subscription economy.

    ## Join Our Journey

    Whether you're launching your first subscription product or optimizing an established business, we're here to support your success.

    [Start your free trial today](/register) and discover how Powernode can transform your business.

    ---

    **Questions about our company or platform?** [Contact us](/pages/contact) - we'd love to hear from you!
  MARKDOWN
end

# Contact page
Page.find_or_create_by!(slug: 'contact') do |page|
  page.title = 'Contact Us'
  page.author = admin_user
  page.status = 'published'
  page.meta_description = 'Get in touch with the Powernode team for sales, support, or general inquiries.'
  page.meta_keywords = 'contact, support, sales, inquiries, help, customer service'
  page.content = <<~MARKDOWN
    # Contact Us

    We're here to help! Choose the best way to reach our team based on your needs.

    ---

    ## 📧 Sales Inquiries

    Interested in Powernode for your business? Our sales team can help you find the right plan and answer any questions about enterprise features.

    **Email**: sales@powernode.org
    **Response Time**: Within 24 hours

    ---

    ## 🛠️ Technical Support

    Need help with your existing account or experiencing technical issues? Our support team is ready to assist.

    **Email**: support@powernode.org
    **Response Time**: Based on your plan tier (see [Help Center](/pages/help) for details)

    For faster resolution, please include:
    - Your account email
    - A clear description of the issue
    - Steps to reproduce (if applicable)
    - Screenshots or error messages

    ---

    ## 💬 General Questions

    Have general questions about Powernode, partnerships, or press inquiries?

    **Email**: hello@powernode.org

    ---

    ## 🔗 Quick Links

    - [Help Center & FAQ](/pages/help) - Find answers to common questions
    - [System Status](/status) - Check current platform status
    - [Knowledge Base](/kb) - Detailed guides and tutorials
    - [API Documentation](/kb/api-integrations) - Developer resources

    ---

    *We typically respond to all inquiries within 1-2 business days. For urgent issues, paid plan customers can access priority support through the dashboard.*
  MARKDOWN
end

# Features page
Page.find_or_create_by!(slug: 'features') do |page|
  page.title = 'Platform Features'
  page.author = admin_user
  page.status = 'published'
  page.meta_description = 'Explore Powernode features: subscription billing, AI orchestration, DevOps integration, and supply chain security.'
  page.meta_keywords = 'features, subscription billing, AI orchestration, DevOps, supply chain security, SaaS platform'
  page.content = <<~MARKDOWN
    # Platform Features

    Powernode is a comprehensive platform that combines subscription management, AI orchestration, DevOps integration, and supply chain security into one unified solution.

    ---

    ## 💰 Subscription & Billing

    **Flexible subscription management for any business model**

    | Feature | Description |
    |---------|-------------|
    | Multiple Billing Cycles | Monthly, yearly, or custom intervals |
    | Usage-Based Billing | Metered pricing with automatic invoicing |
    | Plan Management | Create and manage unlimited subscription plans |
    | Payment Gateways | Stripe, PayPal, and more |
    | Automated Invoicing | Professional invoices with custom branding |
    | Dunning Management | Automated retry logic for failed payments |
    | Proration | Automatic credits for plan changes |
    | Trial Periods | Configurable free trials per plan |

    **Analytics & Insights**
    - Real-time MRR, ARR, and churn tracking
    - Cohort analysis and customer lifetime value
    - Revenue forecasting and growth metrics
    - Custom dashboards and reports

    ---

    ## 🤖 AI Orchestration

    **Build intelligent automation with multi-provider AI support**

    ### AI Providers
    - **OpenAI** - GPT-4, GPT-4 Turbo, GPT-3.5
    - **Anthropic** - Claude 3.5 Sonnet, Claude 3 Opus, Claude 3 Haiku
    - **xAI** - Grok models
    - **Ollama** - Local/self-hosted models (Llama, Mistral, Mixtral)

    ### AI Agents
    Create intelligent agents with:
    - Custom system prompts and personas
    - Memory and context retention
    - Tool integration and function calling
    - Conversation history management

    ### Workflows
    Visual workflow automation with:
    - Drag-and-drop workflow builder
    - Event triggers and scheduled execution
    - Conditional branching and loops
    - Multi-step AI chains
    - Webhook integrations

    ### MCP Integration
    Model Context Protocol support for:
    - External tool connections
    - Database access for AI agents
    - File system operations
    - API integrations

    ---

    ## 🔧 DevOps Integration

    **Streamline your development workflow**

    ### Git Providers
    Connect your repositories from:
    - **GitHub** - OAuth and personal access tokens
    - **GitLab** - Cloud and self-hosted instances
    - **Gitea** - Self-hosted Git service
    - **Bitbucket** - Cloud and server

    ### CI/CD Pipelines
    - YAML-based pipeline definitions
    - Parallel and sequential stages
    - Environment variables and secrets
    - Build artifacts and caching
    - Deployment automation

    ### Webhooks
    - 60+ event types for real-time notifications
    - Custom headers and authentication
    - Retry policies and delivery logs
    - Event filtering and routing

    ### API Keys
    - Secure key generation and rotation
    - Scoped permissions per key
    - Usage tracking and rate limits
    - IP allowlisting

    ---

    ## 🛡️ Supply Chain Security

    **Secure your software supply chain**

    ### SBOM Management
    - **Import** - SPDX and CycloneDX formats
    - **Generate** - Automatic SBOM creation
    - **Analyze** - Component dependency graphs
    - **Export** - Compliance-ready reports

    ### Vulnerability Detection
    - Real-time scanning against NVD, OSV
    - CVE severity scoring and prioritization
    - Remediation guidance and fix tracking
    - Automated alerts and notifications

    ### Container Attestations
    - Verify image provenance
    - Build integrity validation
    - Sigstore and cosign support
    - SLSA compliance tracking

    ### Vendor Risk Assessment
    - Vendor questionnaires and scoring
    - Compliance document management
    - Risk level tracking (Critical, High, Medium, Low)
    - Audit trails and review history

    ### License Compliance
    - Open source license detection
    - Policy violation alerts
    - License compatibility analysis
    - Compliance reporting

    ---

    ## 🏢 Enterprise Ready

    **Built for scale and security**

    | Capability | Details |
    |------------|---------|
    | **SSO/SAML** | Enterprise single sign-on |
    | **Role-Based Access** | Granular permissions and roles |
    | **Audit Logs** | Complete activity tracking |
    | **White-Label** | Custom branding and domains |
    | **SLA Guarantees** | 99.9% uptime commitment |
    | **Dedicated Support** | Priority access to engineering |
    | **Data Export** | Full data portability |
    | **API Access** | Complete REST API |

    ---

    ## 🚀 Get Started

    Ready to transform your business with Powernode?

    - [View Pricing Plans](/plans) - Find the right plan for your needs
    - [Create an Account](/register) - Start your free trial today
    - [Contact Sales](/pages/contact) - Talk to our team about enterprise features

    ---

    *Have questions about a specific feature? Visit our [Help Center](/pages/help) or [Knowledge Base](/kb) for detailed documentation.*
  MARKDOWN
end

puts "✅ Created #{Page.count} public pages"

# Load Knowledge Base data
puts "\n📚 Loading Knowledge Base content..."
load Rails.root.join('db', 'seeds', 'knowledge_base_permissions.rb')
load Rails.root.join('db', 'seeds', 'knowledge_base_articles.rb')

# Marketing permissions loaded via extension seeds (extensions/marketing/)

# Load AI Providers and Workflows (only in development/test)
if Rails.env.development? || Rails.env.test?
  puts "\n🤖 Loading Comprehensive AI Providers (OpenAI, Grok, Ollama, Claude)..."
  load Rails.root.join('db', 'seeds', 'comprehensive_ai_providers_seed.rb')

  puts "\n🧠 Loading Claude-Powered Workflow Agents..."
  load Rails.root.join('db', 'seeds', 'claude_agents_seed.rb')

  puts "\n📊 Loading Monitoring and Analytics Agents..."
  load Rails.root.join('db', 'seeds', 'monitoring_analytics_agents_seed.rb')

  puts "\n🔌 Loading MCP Servers..."
  load Rails.root.join('db', 'seeds', 'mcp_servers_seeds.rb')

  puts "\n🚀 Loading AI Workflow Showcase Examples..."
  load Rails.root.join('db', 'seeds', 'ai_workflow_showcase_seeds.rb')

  puts "\n🗄️  Loading File Storage configurations..."
  load Rails.root.join('db', 'seeds', 'file_storage_seeds.rb')

  puts "\n📦 Loading DevOps Container Templates..."
  load Rails.root.join('db', 'seeds', 'devops_container_templates.rb')

  puts "\n🔌 Loading MCP Server Container Templates..."
  load Rails.root.join('db', 'seeds', 'mcp_container_templates_seed.rb')

  puts "\n🔧 Loading AI DevOps Templates..."
  load Rails.root.join('db', 'seeds', 'ai_devops_templates_seed.rb')

  puts "\n🔧 Loading AI DevOps Configs (Template Installations + AI Configs)..."
  load Rails.root.join('db', 'seeds', 'ai_devops_configs_seed.rb')

  puts "\n👥 Loading AI Agent Teams..."
  load Rails.root.join('db', 'seeds', 'ai_teams_seed.rb')

  puts "\n📋 Loading AI Todo App Team..."
  load Rails.root.join('db', 'seeds', 'ai_todo_team_seed.rb')

  puts "\n🧩 Loading AI Skills..."
  load Rails.root.join('db', 'seeds', 'ai_skills_seed.rb')

  puts "\n📋 Loading AI Example Templates..."
  load Rails.root.join('db', 'seeds', 'ai_example_templates_seed.rb')

  puts "\n🔧 Loading AI Utility Agents & Specialist Skills..."
  load Rails.root.join('db', 'seeds', 'ai_utility_agents_seed.rb')

  puts "\n🔧 Loading Powernode Development Team..."
  load Rails.root.join('db', 'seeds', 'ai_dev_team_seed.rb')

  puts "\n🎯 Loading AI Mission Templates..."
  load Rails.root.join('db', 'seeds', 'ai_mission_templates.rb')

  puts "\n🤖 Loading AI Concierge Agent..."
  load Rails.root.join('db', 'seeds', 'ai_concierge_seed.rb')

  puts "\n📝 Loading AI System Prompt Templates..."
  load Rails.root.join('db', 'seeds', 'ai_system_prompt_templates_seed.rb')

  puts "\n📚 Loading RAG Knowledge Base seed..."
  load Rails.root.join('db', 'seeds', 'ai_knowledge_base_seed.rb')

  puts "\n🤖 Loading Autonomy Data (consolidation + seeding)..."
  load Rails.root.join('db', 'seeds', 'autonomy_data_seed.rb')

  puts "\n🧠 Loading AI Memory Pools..."
  load Rails.root.join('db', 'seeds', 'ai_memory_pools_seed.rb')

  # Seed AI model pricing from hardcoded constant
  if defined?(Ai::ProviderManagementService::MODEL_PRICING) && Ai::ModelPricing.count == 0
    puts "\n💰 Seeding AI model pricing..."
    Ai::ProviderManagementService::MODEL_PRICING.each do |model_id, pricing|
      provider_type = case model_id
                      when /^gpt-|^o[34]/ then "openai"
                      when /^claude/ then "anthropic"
                      when /^gemini/ then "google"
                      when /^grok/ then "xai"
                      when /^llama|^mixtral/ then "groq"
                      when /^mistral|^codestral/ then "mistral"
                      when /^command/ then "cohere"
                      else "unknown"
                      end

      Ai::ModelPricing.find_or_create_by!(model_id: model_id, provider_type: provider_type) do |mp|
        mp.input_per_1k = pricing["input"]
        mp.output_per_1k = pricing["output"]
        mp.cached_input_per_1k = pricing["cached_input"] || 0
        mp.tier = pricing["tier"]
        mp.source = "constant_fallback"
        mp.last_synced_at = Time.current
        mp.metadata = {}
      end
    end
    puts "✅ Seeded #{Ai::ModelPricing.count} model pricings"
  end
end

# Extension seeds (dynamically discovered from registered extensions)
Powernode::ExtensionRegistry.each do |slug, ext|
  seeds_dir = ext[:engine].root.join("db", "seeds")
  next unless Dir.exist?(seeds_dir)

  puts "\n📦 Loading #{slug} extension seeds..."
  Dir[seeds_dir.join("*.rb")].sort.each { |f| load f }
  puts "✅ #{slug.capitalize} extension seeds loaded"
end

puts "\n🎉 Seeding complete!"
puts "   Permissions: #{Permission.count}"
puts "   Roles: #{Role.count}"
plan_class = defined?(Billing::Plan) ? Billing::Plan : (defined?(Plan) ? Plan : nil)
puts "   Plans: #{plan_class&.count || 0}"
puts "   Workers: #{Worker.count}"
puts "   Public Pages: #{Page.count}"
puts "   KB Categories: #{KnowledgeBase::Category.count}"
puts "   KB Articles: #{KnowledgeBase::Article.count}"

if Rails.env.development? || Rails.env.test?
  puts "   AI Providers: #{Ai::Provider.count}"
  puts "   AI Agents: #{Ai::Agent.count}"
  puts "   AI Workflows: #{Ai::Workflow.count}"
  puts "   AI Workflow Templates: #{Ai::WorkflowTemplate.count}"
  puts "   AI Workflow Runs: #{Ai::WorkflowRun.count}"
  puts "   DevOps Container Templates: #{Devops::ContainerTemplate.count}"
  puts "   AI DevOps Templates: #{Ai::DevopsTemplate.count}"
  puts "   AI Skills: #{Ai::Skill.count}"
  puts "   AI Agent Templates: #{Ai::AgentTemplate.count}"
  puts "   AI Agent Teams: #{Ai::AgentTeam.count}"
  puts "   AI Memory Pools: #{Ai::MemoryPool.count}"
end

# 🔧 Create default site settings
puts "\n🔧 Creating default site settings..."

# Site information
SiteSetting.set('site_name', 'Powernode', description: 'Name of the site', setting_type: 'string', is_public: true)
SiteSetting.set('footer_description', 'Powerful subscription management platform designed to help businesses grow. Trusted by thousands of companies worldwide.', description: 'Footer description text', setting_type: 'text', is_public: true)

# Copyright information
SiteSetting.set('copyright_text', 'Everett C. Haimes III. All rights reserved.', description: 'Copyright text displayed in footer', setting_type: 'string', is_public: true)
SiteSetting.set('copyright_year', Date.current.year.to_s, description: 'Copyright year', setting_type: 'string', is_public: true)

# Contact information
SiteSetting.set('contact_email', 'hello@powernode.org', description: 'Main contact email', setting_type: 'string', is_public: true)
SiteSetting.set('contact_phone', '+1 (555) 123-4567', description: 'Contact phone number', setting_type: 'string', is_public: true)
SiteSetting.set('company_address', '123 Innovation Drive, Tech City, TC 12345', description: 'Company address', setting_type: 'string', is_public: true)

# Social media links
SiteSetting.set('social_twitter', '', description: 'Twitter/X profile URL', setting_type: 'string', is_public: true)
SiteSetting.set('social_linkedin', '', description: 'LinkedIn profile URL', setting_type: 'string', is_public: true)
SiteSetting.set('social_facebook', '', description: 'Facebook page URL', setting_type: 'string', is_public: true)
SiteSetting.set('social_instagram', '', description: 'Instagram profile URL', setting_type: 'string', is_public: true)
SiteSetting.set('social_youtube', '', description: 'YouTube channel URL', setting_type: 'string', is_public: true)

# Admin-only settings
SiteSetting.set('maintenance_mode', 'false', description: 'Enable maintenance mode', setting_type: 'boolean', is_public: false)
SiteSetting.set('analytics_tracking_id', '', description: 'Google Analytics tracking ID', setting_type: 'string', is_public: false)
SiteSetting.set('seo_default_title', 'Powernode - Subscription Management Platform', description: 'Default SEO title', setting_type: 'string', is_public: false)
SiteSetting.set('seo_default_description', 'Streamline your subscription business with automated billing, analytics, and customer lifecycle management.', description: 'Default SEO description', setting_type: 'text', is_public: false)

# Footer caching
SiteSetting.set('footer_cache_enabled', 'true', description: 'Enable caching for footer data to improve performance', setting_type: 'boolean', is_public: false)

puts "✅ Created #{SiteSetting.count} site settings"


if Rails.env.development? || Rails.env.test?
  puts "   Accounts: #{Account.count}"
  puts "   Users: #{User.count}"
  if defined?(Billing::Subscription)
    puts "   Subscriptions: #{Billing::Subscription.count}"
  elsif defined?(Subscription)
    puts "   Subscriptions: #{Subscription.count}"
  end
  puts "   Site Settings: #{SiteSetting.count}"
end
