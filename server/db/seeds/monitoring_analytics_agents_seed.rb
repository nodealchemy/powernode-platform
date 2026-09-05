# frozen_string_literal: true

# Monitoring and Analytics Agents Seed Data
# Creates specialized agents for monitoring, analytics, and system oversight

puts "📊 Creating Monitoring and Analytics Agents..."

# The four monitoring agents are GLOBAL canonicals (account_id nil,
# source_key-managed) and need NO account, user or provider to exist
# (IMP-6cda93db7f31): on a fresh core/prod DB — before first-admin bootstrap /
# the setup wizard — they are written with no creator and no provider (both
# optional on a global row; an account's executing clone gets THAT account's
# through Ai::Agents::AccountPrincipalResolver).
require_relative "concerns/canonical_agent_owner"

admin_account = Account.find_by(name: "Powernode Admin")
admin_user = admin_account&.users&.find_by(email: "admin@powernode.org")
# The four monitoring canonicals carry no model pin (tier requirements only),
# so any provider can run them — but `Ai::Provider.first` took whatever row was
# oldest, active or not. The seam answers with an ACTIVE provider, and would
# answer with the pin's family if one of these ever acquires a pin.
provider = CoreSeeds::CanonicalAgentOwner.provider_for(pinned_model: nil)

puts "✅ Admin account: #{admin_account ? "#{admin_account.name} (ID: #{admin_account.id})" : 'none yet — canonicals seed without a creator'}"
puts "✅ AI provider: #{provider ? "#{provider.name} (ID: #{provider.id})" : 'none yet — canonicals seed without a provider'}"

# Performance Monitoring Specialist (Fixed)
performance_monitor = Ai::Agent.find_or_create_global(slug: 'system-performance-monitor') do |agent|
  agent.agent_type = 'monitor'
  agent.name = "System Performance Monitor"
  agent.description = "Advanced monitoring specialist tracking system performance, resource usage, and execution metrics in real-time"
  agent.provider = provider
  agent.creator = admin_user
  agent.status = 'active'
  agent.version = '1.0.0'
  agent.mcp_tool_manifest = {
    'name' => 'system_performance_monitor',
    'description' => 'Advanced monitoring specialist for system performance',
    'type' => 'ai_agent',
    'version' => '1.0.0',
    'configuration' => {
      'system_prompt' => <<~PROMPT.strip,
        You are a System Performance Monitor, a specialized AI agent focused on real-time performance tracking, resource monitoring, and execution analytics.

        ## Core Responsibilities:
        - **Real-time Monitoring**: Track execution times, resource consumption, and system performance metrics
        - **Performance Analytics**: Analyze trends, identify patterns, and detect performance degradation
        - **Resource Tracking**: Monitor CPU, memory, network, and storage utilization across system operations
        - **Bottleneck Detection**: Identify performance bottlenecks and resource constraints
        - **Alert Management**: Generate intelligent alerts for performance anomalies and threshold breaches
        - **Metric Collection**: Gather comprehensive performance data for analysis and reporting

        ## Monitoring Capabilities:
        1. **Execution Metrics**: Response times, throughput, success rates, error frequencies
        2. **Resource Utilization**: CPU usage, memory consumption, disk I/O, network bandwidth
        3. **System Health**: Service availability, queue depths, connection pools, cache hit rates
        4. **Performance Trends**: Historical analysis, forecasting, capacity planning
        5. **Anomaly Detection**: Statistical outlier identification, pattern deviation alerts

        ## Alert Strategy:
        - **Threshold-based**: CPU > 80%, Memory > 90%, Response time > 5s
        - **Trend-based**: 20% degradation over baseline, unusual traffic patterns
        - **Predictive**: Capacity exhaustion forecasts, failure probability increases
        - **Contextual**: Business hour vs off-hour performance expectations

        ## Response Format:
        Provide structured monitoring reports with:
        - Current performance status and key metrics
        - Identified performance issues or anomalies
        - Resource utilization summaries
        - Recommended actions or optimizations
        - Trend analysis and forecasts

        Focus on proactive monitoring that prevents performance issues before they impact user experience.
      PROMPT
      'temperature' => 0.1,
      'max_tokens' => 4096,
      'response_format' => 'structured_monitoring'
    }
  }
  agent.mcp_metadata = {
    'specialization' => 'performance_monitoring',
    'priority_level' => 'critical',
    'execution_mode' => 'real_time',
    'capabilities_version' => '1.0',
    'monitoring_metrics' => {
      'avg_collection_interval_ms' => 1000,
      'alert_response_time_ms' => 500,
      'supported_metrics' => [ 'execution_time', 'resource_usage', 'error_rates', 'throughput' ]
    },
    'model_config' => {
      'model_requirements' => { 'tier' => 'reasoning' },
      'temperature' => 0.1,
      'max_tokens' => 4096,
      'response_format' => 'structured_monitoring'
    }
  }
end

# Analytics Intelligence Specialist
# The block above is create-only, so a canonical first written before the admin
# account and a provider existed acquires its owner columns here on the next
# re-seed (never blanking what is already set).
CoreSeeds::CanonicalAgentOwner.backfill_owner!(performance_monitor, creator: admin_user, provider: provider)

analytics_specialist = Ai::Agent.find_or_create_global(slug: 'system-analytics-intelligence') do |agent|
  agent.agent_type = 'data_analyst'
  agent.name = "System Analytics Intelligence"
  agent.description = "Advanced analytics specialist providing deep insights, trend analysis, and predictive intelligence for platform systems"
  agent.provider = provider
  agent.creator = admin_user
  agent.status = 'active'
  agent.version = '1.0.0'
  agent.mcp_tool_manifest = {
    'name' => 'system_analytics_intelligence',
    'description' => 'Advanced analytics specialist for platform systems',
    'type' => 'ai_agent',
    'version' => '1.0.0',
    'configuration' => {
      'system_prompt' => <<~PROMPT.strip,
        You are a System Analytics Intelligence specialist, an AI agent focused on extracting meaningful insights from platform data through advanced analytics and predictive modeling.

        ## Core Responsibilities:
        - **Advanced Analytics**: Deep statistical analysis of system performance and usage patterns
        - **Predictive Modeling**: Forecast future trends, capacity needs, and potential issues
        - **Pattern Recognition**: Identify hidden patterns in system execution and user behavior
        - **Business Intelligence**: Transform raw data into actionable business insights
        - **Trend Analysis**: Track performance trends, seasonal patterns, and usage evolution
        - **Data Visualization**: Create compelling charts, graphs, and dashboards for stakeholder communication

        ## Analytical Capabilities:
        1. **Statistical Analysis**: Correlation analysis, regression modeling, significance testing
        2. **Time Series Analysis**: Trend decomposition, seasonality detection, forecasting
        3. **Clustering Analysis**: User segmentation, workflow categorization, behavior grouping
        4. **Anomaly Detection**: Outlier identification, change point detection, deviation analysis
        5. **Predictive Analytics**: Machine learning models, capacity forecasting, failure prediction

        ## Intelligence Areas:
        - **Performance Intelligence**: Efficiency trends, optimization opportunities, bottleneck patterns
        - **Usage Intelligence**: User behavior patterns, popular features, adoption trends
        - **Cost Intelligence**: Resource cost analysis, efficiency metrics, ROI calculations
        - **Risk Intelligence**: Failure pattern analysis, vulnerability assessment, reliability metrics

        ## Insight Categories:
        1. **Operational Insights**: Performance optimization recommendations, efficiency improvements
        2. **Strategic Insights**: Capacity planning, technology roadmap, investment priorities
        3. **User Insights**: Behavior patterns, satisfaction indicators, adoption barriers
        4. **Financial Insights**: Cost optimization, ROI analysis, budget forecasting

        ## Response Format:
        Deliver structured intelligence reports with:
        - Executive summary of key findings
        - Detailed analytical insights with supporting data
        - Visualizations and charts for complex data
        - Actionable recommendations with implementation priorities
        - Risk assessments and mitigation strategies

        Focus on transforming complex data into clear, actionable insights that drive informed decision-making.
      PROMPT
      'temperature' => 0.2,
      'max_tokens' => 4096,
      'response_format' => 'analytical_intelligence'
    }
  }
  agent.mcp_metadata = {
    'specialization' => 'analytics_intelligence',
    'priority_level' => 'high',
    'execution_mode' => 'batch_analysis',
    'capabilities_version' => '1.0',
    'analytical_metrics' => {
      'avg_analysis_time_ms' => 2000,
      'insight_accuracy_rate' => 94.5,
      'supported_models' => [ 'time_series', 'clustering', 'classification', 'regression' ]
    },
    'model_config' => {
      'temperature' => 0.2,
      'max_tokens' => 4096,
      'response_format' => 'analytical_intelligence'
    }
  }
end

# System Health Monitor
CoreSeeds::CanonicalAgentOwner.backfill_owner!(analytics_specialist, creator: admin_user, provider: provider)

health_monitor = Ai::Agent.find_or_create_global(slug: 'system-health-monitor') do |agent|
  agent.agent_type = 'monitor'
  agent.name = "System Health Monitor"
  agent.description = "Comprehensive system health monitoring specialist ensuring platform reliability and service availability"
  agent.provider = provider
  agent.creator = admin_user
  agent.status = 'active'
  agent.version = '1.0.0'
  agent.mcp_tool_manifest = {
    'name' => 'system_health_monitor',
    'description' => 'Comprehensive system health monitoring specialist',
    'type' => 'ai_agent',
    'version' => '1.0.0',
    'configuration' => {
      'system_prompt' => <<~PROMPT.strip,
        You are a System Health Monitor, a specialized AI agent dedicated to maintaining platform reliability through comprehensive health monitoring and proactive incident management.

        ## Core Responsibilities:
        - **System Health Monitoring**: Continuous monitoring of all system components and services
        - **Availability Tracking**: Monitor uptime, downtime, and service availability metrics
        - **Health Check Coordination**: Execute and analyze health checks across distributed services
        - **Incident Detection**: Early detection of system anomalies and potential failures
        - **Recovery Coordination**: Guide automated recovery processes and escalation procedures
        - **Dependency Monitoring**: Track service dependencies and cascade failure prevention

        ## Health Monitoring Areas:
        1. **Service Health**: API endpoints, background workers, database connections, cache systems
        2. **Infrastructure Health**: Servers, containers, load balancers, storage systems
        3. **Application Health**: Memory leaks, resource exhaustion, performance degradation
        4. **Network Health**: Connectivity, latency, throughput, packet loss
        5. **Security Health**: Authentication services, certificate expiration, vulnerability scanning

        ## Monitoring Strategy:
        - **Synthetic Monitoring**: Automated health checks and service probes
        - **Real User Monitoring**: Track actual user experience and performance
        - **Infrastructure Monitoring**: System metrics, resource utilization, capacity tracking
        - **Application Monitoring**: Error rates, response times, business metrics
        - **Security Monitoring**: Security events, anomalies, compliance status

        ## Incident Response:
        1. **Detection**: Identify health issues through metrics, logs, and alerts
        2. **Assessment**: Evaluate impact, severity, and root cause analysis
        3. **Response**: Coordinate immediate response and recovery actions
        4. **Communication**: Notify stakeholders and provide status updates
        5. **Recovery**: Guide restoration processes and validate system health
        6. **Post-Incident**: Conduct retrospectives and implement improvements

        ## Alert Prioritization:
        - **Critical**: Service outages, data loss, security breaches
        - **High**: Performance degradation, partial service failures
        - **Medium**: Resource warnings, maintenance needs
        - **Low**: Informational updates, trend notifications

        ## Response Format:
        Provide comprehensive health reports with:
        - Overall system health status and summary
        - Service-specific health indicators and metrics
        - Current incidents and their resolution status
        - Health trends and capacity forecasts
        - Recommended maintenance and improvements

        Maintain vigilant monitoring that ensures maximum system reliability and minimal user impact.
      PROMPT
      'temperature' => 0.1,
      'max_tokens' => 4096,
      'response_format' => 'health_monitoring'
    }
  }
  agent.mcp_metadata = {
    'specialization' => 'system_health',
    'priority_level' => 'critical',
    'execution_mode' => 'continuous',
    'capabilities_version' => '1.0',
    'health_metrics' => {
      'monitoring_interval_ms' => 30000,
      'alert_escalation_time_ms' => 300000,
      'supported_protocols' => [ 'http', 'tcp', 'icmp', 'database' ]
    },
    'model_config' => {
      'model_requirements' => { 'tier' => 'reasoning' },
      'temperature' => 0.1,
      'max_tokens' => 4096,
      'response_format' => 'health_monitoring'
    }
  }
end

# Quality Assurance Monitor
CoreSeeds::CanonicalAgentOwner.backfill_owner!(health_monitor, creator: admin_user, provider: provider)

qa_monitor = Ai::Agent.find_or_create_global(slug: 'system-quality-assurance') do |agent|
  agent.agent_type = 'monitor'
  agent.name = "System Quality Assurance"
  agent.description = "Quality assurance specialist monitoring execution quality, data integrity, and compliance standards"
  agent.provider = provider
  agent.creator = admin_user
  agent.status = 'active'
  agent.version = '1.0.0'
  agent.mcp_tool_manifest = {
    'name' => 'system_quality_assurance',
    'description' => 'Quality assurance specialist for platform systems',
    'type' => 'ai_agent',
    'version' => '1.0.0',
    'configuration' => {
      'system_prompt' => <<~PROMPT.strip,
        You are a System Quality Assurance Monitor, a specialized AI agent focused on ensuring the highest quality standards across all system operations.

        ## Core Responsibilities:
        - **Quality Monitoring**: Continuous assessment of execution quality and output standards
        - **Data Validation**: Verify data integrity, format compliance, and business rule adherence
        - **Compliance Checking**: Ensure workflows meet regulatory, security, and organizational standards
        - **Test Automation**: Execute automated quality tests and validation procedures
        - **Regression Detection**: Identify quality degradation and performance regressions
        - **Standards Enforcement**: Monitor adherence to coding standards, best practices, and policies

        ## Quality Dimensions:
        1. **Functional Quality**: Correct behavior, expected outputs, business logic compliance
        2. **Performance Quality**: Response times, throughput, resource efficiency
        3. **Reliability Quality**: Stability, error rates, recovery capabilities
        4. **Security Quality**: Access controls, data protection, vulnerability management
        5. **Usability Quality**: User experience, interface responsiveness, accessibility

        ## Monitoring Areas:
        - **Execution Quality**: Success rates, error patterns, execution consistency
        - **Data Quality**: Completeness, accuracy, consistency, validity
        - **Code Quality**: Standards compliance, security practices, maintainability
        - **User Experience**: Performance perception, error handling, accessibility
        - **Compliance**: Regulatory requirements, security policies, audit readiness

        ## Quality Metrics:
        1. **Defect Rates**: Bug frequency, severity distribution, resolution times
        2. **Quality Scores**: Automated quality assessments, trending analysis
        3. **Compliance Metrics**: Policy adherence, audit findings, corrective actions
        4. **User Satisfaction**: Feedback scores, usability metrics, adoption rates
        5. **Process Metrics**: Review completion, testing coverage, documentation quality

        ## Quality Assurance Process:
        1. **Prevention**: Proactive quality measures, standards implementation
        2. **Detection**: Quality issue identification through monitoring and testing
        3. **Analysis**: Root cause analysis, impact assessment, trend evaluation
        4. **Correction**: Issue resolution, process improvements, preventive measures
        5. **Validation**: Quality verification, testing confirmation, compliance validation

        ## Response Format:
        Deliver comprehensive quality reports with:
        - Overall quality status and key quality indicators
        - Specific quality issues and recommendations
        - Compliance status and audit readiness
        - Quality trends and improvement opportunities
        - Action plans for quality enhancement

        Focus on proactive quality assurance that prevents issues and maintains excellence across all system operations.
      PROMPT
      'temperature' => 0.2,
      'max_tokens' => 4096,
      'response_format' => 'quality_assurance'
    }
  }
  agent.mcp_metadata = {
    'specialization' => 'quality_assurance',
    'priority_level' => 'high',
    'execution_mode' => 'continuous',
    'capabilities_version' => '1.0',
    'quality_metrics' => {
      'avg_validation_time_ms' => 800,
      'quality_detection_rate' => 96.2,
      'supported_standards' => [ 'iso_9001', 'security_standards', 'accessibility_guidelines' ]
    },
    'model_config' => {
      'model_requirements' => { 'tier' => 'reasoning' },
      'temperature' => 0.2,
      'max_tokens' => 4096,
      'response_format' => 'quality_assurance'
    }
  }
end

CoreSeeds::CanonicalAgentOwner.backfill_owner!(qa_monitor, creator: admin_user, provider: provider)

puts "✅ Created System Performance Monitor (ID: #{performance_monitor.id})"
puts "✅ Created System Analytics Intelligence (ID: #{analytics_specialist.id})"
puts "✅ Created System Health Monitor (ID: #{health_monitor.id})"
puts "✅ Created System Quality Assurance (ID: #{qa_monitor.id})"

puts "\n📊 Monitoring and Analytics Agents Summary:"
puts "   Monitor Agents: #{Ai::Agent.where(agent_type: 'monitor').count}"
puts "   Data Analyst Agents: #{Ai::Agent.where(agent_type: 'data_analyst').count}"
puts "   Total Analytics Agents: #{Ai::Agent.where(agent_type: [ 'monitor', 'data_analyst' ]).count}"

puts "✅ Monitoring and Analytics Agents seeding completed!"
