# frozen_string_literal: true

# A2A Protocol Configuration
# Configures the Agent-to-Agent protocol implementation

Rails.application.config.after_initialize do
  # Reload skill registry on initialization
  A2a::SkillRegistry.reload! if defined?(A2a::SkillRegistry)
end
