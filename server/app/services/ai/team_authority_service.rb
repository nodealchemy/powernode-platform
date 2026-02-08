# frozen_string_literal: true

module Ai
  class TeamAuthorityService
    # Authority levels: 0 = human, 1 = manager/lead, 2 = coordinator/specialist, 3 = worker, 4 = reviewer/validator
    ROLE_TYPE_AUTHORITY = {
      "manager" => 1, "coordinator" => 2, "specialist" => 2,
      "worker" => 3, "reviewer" => 4, "validator" => 4
    }.freeze

    MEMBER_ROLE_AUTHORITY = {
      "manager" => 1, "coordinator" => 2, "facilitator" => 2, "analyst" => 2,
      "researcher" => 3, "writer" => 3, "executor" => 3, "reviewer" => 4
    }.freeze

    DOWNWARD_ONLY_MESSAGES = %w[task_assignment task_cancellation priority_change].freeze
    UPWARD_ONLY_MESSAGES = %w[escalation status_report].freeze
    BROADCAST_MIN_LEVEL = 2

    class AuthorityViolation < AiExceptions::AuthorizationError
      attr_reader :actor, :target, :action

      def initialize(message, actor: nil, target: nil, action: nil)
        @actor = actor
        @target = target
        @action = action
        super(message, details: { actor: actor&.class&.name, target: target&.class&.name, action: action })
      end
    end

    attr_reader :team

    def initialize(team:)
      @team = team
      @overrides = (team.team_config || {}).dig("authority_overrides") || {}
    end

    # Resolve authority level for an actor (TeamRole, AgentTeamMember, or nil for human)
    def authority_level(actor)
      return 0 if actor.nil?

      case actor
      when Ai::TeamRole
        return 1 if actor.respond_to?(:manager?) && actor.manager?

        ROLE_TYPE_AUTHORITY[actor.role_type] || 3
      when Ai::AgentTeamMember
        return 1 if actor.is_lead?

        MEMBER_ROLE_AUTHORITY[actor.role] || 3
      else
        3
      end
    end

    # Actor delegates a task to target — actor must have can_delegate and higher authority
    def authorize_delegation!(actor, target)
      return if actor.nil? # Human always allowed

      actor_level = authority_level(actor)
      target_level = authority_level(target)

      unless has_delegate_flag?(actor)
        raise AuthorityViolation.new(
          "#{actor_name(actor)} does not have delegation authority",
          actor: actor, target: target, action: :delegate
        )
      end

      # Lateral delegation allowed via override
      if actor_level == target_level && @overrides["lateral_delegation_allowed"]
        return
      end

      # Specialists can delegate via override
      if actor_level == 2 && @overrides["specialists_can_delegate"]
        return
      end

      unless actor_level < target_level
        raise AuthorityViolation.new(
          "#{actor_name(actor)} (level #{actor_level}) cannot delegate to #{actor_name(target)} (level #{target_level})",
          actor: actor, target: target, action: :delegate
        )
      end
    end

    # Actor escalates to target — actor must have can_escalate and target must be higher
    def authorize_escalation!(actor, target)
      return if actor.nil?

      actor_level = authority_level(actor)
      target_level = authority_level(target)

      unless has_escalate_flag?(actor)
        raise AuthorityViolation.new(
          "#{actor_name(actor)} does not have escalation authority",
          actor: actor, target: target, action: :escalate
        )
      end

      unless target_level < actor_level
        raise AuthorityViolation.new(
          "#{actor_name(actor)} (level #{actor_level}) cannot escalate to #{actor_name(target)} (level #{target_level})",
          actor: actor, target: target, action: :escalate
        )
      end

      # Skip-level check: workers (3) escalating directly to managers (1) requires override
      level_gap = actor_level - target_level
      if level_gap > 1 && !@overrides["workers_can_escalate_directly"] && !@overrides["emergency_escalation_enabled"]
        raise AuthorityViolation.new(
          "#{actor_name(actor)} cannot skip-level escalate to #{actor_name(target)} without authorization",
          actor: actor, target: target, action: :escalate
        )
      end
    end

    # Validate message direction based on message type
    def authorize_message!(from, to, message_type)
      return if from.nil?

      from_level = authority_level(from)
      to_level = authority_level(to)

      if DOWNWARD_ONLY_MESSAGES.include?(message_type) && from_level >= to_level
        raise AuthorityViolation.new(
          "#{message_type} messages can only be sent downward (#{actor_name(from)} level #{from_level} -> #{actor_name(to)} level #{to_level})",
          actor: from, target: to, action: :message
        )
      end

      if UPWARD_ONLY_MESSAGES.include?(message_type) && from_level <= to_level
        raise AuthorityViolation.new(
          "#{message_type} messages can only be sent upward (#{actor_name(from)} level #{from_level} -> #{actor_name(to)} level #{to_level})",
          actor: from, target: to, action: :message
        )
      end

      if message_type == "broadcast" && from_level > BROADCAST_MIN_LEVEL
        raise AuthorityViolation.new(
          "#{actor_name(from)} (level #{from_level}) does not have broadcast authority (requires level #{BROADCAST_MIN_LEVEL} or higher)",
          actor: from, target: to, action: :broadcast
        )
      end
    end

    # Validate task modification authority
    def authorize_task_modification!(actor, task, action)
      return if actor.nil?

      actor_level = authority_level(actor)

      case action
      when :cancel, :reassign
        task_level = resolve_task_level(task)
        unless actor_level < task_level
          raise AuthorityViolation.new(
            "#{actor_name(actor)} (level #{actor_level}) cannot #{action} a task assigned to level #{task_level}",
            actor: actor, target: nil, action: action
          )
        end
      when :modify_priority
        unless actor_level <= 2
          raise AuthorityViolation.new(
            "#{actor_name(actor)} (level #{actor_level}) cannot modify task priority (requires level 1-2)",
            actor: actor, target: nil, action: :modify_priority
          )
        end
      end
    end

    # Validate memory pool access control
    def authorize_memory_control!(actor, _pool)
      return if actor.nil?

      actor_level = authority_level(actor)
      unless actor_level <= 2
        raise AuthorityViolation.new(
          "#{actor_name(actor)} (level #{actor_level}) cannot grant/revoke memory access (requires level 1-2)",
          actor: actor, target: nil, action: :memory_control
        )
      end
    end

    # Validate no self-review
    def authorize_review!(reviewer_role, task)
      reviewer_agent_id = case reviewer_role
                          when Ai::TeamRole then reviewer_role.ai_agent_id
                          when Ai::AgentTeamMember then reviewer_role.ai_agent_id
                          end

      task_agent_id = task.respond_to?(:assigned_agent_id) ? task.assigned_agent_id : nil

      if reviewer_agent_id.present? && reviewer_agent_id == task_agent_id
        raise AuthorityViolation.new(
          "Agent cannot review their own task",
          actor: reviewer_role, target: nil, action: :self_review
        )
      end
    end

    # Validate authority changes (role, capabilities, lead status)
    def authorize_authority_change!(actor, target, changes)
      return if actor.nil?

      actor_level = authority_level(actor)

      unless actor_level <= 1
        raise AuthorityViolation.new(
          "#{actor_name(actor)} (level #{actor_level}) cannot change member authority (requires level 0-1)",
          actor: actor, target: target, action: :authority_change
        )
      end

      # Leader cannot promote above their own level
      if changes[:role].present? && actor_level > 0
        new_level = MEMBER_ROLE_AUTHORITY[changes[:role]] || ROLE_TYPE_AUTHORITY[changes[:role]] || 3
        if new_level < actor_level
          raise AuthorityViolation.new(
            "#{actor_name(actor)} cannot promote #{actor_name(target)} above their own authority level",
            actor: actor, target: target, action: :authority_change
          )
        end
      end

      # Cannot grant lead status unless actor is lead/human
      if changes[:is_lead] == true && actor_level > 0
        raise AuthorityViolation.new(
          "Only human users can grant lead status",
          actor: actor, target: target, action: :grant_lead
        )
      end
    end

    # Validate member management actions
    def authorize_member_management!(actor, action)
      return if actor.nil?

      actor_level = authority_level(actor)

      case action
      when :add_member
        unless actor_level <= 2
          raise AuthorityViolation.new(
            "#{actor_name(actor)} (level #{actor_level}) cannot add members (requires level 0-2)",
            actor: actor, target: nil, action: :add_member
          )
        end
      when :remove_member
        unless actor_level <= 1
          raise AuthorityViolation.new(
            "#{actor_name(actor)} (level #{actor_level}) cannot remove members (requires level 0-1)",
            actor: actor, target: nil, action: :remove_member
          )
        end
      when :set_role
        unless actor_level <= 1
          raise AuthorityViolation.new(
            "#{actor_name(actor)} (level #{actor_level}) cannot set member roles (requires level 0-1)",
            actor: actor, target: nil, action: :set_role
          )
        end
      end
    end

    private

    def has_delegate_flag?(actor)
      case actor
      when Ai::TeamRole then actor.can_delegate
      when Ai::AgentTeamMember then authority_level(actor) <= 2 || @overrides["specialists_can_delegate"]
      else false
      end
    end

    def has_escalate_flag?(actor)
      case actor
      when Ai::TeamRole then actor.can_escalate
      when Ai::AgentTeamMember then true # All members can escalate by default
      else false
      end
    end

    def resolve_task_level(task)
      if task.respond_to?(:assigned_role) && task.assigned_role
        authority_level(task.assigned_role)
      elsif task.respond_to?(:assigned_agent_id) && task.assigned_agent_id
        3 # Default worker level for direct agent assignment
      else
        3
      end
    end

    def actor_name(actor)
      case actor
      when Ai::TeamRole then actor.role_name
      when Ai::AgentTeamMember then actor.agent_name
      when NilClass then "Human"
      else actor.class.name
      end
    end
  end
end
