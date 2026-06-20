# frozen_string_literal: true

module Setup
  # Aggregates the ordered list of setup steps from two sources — static core
  # steps and steps contributed by *enabled* extensions via their extension.json
  # `setup_steps` manifest field — and annotates each with per-account completion
  # state. Slug-agnostic: core never names an extension; an extension contributes
  # a step purely by declaring it in its manifest, with zero core edits.
  #
  # Backs both the web wizard (GET /api/v1/setup/steps) and the headless CLI.
  module StepRegistry
    # Static core steps. Order 0–40 is reserved for core; extensions use 50+.
    # `completion: :user_exists` resolves the admin step's completion from the
    # presence of a user rather than a metadata stamp — an admin existing IS
    # "the admin step is done", however it was created.
    CORE_STEPS = [
      {
        key: "admin",
        title: "Administrator account",
        description: "Create the first administrator for this instance.",
        order: 0,
        required: true,
        owner: "core",
        completion: :user_exists,
        endpoint: "/api/v1/setup/admin",
        schema: [
          { key: "name",     label: "Full name", type: "text",     required: false },
          { key: "email",    label: "Email",     type: "text",     required: true },
          { key: "password", label: "Password",  type: "password", required: true, helper: "At least 8 characters." }
        ]
      },
      {
        key: "domain",
        title: "Domain",
        description: "The public domain this instance is served from.",
        order: 10,
        required: false,
        owner: "core",
        endpoint: "/api/v1/setup/steps/domain",
        schema: [
          { key: "domain", label: "Domain", type: "text", required: true, placeholder: "powernode.example.com" }
        ]
      },
      {
        key: "email",
        title: "Email (SMTP)",
        description: "Outbound email server. The password is stored in the active secret backend (Vault or DB-encrypted).",
        order: 20,
        required: false,
        owner: "core",
        endpoint: "/api/v1/setup/steps/email",
        schema: [
          { key: "smtp_host",         label: "SMTP host",    type: "text",     required: false, placeholder: "smtp.example.com" },
          { key: "smtp_port",         label: "SMTP port",    type: "text",     required: false, placeholder: "587" },
          { key: "smtp_username",     label: "Username",     type: "text",     required: false },
          { key: "smtp_password",     label: "Password",     type: "password", required: false },
          { key: "smtp_from_address", label: "From address", type: "text",     required: false, placeholder: "noreply@example.com" }
        ]
      },
      {
        key: "general_settings",
        title: "General settings",
        description: "Basic identity for this instance.",
        order: 30,
        required: false,
        owner: "core",
        endpoint: "/api/v1/setup/steps/general_settings",
        schema: [
          { key: "site_name",     label: "Site name",     type: "text", required: false, placeholder: "Powernode" },
          { key: "support_email", label: "Support email", type: "text", required: false, placeholder: "support@example.com" }
        ]
      },
      {
        key: "extension_selection",
        title: "Extensions",
        description: "Enable or disable the extensions installed in this build. Disabling is non-destructive — data is retained.",
        order: 40,
        required: false,
        owner: "core",
        component: "core/extension_selection",
        endpoint: "/api/v1/setup/steps/extension_selection"
      },
      {
        key: "seed",
        title: "Example data",
        description: "Optionally seed example data so the platform has something to work with.",
        order: 90,
        required: false,
        owner: "core",
        component: "core/seed",
        endpoint: "/api/v1/setup/steps/seed"
      }
    ].freeze

    class << self
      # Ordered, completion-annotated steps for an account (core + enabled exts).
      def steps_for(account)
        all_steps.sort_by { |s| s[:order].to_i }.map { |s| annotate(s, account) }
      end

      # Locate a step definition (unannotated) by key — used to validate POSTs.
      def find(key)
        key = key.to_s
        all_steps.find { |s| s[:key] == key }
      end

      # Bootstrap is complete once every *required* core step is done.
      def bootstrap_complete?(account)
        CORE_STEPS.select { |s| s[:required] }.all? { |s| step_completed?(s, account) }
      end

      # Pending (incomplete) steps grouped by owner, for GET /setup/status.
      def pending(account)
        steps_for(account).reject { |s| s[:completed] }.group_by { |s| s[:owner] }.map do |owner, steps|
          { owner: owner, steps: steps }
        end
      end

      # Merge per-account completion state onto a single step definition.
      def annotate(step, account)
        completed = step_completed?(step, account)
        step.merge(
          completed: completed,
          completed_at: completed ? completed_at(step, account)&.iso8601 : nil
        )
      end

      private

      def all_steps
        CORE_STEPS + extension_steps
      end

      def step_completed?(step, account)
        if step[:completion] == :user_exists
          users_exist?(account)
        else
          account.respond_to?(:setup_step_completed?) && account.setup_step_completed?(step[:key])
        end
      end

      def completed_at(step, account)
        return nil if step[:completion] == :user_exists
        return nil unless account.respond_to?(:setup_step_completed_at)

        account.setup_step_completed_at(step[:key])
      end

      def users_exist?(account)
        (account.respond_to?(:users) && account.users.exists?) || User.exists?
      end

      # Steps contributed by enabled extensions, read generically from each
      # extension.json `setup_steps`. No extension slug is named in core.
      def extension_steps
        Powernode::ExtensionRegistry.slugs.flat_map do |slug|
          next [] unless Shared::FeatureGateService.extension_enabled?(slug)

          Array(manifest_setup_steps(slug)).map do |raw|
            raw.deep_symbolize_keys.merge(owner: slug.to_s)
          end
        end
      end

      def manifest_setup_steps(slug)
        path = Shared::ExtensionPaths.manifest_for(slug)
        return [] if path.nil? || !path.exist?

        JSON.parse(File.read(path))["setup_steps"]
      rescue JSON::ParserError, IOError, SystemCallError => e
        Rails.logger.warn("[Setup::StepRegistry] could not read setup_steps for #{slug}: #{e.message}")
        []
      end
    end
  end
end
