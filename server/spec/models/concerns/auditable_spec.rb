# frozen_string_literal: true

require "rails_helper"

# Every model that includes Auditable must be able to produce an AuditLog row.
#
# AuditLog requires an account and `audit_logs.account_id` is NOT NULL, so a
# model that cannot resolve one produces no audit trail at all. Before this
# spec existed the concern swallowed that failure into a Rails.logger line, so
# ~25 models had a permanent audit blind spot that read as working.
#
# This spec walks the models rather than naming them, so a new model that
# includes Auditable without a reachable account fails here instead of going
# quiet in production.
RSpec.describe Auditable do
  Rails.application.eager_load!

  # Models with no owning tenant. Each suppresses its own audit writes via
  # `audit_without_account!`; this list exists so the exemption is visible in
  # one place and cannot grow without a reviewer noticing. The set is asserted
  # to match the declarations exactly, in both directions.
  EXPECTED_EXEMPTIONS = %w[
    KnowledgeBase::Category
    KnowledgeBase::Tag
    Monitoring::CircuitBreaker
    ValidationRule
  ].freeze

  # Models owned by an extension submodule that have no account path. Core
  # cannot declare on their behalf (an extension owns its own models), so they
  # are recorded here instead and remain a real audit gap until the extension
  # adds `audit_without_account!` or `audit_account_via`. Listing them keeps
  # the gap visible without letting a *core* model land in the same state.
  EXTENSION_OWNED_GAPS = {
    "SupplyChain::License" => "global SPDX licence catalogue, not tenant-owned data; " \
                              "needs audit_without_account! in extensions/supply-chain",
    "SupplyChain::ScanTemplate" => "system scan templates have a nullable account; " \
                                   "needs audit_optional_account! in extensions/supply-chain"
  }.freeze

  # Models whose records cannot be built at all today, so they get the
  # structural check only. None of these are audit defects — each model reaches
  # an account fine — but each blocks behavioural coverage until it is fixed.
  # Every entry is the error `FactoryBot.create` currently raises.
  RECORDS_THAT_CANNOT_BE_BUILT = {
    "Ai::PersistentContext" => "context_type is not included in the list " \
                               "(factory sets \"agent\", model allows agent_memory/knowledge_base/shared_context)",
    "Ai::ContextEntry" => "builds an Ai::PersistentContext, which is invalid for the reason above",
    "Devops::KubernetesNode" => "Node instance must exist (factory sets no node_instance)",
    "SupplyChain::SbomDiff" => "SBOMs must belong to the same account (factory builds two unrelated SBOMs)",
    # Not a factory defect: the model validates, scopes and branches on a
    # workflow_type column that knowledge_base_workflows does not have, so
    # every save raises NoMethodError. The model is unusable in production too.
    "KnowledgeBase::Workflow" => "undefined method `workflow_type' — model references a column " \
                                 "that does not exist in knowledge_base_workflows"
  }.freeze

  # Models with no FactoryBot factory. They get the structural check only.
  # Shrinking this list is strictly an improvement; growing it means a new
  # model shipped without a factory and loses behavioural coverage here.
  MODELS_WITHOUT_FACTORY = %w[
    CommunityAgentReport
    Devops::AccountGitWebhookConfig
    Devops::SecretReference
    Devops::SwarmDeployment
    Devops::SwarmEvent
    Devops::SwarmNode
    Devops::SwarmService
    Devops::SwarmStack
    KnowledgeBase::Attachment
    KnowledgeBase::Comment
    KnowledgeBase::Tag
    Marketing::Campaign
  ].freeze

  def self.auditable_models
    ApplicationRecord.descendants
                     .select { |klass| klass.include?(Auditable) }
                     .reject(&:abstract_class?)
                     .sort_by(&:name)
  end

  def self.factory_for(klass)
    FactoryBot.factories.to_a.find { |factory| safe_build_class(factory) == klass.name }&.name
  end

  def self.safe_build_class(factory)
    factory.build_class.name
  rescue StandardError
    nil
  end

  it "finds the models to check" do
    expect(self.class.auditable_models.size).to be >= 100
  end

  describe "account resolution" do
    it "exempts exactly the models the allowlist names" do
      declared = self.class.auditable_models.select { |m| m.audit_account_exemption.present? }.map(&:name)
      expect(declared).to match_array(EXPECTED_EXEMPTIONS)
    end

    auditable_models.each do |model|
      context model.name do
        it "can name the account its audit rows belong to" do
          if model.audit_account_exemption.present?
            expect(EXPECTED_EXEMPTIONS).to include(model.name),
                                           "#{model.name} exempts itself from auditing " \
                                           "(#{model.audit_account_exemption}) but is not in " \
                                           "EXPECTED_EXEMPTIONS. Add it there with the reason."
            next
          end

          if EXTENSION_OWNED_GAPS.key?(model.name)
            skip "known extension-owned audit gap: #{EXTENSION_OWNED_GAPS[model.name]}"
          end

          has_own_association = model.reflect_on_association(:account).present?
          has_delegated_method = model.method_defined?(:account)
          has_declared_sources = model.audit_account_sources.any?
          has_custom_hook = model.instance_method(:audit_account).owner != Auditable

          expect(has_own_association || has_delegated_method || has_declared_sources || has_custom_hook)
            .to be(true),
                "#{model.name} includes Auditable but has no path to an account. Every AuditLog " \
                "row requires one, so its audit writes would fail silently. Declare a path with " \
                "audit_account_via, or audit_without_account! if it has no owning tenant."
        end

        it "declares a path that actually terminates at an account" do
          skip "no declared path" if model.audit_account_sources.empty?

          model.audit_account_sources.each do |path|
            owner = path.reduce(model) do |klass, segment|
              reflection = klass.reflect_on_association(segment)
              expect(reflection).to be_present,
                                    "#{model.name} declares audit_account_via #{path.inspect} but " \
                                    "#{klass.name} has no association :#{segment}."
              reflection.klass
            end

            terminates = owner == Account ||
                         owner.reflect_on_association(:account).present? ||
                         owner.method_defined?(:account)

            expect(terminates).to be(true),
                                  "#{model.name} declares audit_account_via #{path.inspect} but " \
                                  "#{owner.name} cannot produce an account."
          end
        end
      end
    end
  end

  describe "audit log writes" do
    # Each example asserts only about its own model. A factory pulls in other
    # Auditable records, and raising on *their* audit failures would fail this
    # example for someone else's gap. The raising policy is proven separately
    # under "failure policy" below.
    around do |example|
      previous = Auditable.raise_on_failure
      Auditable.raise_on_failure = false
      Auditable.with_logging { example.run }
    ensure
      Auditable.raise_on_failure = previous
    end

    auditable_models.reject { |m| MODELS_WITHOUT_FACTORY.include?(m.name) }.each do |model|
      factory = factory_for(model)

      context model.name do
        it "writes an AuditLog row when a record is created" do
          skip "no factory for #{model.name}" if factory.nil?
          if EXTENSION_OWNED_GAPS.key?(model.name)
            skip "known extension-owned audit gap: #{EXTENSION_OWNED_GAPS[model.name]}"
          end
          if RECORDS_THAT_CANNOT_BE_BUILT.key?(model.name)
            skip "cannot build a valid record: #{RECORDS_THAT_CANNOT_BE_BUILT[model.name]}"
          end

          record = FactoryBot.create(factory)

          if model.audit_account_exemption.present?
            expect(audit_rows_for(record)).to be_empty,
                                              "#{model.name} is exempt from auditing but wrote a row."
            next
          end

          if record.audit_account.nil?
            expect(model.audit_optional_account_reason).to be_present,
                                                           "This #{model.name} has no account and the model does not " \
                                                           "declare audit_optional_account!, so its audit row is lost."
            expect(audit_rows_for(record)).to be_empty
            next
          end

          rows = audit_rows_for(record)
          expect(rows).not_to be_empty,
                              "Creating a #{model.name} produced no AuditLog row."
          expect(rows.first.account_id).to eq(record.audit_account.id)
        end
      end
    end
  end

  # Update and destroy resolve the account through the same hook as create, so
  # a sample is enough to prove the other two callbacks are wired to it.
  describe "update and destroy" do
    around { |example| Auditable.with_logging { example.run } }

    it "writes an AuditLog row when a record is updated" do
      iteration = FactoryBot.create(:ai_ralph_iteration)
      iteration.update!(status: "completed")

      row = AuditLog.find_by(resource_type: "Ai::RalphIteration", resource_id: iteration.id, action: "updated")
      expect(row).to be_present
      expect(row.account_id).to eq(iteration.ralph_loop.account_id)
    end

    it "writes an AuditLog row when a record is destroyed" do
      iteration = FactoryBot.create(:ai_ralph_iteration)
      account_id = iteration.ralph_loop.account_id
      iteration.destroy!

      row = AuditLog.find_by(resource_type: "Ai::RalphIteration", resource_id: iteration.id, action: "deleted")
      expect(row).to be_present
      expect(row.account_id).to eq(account_id)
    end
  end

  describe "failure policy" do
    let(:broken) { Ai::RalphIteration.new }

    it "instruments a counted event when an audit write cannot resolve an account" do
      events = []
      subscriber = ActiveSupport::Notifications.subscribe(Auditable::FAILURE_NOTIFICATION) do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end

      Auditable.logging_enabled = true
      Auditable.raise_on_failure = false
      allow(broken).to receive(:audit_account).and_return(nil)
      broken.send(:write_audit_log, "created")

      expect(events.size).to eq(1)
      expect(events.first.payload[:model]).to eq("Ai::RalphIteration")
      expect(events.first.payload[:error_class]).to eq("Auditable::AccountUnresolved")
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
      Auditable.logging_enabled = !Rails.env.test?
      Auditable.raise_on_failure = Rails.env.test?
    end

    it "does not swallow the failure in test so CI catches a regression" do
      Auditable.logging_enabled = true
      allow(broken).to receive(:audit_account).and_return(nil)

      expect { broken.send(:write_audit_log, "created") }.to raise_error(Auditable::AccountUnresolved)
    ensure
      Auditable.logging_enabled = !Rails.env.test?
    end

    it "is inert by default in the test environment" do
      expect(Auditable.logging_enabled).to be(false)
    end
  end

  def audit_rows_for(record)
    AuditLog.where(resource_type: record.class.name, resource_id: record.id, action: "created").to_a
  end
end
