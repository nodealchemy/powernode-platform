#!/usr/bin/env ruby
# frozen_string_literal: true

# Loop Protection Manager - Utility for managing worker loop detection
require_relative '../config/boot'

class LoopProtectionManager
  def self.status
    puts "[STATUS] Loop Protection Status"
    puts "=" * 50

    redis = Sidekiq.redis_pool.with { |conn| conn }

    # Find all job execution tracking keys
    execution_keys = redis.keys("job_executions:*")
    disabled_keys = redis.keys("job_disabled:*")
    failure_keys = redis.keys("job_failures:*")

    puts "\n[INFO] Current Tracking:"
    puts "  Active execution trackers: #{execution_keys.length}"
    puts "  Disabled jobs: #{disabled_keys.length}"
    puts "  Failure trackers: #{failure_keys.length}"

    if disabled_keys.any?
      puts "\n[BLOCKED] Disabled Jobs:"
      disabled_keys.each do |key|
        job_key = key.sub('job_disabled:', '')
        reason = redis.get(key)
        ttl = redis.ttl(key)
        puts "  - #{job_key}: #{reason} (expires in #{ttl}s)"
      end
    end

    if execution_keys.any?
      puts "\n[INFO] Recent Executions (last 10 trackers):"
      execution_keys.first(10).each do |key|
        job_key = key.sub('job_executions:', '')
        executions = redis.lrange(key, 0, -1).map(&:to_f)
        recent_count = executions.count { |ts| (Time.current.to_f - ts) <= 60 }
        puts "  - #{job_key}: #{executions.length} total, #{recent_count} in last minute"
      end
    end
  end

  def self.clear_all
    puts "[CLEANUP] Clearing all loop protection data..."

    redis = Sidekiq.redis_pool.with { |conn| conn }

    patterns = [
      "job_executions:*",
      "job_disabled:*",
      "job_failures:*",
      "job_success:*"
    ]

    total_deleted = 0
    patterns.each do |pattern|
      keys = redis.keys(pattern)
      if keys.any?
        deleted = redis.del(*keys)
        total_deleted += deleted
        puts "  Deleted #{deleted} keys matching #{pattern}"
      end
    end

    puts "[OK] Cleared #{total_deleted} total keys"
  end

  def self.enable_job(job_pattern)
    puts "[UNLOCK] Enabling jobs matching: #{job_pattern}"

    redis = Sidekiq.redis_pool.with { |conn| conn }
    disabled_keys = redis.keys("job_disabled:*#{job_pattern}*")

    if disabled_keys.any?
      deleted = redis.del(*disabled_keys)
      puts "[OK] Enabled #{deleted} disabled jobs"
    else
      puts "[INFO] No disabled jobs found matching pattern"
    end
  end

  def self.help
    puts <<~HELP
      [TOOLS] Loop Protection Manager

      Commands:
        status                    - Show current loop protection status
        clear                     - Clear all loop protection data
        enable [pattern]          - Enable jobs matching pattern
        help                      - Show this help message

      Examples:
        ruby loop-protection-manager.rb status
        ruby loop-protection-manager.rb clear
        ruby loop-protection-manager.rb enable AiWorkflowExecutionJob
    HELP
  end
end

# Command line interface
case ARGV[0]
when 'status'
  LoopProtectionManager.status
when 'clear'
  LoopProtectionManager.clear_all
when 'enable'
  pattern = ARGV[1] || ''
  LoopProtectionManager.enable_job(pattern)
when 'help', nil
  LoopProtectionManager.help
else
  puts "[ERROR] Unknown command: #{ARGV[0]}"
  puts "Run 'ruby loop-protection-manager.rb help' for usage"
  exit 1
end
