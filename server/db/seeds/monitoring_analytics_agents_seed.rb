# frozen_string_literal: true

# Monitoring and Analytics Agents Seed Data
# Creates specialized agents for monitoring, analytics, and system oversight

puts "📊 Creating Monitoring and Analytics Workflow Agents..."

admin_account = Account.find_by(name: "Powernode Admin")
admin_user = admin_account.users.find_by(email: "admin@powernode.org")
provider = AiProvider.first

if admin_account && admin_user && provider
  puts "✅ Using admin account: #{admin_account.name} (ID: #{admin_account.id})"
  puts "✅ Using admin user: #{admin_user.name} (ID: #{admin_user.id})"
  puts "✅ Using AI provider: #{provider.name} (ID: #{provider.id})"

  # Performance Monitoring Specialist (Fixed)
  performance_monitor = AiAgent.find_or_create_by(
    account: admin_account,
    slug: 'workflow-performance-monitor',
    agent_type: 'monitor'
  ) do |agent|
    agent.name = "Workflow Performance Monitor"
    agent.description = "Advanced monitoring specialist tracking workflow performance, resource usage, and execution metrics in real-time"
    agent.ai_provider = provider
    agent.creator = admin_user
    agent.status = 'active'
    agent.version = '1.0.0'
    agent.mcp_capabilities = [
      'performance_monitoring',
      'resource_tracking',
      'execution_analytics',
      'bottleneck_detection',
      'real_time_alerting',
      'metric_collection',
      'threshold_management',
      'performance_reporting'
    ]
    agent.mcp_tool_manifest = {
      'name' => 'workflow_performance_monitor',
      'description' => 'Advanced monitoring specialist for workflow performance',
      'type' => 'ai_agent',
      'version' => '1.0.0',
      'configuration' => {
        'system_prompt' => <<~PROMPT.strip,
          You are a Workflow Performance Monitor, a specialized AI agent focused on real-time performance tracking, resource monitoring, and execution analytics for workflow systems.

          ## Core Responsibilities:
          - **Real-time Monitoring**: Track workflow execution times, resource consumption, and system performance metrics
          - **Performance Analytics**: Analyze trends, identify patterns, and detect performance degradation
          - **Resource Tracking**: Monitor CPU, memory, network, and storage utilization across workflow executions
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
        'model' => 'claude-sonnet-4-5-20250514',
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
        'supported_metrics' => ['execution_time', 'resource_usage', 'error_rates', 'throughput']
      },
      'model_config' => {
        'model' => 'claude-sonnet-4-5-20250514',
        'temperature' => 0.1,
        'max_tokens' => 4096,
        'response_format' => 'structured_monitoring'
      }
    }
  end

  # Analytics Intelligence Specialist
  analytics_specialist = AiAgent.find_or_create_by(
    account: admin_account,
    slug: 'workflow-analytics-intelligence',
    agent_type: 'data_analyst'
  ) do |agent|
    agent.name = "Workflow Analytics Intelligence"
    agent.description = "Advanced analytics specialist providing deep insights, trend analysis, and predictive intelligence for workflow systems"
    agent.ai_provider = provider
    agent.creator = admin_user
    agent.status = 'active'
    agent.version = '1.0.0'
    agent.mcp_capabilities = [
      'advanced_analytics',
      'predictive_modeling',
      'trend_analysis',
      'pattern_recognition',
      'data_visualization',
      'statistical_analysis',
      'business_intelligence',
      'forecast_generation'
    ]
    agent.mcp_tool_manifest = {
      'name' => 'workflow_analytics_intelligence',
      'description' => 'Advanced analytics specialist for workflow systems',
      'type' => 'ai_agent',
      'version' => '1.0.0',
      'configuration' => {
        'system_prompt' => <<~PROMPT.strip,
          You are a Workflow Analytics Intelligence specialist, an AI agent focused on extracting meaningful insights from workflow data through advanced analytics and predictive modeling.

          ## Core Responsibilities:
          - **Advanced Analytics**: Deep statistical analysis of workflow performance and usage patterns
          - **Predictive Modeling**: Forecast future trends, capacity needs, and potential issues
          - **Pattern Recognition**: Identify hidden patterns in workflow execution and user behavior
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
          - **Usage Intelligence**: User behavior patterns, popular workflows, adoption trends
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
        'model' => 'claude-sonnet-4-5-20250514',
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
        'supported_models' => ['time_series', 'clustering', 'classification', 'regression']
      },
      'model_config' => {
        'model' => 'claude-sonnet-4-5-20250514',
        'temperature' => 0.2,
        'max_tokens' => 4096,
        'response_format' => 'analytical_intelligence'
      }
    }
  end

  # System Health Monitor
  health_monitor = AiAgent.find_or_create_by(
    account: admin_account,
    slug: 'system-health-monitor',
    agent_type: 'monitor'
  ) do |agent|
    agent.name = "System Health Monitor"
    agent.description = "Comprehensive system health monitoring specialist ensuring platform reliability and service availability"
    agent.ai_provider = provider
    agent.creator = admin_user
    agent.status = 'active'
    agent.version = '1.0.0'
    agent.mcp_capabilities = [
      'system_monitoring',
      'health_checks',
      'service_discovery',
      'availability_tracking',
      'incident_detection',
      'recovery_coordination',
      'uptime_monitoring',
      'dependency_tracking'
    ]
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
        'model' => 'claude-sonnet-4-5-20250514',
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
        'supported_protocols' => ['http', 'tcp', 'icmp', 'database']
      },
      'model_config' => {
        'model' => 'claude-sonnet-4-5-20250514',
        'temperature' => 0.1,
        'max_tokens' => 4096,
        'response_format' => 'health_monitoring'
      }
    }
  end

  # Quality Assurance Monitor
  qa_monitor = AiAgent.find_or_create_by(
    account: admin_account,
    slug: 'workflow-quality-assurance',
    agent_type: 'monitor'
  ) do |agent|
    agent.name = "Workflow Quality Assurance"
    agent.description = "Quality assurance specialist monitoring workflow execution quality, data integrity, and compliance standards"
    agent.ai_provider = provider
    agent.creator = admin_user
    agent.status = 'active'
    agent.version = '1.0.0'
    agent.mcp_capabilities = [
      'quality_monitoring',
      'data_validation',
      'compliance_checking',
      'test_automation',
      'regression_detection',
      'quality_scoring',
      'audit_trail_monitoring',
      'standards_enforcement'
    ]
    agent.mcp_tool_manifest = {
      'name' => 'workflow_quality_assurance',
      'description' => 'Quality assurance specialist for workflow systems',
      'type' => 'ai_agent',
      'version' => '1.0.0',
      'configuration' => {
        'system_prompt' => <<~PROMPT.strip,
          You are a Workflow Quality Assurance Monitor, a specialized AI agent focused on ensuring the highest quality standards across all workflow executions and system operations.

          ## Core Responsibilities:
          - **Quality Monitoring**: Continuous assessment of workflow execution quality and output standards
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
          - **Workflow Execution**: Success rates, error patterns, execution consistency
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
        'model' => 'claude-sonnet-4-5-20250514',
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
        'supported_standards' => ['iso_9001', 'security_standards', 'accessibility_guidelines']
      },
      'model_config' => {
        'model' => 'claude-sonnet-4-5-20250514',
        'temperature' => 0.2,
        'max_tokens' => 4096,
        'response_format' => 'quality_assurance'
      }
    }
  end

  puts "✅ Created Workflow Performance Monitor (ID: #{performance_monitor.id})"
  puts "✅ Created Workflow Analytics Intelligence (ID: #{analytics_specialist.id})"
  puts "✅ Created System Health Monitor (ID: #{health_monitor.id})"
  puts "✅ Created Workflow Quality Assurance (ID: #{qa_monitor.id})"

  puts "\n📊 Monitoring and Analytics Agents Summary:"
  puts "   Monitor Agents: #{AiAgent.where(agent_type: 'monitor').count}"
  puts "   Data Analyst Agents: #{AiAgent.where(agent_type: 'data_analyst').count}"
  puts "   Total Analytics Agents: #{AiAgent.where(agent_type: ['monitor', 'data_analyst']).count}"

else
  puts "❌ Missing required data (account, user, or provider)"
  puts "   Account: #{admin_account&.name || 'NOT FOUND'}"
  puts "   User: #{admin_user&.name || 'NOT FOUND'}"
  puts "   Provider: #{provider&.name || 'NOT FOUND'}"
end

puts "✅ Monitoring and Analytics Agents seeding completed!"