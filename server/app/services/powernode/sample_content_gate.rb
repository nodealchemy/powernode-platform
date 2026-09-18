# frozen_string_literal: true

module Powernode
  # Single deployment-wide gate for OPT-IN sample/demo content.
  #
  # 2026-09-13 operator ruling (IMP-f1f96c292991): a clean install ships NO
  # sample data — a curated starter catalog is product, sample content is an
  # explicit opt-in. Behind this ONE SiteSetting, default OFF:
  #   - the 5 business example agents (Legal & Compliance Analyst, Life
  #     Sciences Research Analyst, Finance Operations Analyst, Sales
  #     Operations Specialist, Customer Success Agent) — server/db/seeds/
  #     autonomy_data_seed.rb;
  #   - the hobby/showcase node templates (rpi4-base, rpi4-hardened,
  #     web-apache, web-nginx) and the modules only they use (apache, nginx,
  #     rpi4-firmware) — System::AccountBootstrapService.seed_templates_for;
  #   - role modules used only by smoke seeds (docker-runtime, python-runtime,
  #     postgres-server, redis-cache) — extensions/system/server/db/seeds/
  #     role_modules_seed.rb. `nodejs-runtime` is DELIBERATELY EXCLUDED: on
  #     this deployment it is load-bearing for the live "powernode-ops-cell"
  #     NodeTemplate (verified 2026-09-18: 14 real NodeModuleAssignment rows,
  #     the only one of the five role modules with any), so it stays baseline
  #     product content, not sample content;
  #   - the local-qemu dev/test Provider block — node_module_catalog.rb.
  #
  # The Pro Cloud provider/regions/instance-types scaffold and the starter
  # catalog (base, hardened, arm64-uefi-base + system-base, security-
  # hardening, chrony) are product, NOT sample content, and are never gated
  # here.
  #
  # Read directly from SiteSetting (uncached): this gates a one-time seed /
  # per-account bootstrap decision, not a hot runtime path.
  module SampleContentGate
    SETTING_KEY = "system.sample_content.enabled"

    def self.enabled?
      SiteSetting.get(SETTING_KEY) == true
    rescue StandardError => e
      Rails.logger.error("[SampleContentGate] SiteSetting lookup failed: #{e.class}: #{e.message}") if defined?(Rails)
      false
    end
  end
end
