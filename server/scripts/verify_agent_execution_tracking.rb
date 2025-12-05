#!/usr/bin/env ruby
# frozen_string_literal: true

# Verification script for agent execution tracking fix
# This script verifies that workflow-triggered AI agent executions are properly tracked

puts "=" * 80
puts "Agent Execution Tracking Verification"
puts "=" * 80
puts ""

# 1. Overall Statistics
puts "📊 OVERALL STATISTICS"
puts "-" * 80

total_agents = AiAgent.count
total_agent_executions = AiAgentExecution.count
total_workflows = AiWorkflow.count
total_workflow_runs = AiWorkflowRun.count
total_agent_nodes = AiWorkflowNodeExecution.where(node_type: 'ai_agent').count

puts "AI Agents: #{total_agents}"
puts "AI Agent Executions: #{total_agent_executions}"
puts "Workflows: #{total_workflows}"
puts "Workflow Runs: #{total_workflow_runs}"
puts "AI Agent Node Executions: #{total_agent_nodes}"
puts ""

# 2. Agent Execution Counts
puts "🤖 AGENT EXECUTION COUNTS"
puts "-" * 80

AiAgent.includes(:ai_agent_executions).find_each do |agent|
  exec_count = agent.ai_agent_executions.count
  status = exec_count > 0 ? "✅" : "⚠️ "
  puts "#{status} #{agent.name}: #{exec_count} executions"
end
puts ""

# 3. Workflow Node Execution Linkage
puts "🔗 WORKFLOW NODE EXECUTION LINKAGE"
puts "-" * 80

linked_count = AiWorkflowNodeExecution.where(node_type: 'ai_agent').where.not(ai_agent_execution_id: nil).count
unlinked_count = AiWorkflowNodeExecution.where(node_type: 'ai_agent').where(ai_agent_execution_id: nil).count
linkage_rate = total_agent_nodes > 0 ? (linked_count.to_f / total_agent_nodes * 100).round(1) : 0

puts "Total AI Agent Node Executions: #{total_agent_nodes}"
puts "✅ With linked AiAgentExecution: #{linked_count}"
puts "⚠️  Without linked AiAgentExecution: #{unlinked_count}"
puts "Linkage Rate: #{linkage_rate}%"
puts ""

# 4. Recent Workflow Runs Analysis
puts "📋 RECENT WORKFLOW RUNS (Last 10)"
puts "-" * 80

recent_runs = AiWorkflowRun.order(created_at: :desc).limit(10)

if recent_runs.any?
  recent_runs.each do |run|
    agent_nodes = run.ai_workflow_node_executions.where(node_type: 'ai_agent')
    linked = agent_nodes.where.not(ai_agent_execution_id: nil).count
    total = agent_nodes.count

    status_icon = case run.status
                  when 'completed' then '✅'
                  when 'failed' then '❌'
                  when 'running' then '🔄'
                  else '⏸️ '
                  end

    linkage_icon = total > 0 && linked == total ? '✅' : (total > 0 ? '⚠️ ' : '➖')

    puts "#{status_icon} #{run.ai_workflow.name}"
    puts "   Run ID: #{run.run_id}"
    puts "   Status: #{run.status}"
    puts "   Started: #{run.started_at&.strftime('%Y-%m-%d %H:%M:%S') || 'Not started'}"
    puts "   #{linkage_icon} Agent Nodes: #{linked}/#{total} linked"
    puts ""
  end
else
  puts "No workflow runs found"
  puts ""
end

# 5. Validation Results
puts "✨ VALIDATION RESULTS"
puts "-" * 80

validations = []

# Check if any agents have executions
if total_agent_executions > 0
  validations << { status: :pass, message: "Agent executions are being created" }
else
  validations << { status: :warn, message: "No agent executions found (expected if no workflows have run since fix)" }
end

# Check linkage for recent runs (created after a certain point)
recent_linked_rate = if total_agent_nodes > 0
                       recent_nodes = AiWorkflowNodeExecution.where(node_type: 'ai_agent')
                                                            .where('created_at > ?', 1.hour.ago)
                       if recent_nodes.any?
                         linked = recent_nodes.where.not(ai_agent_execution_id: nil).count
                         (linked.to_f / recent_nodes.count * 100).round(1)
                       else
                         nil
                       end
                     end

if recent_linked_rate
  if recent_linked_rate == 100
    validations << { status: :pass, message: "Recent workflow runs: 100% linkage rate" }
  elsif recent_linked_rate >= 80
    validations << { status: :warn, message: "Recent workflow runs: #{recent_linked_rate}% linkage rate (investigate partial failures)" }
  else
    validations << { status: :fail, message: "Recent workflow runs: #{recent_linked_rate}% linkage rate (fix may not be working)" }
  end
else
  validations << { status: :info, message: "No recent workflow runs (within 1 hour) to analyze" }
end

# Check for orphaned agent executions
orphaned_executions = AiAgentExecution.where.not(id: AiWorkflowNodeExecution.select(:ai_agent_execution_id).distinct)
if orphaned_executions.any?
  validations << { status: :warn, message: "#{orphaned_executions.count} agent executions not linked to workflow nodes (may be direct API executions)" }
end

validations.each do |validation|
  icon = case validation[:status]
         when :pass then '✅'
         when :warn then '⚠️ '
         when :fail then '❌'
         when :info then 'ℹ️ '
         end

  puts "#{icon} #{validation[:message]}"
end

puts ""

# 6. Overall Assessment
puts "🎯 OVERALL ASSESSMENT"
puts "-" * 80

failures = validations.count { |v| v[:status] == :fail }
warnings = validations.count { |v| v[:status] == :warn }
passes = validations.count { |v| v[:status] == :pass }

if failures > 0
  puts "❌ FAILED: The fix does not appear to be working correctly"
  puts "   Action Required: Review error logs and verify implementation"
elsif warnings > 0 && passes == 0
  puts "⚠️  INCOMPLETE: No workflow runs since fix was deployed"
  puts "   Action Required: Run a test workflow to validate the fix"
elsif warnings > 0
  puts "⚠️  WARNING: Fix is working but some issues detected"
  puts "   Action Recommended: Review warnings and investigate any anomalies"
else
  puts "✅ PASSED: Agent execution tracking is working correctly!"
  puts "   All workflow-triggered agent executions are being properly tracked"
end

puts ""
puts "=" * 80
puts "Verification Complete"
puts "=" * 80
