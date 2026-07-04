# frozen_string_literal: true

module Ai
  class SkillService
    attr_reader :account

    class ValidationError < StandardError; end
    class NotFoundError < StandardError; end

    def initialize(account:)
      @account = account
    end

    def list_skills(filters: {}, page: 1, per_page: 20)
      skills = scoped_skills(filters[:scope])

      skills = skills.by_category(filters[:category]) if filters[:category].present?
      skills = skills.where(status: filters[:status]) if filters[:status].present?
      skills = skills.where(is_enabled: filters[:enabled] == "true") if filters[:enabled].present?

      if filters[:search].present?
        query = "%#{sanitize_sql_like(filters[:search])}%"
        skills = skills.where("name ILIKE :q OR description ILIKE :q", q: query)
      end

      skills.order(is_system: :desc, name: :asc)
            .page(page).per(per_page)
    end

    def find_skill(skill_id:)
      # ID first, then slug — override-aware (resolve_for): if a global skill
      # and the account's own clone/override share a slug, the account's row
      # wins rather than whichever a bare find_by(slug:) happened to return.
      skill = Ai::Skill.for_account(account&.id).find_by(id: skill_id) ||
              Ai::Skill.resolve_for(account&.id, slug: skill_id)
      raise NotFoundError, "Skill not found" unless skill

      skill
    end

    def create_skill(attributes:, knowledge_base_id: nil, mcp_server_ids: [])
      requested_provenance, attrs = extract_provenance(attributes)
      skill = Ai::Skill.new(attrs)
      skill.account = account
      skill.ai_knowledge_base_id = knowledge_base_id if knowledge_base_id.present?

      # Provenance + content/injection scan (G6): record where the content came
      # from and derive a trust_level from a static scan of system_prompt /
      # commands / recipe text. trust_level is computed here — never accepted
      # from the caller — so injected content cannot self-declare "trusted".
      apply_provenance_and_trust(skill, requested_provenance)

      Ai::Skill.transaction do
        skill.save!
        attach_mcp_servers(skill, mcp_server_ids) if mcp_server_ids.present?
      end

      skill
    rescue ActiveRecord::RecordInvalid => e
      raise ValidationError, e.message
    end

    def update_skill(skill_id:, attributes:, mcp_server_ids: nil)
      skill = find_skill(skill_id: skill_id)
      raise ValidationError, "Cannot modify system skills" if skill.is_system && account.present?

      requested_provenance, attrs = extract_provenance(attributes)

      Ai::Skill.transaction do
        skill.assign_attributes(attrs)
        # Re-scan after applying the edit so an update that injects malicious
        # content downgrades the trust_level (and re-gates the attach path).
        apply_provenance_and_trust(skill, requested_provenance || skill.provenance)
        skill.save!
        if mcp_server_ids
          validated_ids = scoped_mcp_servers.where(id: mcp_server_ids).pluck(:id)
          skill.mcp_server_ids = validated_ids
        end
      end

      skill.reload
    rescue ActiveRecord::RecordInvalid => e
      raise ValidationError, e.message
    end

    def delete_skill(skill_id:)
      skill = find_skill(skill_id: skill_id)
      raise ValidationError, "Cannot delete system skills" if skill.is_system

      skill.destroy!
    end

    def toggle_skill(skill_id:, enabled:)
      skill = find_skill(skill_id: skill_id)

      if enabled
        skill.activate!
      else
        skill.deactivate!
      end

      skill
    end

    def assign_to_agent(skill_id:, agent_id:, priority: 0)
      skill = find_skill(skill_id: skill_id)
      agent = ::Ai::Agent.for_account(account.id).find(agent_id)

      # Attach gate (G6): never bind content the scanner flagged as untrusted
      # (high-risk injection / secret-exfiltration markers) to an agent. The
      # skill must be re-vetted (and its trust_level cleared) before it can run.
      if skill.untrusted?
        raise ValidationError,
              "Cannot attach untrusted skill '#{skill.name}' to an agent: failed content/injection scan (re-vet required)"
      end

      agent_skill = Ai::AgentSkill.create!(
        ai_agent_id: agent.id,
        ai_skill_id: skill.id,
        priority: priority
      )
      agent_skill
    rescue ActiveRecord::RecordInvalid => e
      raise ValidationError, e.message
    rescue ActiveRecord::RecordNotFound
      raise NotFoundError, "Agent not found"
    end

    def remove_from_agent(skill_id:, agent_id:)
      agent_skill = Ai::AgentSkill.find_by!(ai_agent_id: agent_id, ai_skill_id: skill_id)
      agent_skill.destroy!
    rescue ActiveRecord::RecordNotFound
      raise NotFoundError, "Agent-skill assignment not found"
    end

    def agent_skills(agent_id:)
      agent = ::Ai::Agent.for_account(account.id).find(agent_id)
      agent.agent_skills.includes(:skill).order(priority: :asc)
    rescue ActiveRecord::RecordNotFound
      raise NotFoundError, "Agent not found"
    end

    def skill_agents(skill_id:)
      skill = find_skill(skill_id: skill_id)
      skill.agents.includes(:creator, :provider)
    end

    private

    # Pull caller-supplied provenance off the attribute hash and drop any
    # caller-supplied trust_level — trust_level is derived from the content
    # scan, never trusted from input. Returns [provenance_or_nil, sanitized].
    def extract_provenance(attributes)
      attrs = attributes.to_h.symbolize_keys
      provenance = attrs.delete(:provenance)
      attrs.delete(:trust_level)
      [provenance.presence, attrs]
    end

    # Records provenance and derives trust_level from a static content/injection
    # scan. External (community/imported) content never defaults to "trusted":
    # clean external content lands at "review" pending human vetting, and any
    # scan finding downgrades further (review → untrusted on high risk).
    def apply_provenance_and_trust(skill, requested_provenance)
      provenance = Ai::Skill::PROVENANCES.include?(requested_provenance) ? requested_provenance : Ai::Skill::DEFAULT_PROVENANCE
      skill.provenance = provenance

      result = Ai::Skill::ContentScanService.scan(skill)
      skill.trust_level = resolve_trust_level(provenance, result)

      log_scan(skill, provenance, result)
      result
    end

    # Combine origin + scan verdict into the persisted trust_level. The more
    # suspicious of the two wins (TRUST_LEVELS is ordered trusted→untrusted, so
    # the higher index is the lower trust).
    def resolve_trust_level(provenance, scan_result)
      scan_level = scan_result[:suggested_trust_level]
      base_level = provenance == "internal" ? "trusted" : "review"

      [base_level, scan_level].max_by { |lvl| Ai::Skill::TRUST_LEVELS.index(lvl) }
    end

    # Crypto-safe: logs only counts/categories, never the scanned content or any
    # matched substring (which could itself be a secret).
    def log_scan(skill, provenance, result)
      return if result[:clean]

      categories = result[:findings].map { |f| f[:category] }.uniq.join(",")
      Rails.logger.warn(
        "[Ai::SkillService] content scan: skill='#{skill.name}' provenance=#{provenance} " \
        "risk=#{result[:risk]} trust_level=#{skill.trust_level} findings=#{result[:findings].size} categories=#{categories}"
      )
    rescue StandardError => e
      Rails.logger.error "[Ai::SkillService] scan log failed: #{e.message}"
    end

    # Apply ?scope=global|custom|all (default: for_account = global + own) so the
    # global baseline skill library stays visible after the global/account split.
    def scoped_skills(scope)
      case scope.to_s
      when "global" then Ai::Skill.global
      when "custom" then Ai::Skill.owned_by_account(account&.id)
      when "all"    then Ai::Skill.all
      else Ai::Skill.for_account(account&.id)
      end
    end

    def attach_mcp_servers(skill, mcp_server_ids)
      servers = scoped_mcp_servers.where(id: mcp_server_ids)
      skill.mcp_servers << servers
    end

    def scoped_mcp_servers
      McpServer.where(account_id: [account&.id, nil])
    end

    def sanitize_sql_like(string)
      string.to_s.gsub(/[%_\\]/) { |m| "\\#{m}" }
    end
  end
end
