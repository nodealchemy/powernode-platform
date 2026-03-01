# frozen_string_literal: true

module Ai
  module Constants
    module Statuses
      PENDING = "pending"
      QUEUED = "queued"
      RUNNING = "running"
      COMPLETED = "completed"
      FAILED = "failed"
      CANCELLED = "cancelled"
      PAUSED = "paused"
      TIMEOUT = "timeout"
      SKIPPED = "skipped"
      RETRYING = "retrying"

      ALL = [PENDING, QUEUED, RUNNING, COMPLETED, FAILED, CANCELLED, PAUSED, TIMEOUT, SKIPPED, RETRYING].freeze
      TERMINAL = [COMPLETED, FAILED, CANCELLED, TIMEOUT, SKIPPED].freeze
      ACTIVE = [PENDING, QUEUED, RUNNING, RETRYING].freeze
      IN_PROGRESS = [RUNNING, RETRYING].freeze
    end

    module ProviderTypes
      OPENAI = "openai"
      ANTHROPIC = "anthropic"
      OLLAMA = "ollama"
      GOOGLE = "google"
      AZURE = "azure"
      GROQ = "groq"
      MISTRAL = "mistral"
      COHERE = "cohere"
      GROK = "grok"
      STABILITY = "stability"
      REPLIT = "replit"

      ALL = [OPENAI, ANTHROPIC, OLLAMA, GOOGLE, AZURE, GROQ, MISTRAL, COHERE, GROK, STABILITY, REPLIT].freeze
      CHAT_CAPABLE = [OPENAI, ANTHROPIC, OLLAMA, GOOGLE, AZURE, GROQ, MISTRAL, COHERE, GROK].freeze
      OPENAI_COMPATIBLE = [OPENAI, GROQ, MISTRAL, AZURE, GROK, COHERE].freeze
    end

    module MemoryTiers
      WORKING = "working"
      SHORT_TERM = "short_term"
      LONG_TERM = "long_term"
      SHARED = "shared"

      ALL = [WORKING, SHORT_TERM, LONG_TERM, SHARED].freeze
    end

    module TrustTiers
      SUPERVISED = "supervised"
      MONITORED = "monitored"
      TRUSTED = "trusted"
      AUTONOMOUS = "autonomous"

      ALL = [SUPERVISED, MONITORED, TRUSTED, AUTONOMOUS].freeze

      THRESHOLDS = {
        SUPERVISED => 0.0,
        MONITORED => 0.4,
        TRUSTED => 0.7,
        AUTONOMOUS => 0.9
      }.freeze
    end

    module TeamTopologies
      STREAM_ALIGNED = "stream_aligned"
      PLATFORM = "platform"
      ENABLING = "enabling"
      COMPLICATED_SUBSYSTEM = "complicated_subsystem"

      ALL = [STREAM_ALIGNED, PLATFORM, ENABLING, COMPLICATED_SUBSYSTEM].freeze
    end

    module CoordinationStrategies
      CENTRALIZED = "centralized"
      DECENTRALIZED = "decentralized"
      HIERARCHICAL = "hierarchical"
      CONSENSUS = "consensus"
      PIPELINE = "pipeline"

      ALL = [CENTRALIZED, DECENTRALIZED, HIERARCHICAL, CONSENSUS, PIPELINE].freeze
    end

    module NodeTypes
      AI_AGENT = "ai_agent"
      API_CALL = "api_call"
      WEBHOOK = "webhook"
      CONDITION = "condition"
      TRANSFORM = "transform"
      DELAY = "delay"
      HUMAN_REVIEW = "human_review"
      PARALLEL = "parallel"
      LOOP = "loop"
      SUB_WORKFLOW = "sub_workflow"

      ALL = [AI_AGENT, API_CALL, WEBHOOK, CONDITION, TRANSFORM, DELAY, HUMAN_REVIEW, PARALLEL, LOOP, SUB_WORKFLOW].freeze
    end

    module MessageRoles
      SYSTEM = "system"
      USER = "user"
      ASSISTANT = "assistant"
      FUNCTION = "function"
      TOOL = "tool"
      DEVELOPER = "developer"

      ALL = [SYSTEM, USER, ASSISTANT, FUNCTION, TOOL, DEVELOPER].freeze
    end

    module CircuitBreakerStates
      CLOSED = "closed"
      OPEN = "open"
      HALF_OPEN = "half_open"

      ALL = [CLOSED, OPEN, HALF_OPEN].freeze
    end

    module LearningCategories
      PATTERN = "pattern"
      TECHNIQUE = "technique"
      DOMAIN_KNOWLEDGE = "domain_knowledge"
      TOOL_USAGE = "tool_usage"
      ERROR_RECOVERY = "error_recovery"
      OPTIMIZATION = "optimization"
      COLLABORATION = "collaboration"

      ALL = [PATTERN, TECHNIQUE, DOMAIN_KNOWLEDGE, TOOL_USAGE, ERROR_RECOVERY, OPTIMIZATION, COLLABORATION].freeze
    end

    module ModelTiers
      ECONOMY = "economy"
      STANDARD = "standard"
      PREMIUM = "premium"

      ALL = [ECONOMY, STANDARD, PREMIUM].freeze
    end

    module ReviewModes
      BLOCKING = "blocking"
      SHADOW = "shadow"

      ALL = [BLOCKING, SHADOW].freeze
    end

    module QuarantineSeverities
      LOW = "low"
      MEDIUM = "medium"
      HIGH = "high"
      CRITICAL = "critical"

      ALL = [LOW, MEDIUM, HIGH, CRITICAL].freeze
    end
  end
end
