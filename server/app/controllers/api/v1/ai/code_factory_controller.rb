# frozen_string_literal: true

module Api
  module V1
    module Ai
      class CodeFactoryController < ApplicationController
        before_action :authorize_read!, only: [:index, :show, :review_states, :review_state_show,
                                               :show_evidence, :harness_gaps]
        before_action :authorize_manage!, only: [:create, :update, :activate, :preflight,
                                                  :remediate, :resolve_threads, :submit_evidence,
                                                  :create_harness_gap, :add_test_case, :close_harness_gap]

        # GET /api/v1/ai/code_factory/contracts
        def index
          contracts = current_account.ai_code_factory_risk_contracts
            .includes(:repository, :created_by)
            .order(created_at: :desc)

          contracts = contracts.where(status: params[:status]) if params[:status].present?
          contracts = contracts.where(repository_id: params[:repository_id]) if params[:repository_id].present?

          render_success(contracts: contracts.as_json(include_associations))
        end

        # POST /api/v1/ai/code_factory/contracts
        def create
          contract = current_account.ai_code_factory_risk_contracts.new(contract_params)
          contract.created_by = current_user

          if contract.save
            render_success(contract: contract.as_json(include_associations), status: :created)
          else
            render_error(contract.errors.full_messages.join(", "), :unprocessable_content)
          end
        end

        # GET /api/v1/ai/code_factory/contracts/:id
        def show
          contract = find_contract!
          render_success(contract: contract.as_json(include_associations))
        end

        # PUT /api/v1/ai/code_factory/contracts/:id
        def update
          contract = find_contract!

          if contract.update(contract_params)
            render_success(contract: contract.as_json(include_associations))
          else
            render_error(contract.errors.full_messages.join(", "), :unprocessable_content)
          end
        end

        # POST /api/v1/ai/code_factory/contracts/:id/activate
        def activate
          contract = find_contract!
          contract.activate!
          render_success(contract: contract.as_json(include_associations))
        rescue StandardError => e
          render_error(e.message, :unprocessable_content)
        end

        # POST /api/v1/ai/code_factory/preflight
        def preflight
          service = ::Ai::CodeFactory::PreflightGateService.new(
            account: current_account,
            risk_contract: params[:contract_id].present? ? find_contract_by_id(params[:contract_id]) : nil
          )

          result = service.evaluate(
            pr_number: params[:pr_number].to_i,
            head_sha: params[:head_sha],
            changed_files: params[:changed_files] || [],
            repository_id: params[:repository_id]
          )

          render_success(preflight: {
            passed: result[:passed],
            risk_tier: result[:risk_tier],
            required_checks: result[:required_checks],
            evidence_required: result[:evidence_required],
            review_state_id: result[:review_state]&.id,
            reason: result[:reason]
          })
        rescue ::Ai::CodeFactory::PreflightGateService::GateError => e
          render_error(e.message, :unprocessable_content)
        end

        # GET /api/v1/ai/code_factory/review_states
        def review_states
          states = current_account.ai_code_factory_review_states
            .includes(:risk_contract, :repository)
            .order(created_at: :desc)

          states = states.where(status: params[:status]) if params[:status].present?
          states = states.where(repository_id: params[:repository_id]) if params[:repository_id].present?

          render_success(review_states: states.as_json(include: { risk_contract: { only: [:id, :name] } }))
        end

        # GET /api/v1/ai/code_factory/review_states/:id
        def review_state_show
          state = find_review_state!
          render_success(review_state: state.as_json(
            include: { risk_contract: { only: [:id, :name] }, evidence_manifests: {} }
          ))
        end

        # POST /api/v1/ai/code_factory/review_states/:id/remediate
        def remediate
          state = find_review_state!
          service = ::Ai::CodeFactory::RemediationLoopService.new(
            account: current_account, review_state: state
          )

          result = service.remediate(findings: params[:findings] || [])
          render_success(remediation: result)
        rescue ::Ai::CodeFactory::RemediationLoopService::RemediationError => e
          render_error(e.message, :unprocessable_content)
        end

        # POST /api/v1/ai/code_factory/review_states/:id/resolve_threads
        def resolve_threads
          state = find_review_state!
          service = ::Ai::CodeFactory::ThreadResolverService.new(account: current_account)
          result = service.resolve_bot_threads(review_state: state)
          render_success(thread_resolution: result)
        rescue ::Ai::CodeFactory::ThreadResolverService::ResolverError => e
          render_error(e.message, :unprocessable_content)
        end

        # POST /api/v1/ai/code_factory/evidence
        def submit_evidence
          state = find_review_state_by_id!(params[:review_state_id])
          service = ::Ai::CodeFactory::EvidenceValidatorService.new(account: current_account)

          manifest = service.create_manifest(
            review_state: state,
            manifest_type: params[:manifest_type],
            artifacts: params[:artifacts] || [],
            assertions: params[:assertions] || []
          )

          validation = service.validate_evidence(review_state: state, manifest: manifest)
          render_success(evidence: { manifest_id: manifest.id, validation: validation })
        rescue StandardError => e
          render_error(e.message, :unprocessable_content)
        end

        # GET /api/v1/ai/code_factory/evidence/:id
        def show_evidence
          manifest = ::Ai::CodeFactory::EvidenceManifest.find_by!(id: params[:id], account: current_account)
          render_success(evidence: manifest)
        rescue ActiveRecord::RecordNotFound
          render_error("Evidence manifest not found", :not_found)
        end

        # GET /api/v1/ai/code_factory/harness_gaps
        def harness_gaps
          gaps = current_account.ai_code_factory_harness_gaps.order(created_at: :desc)
          gaps = gaps.where(status: params[:status]) if params[:status].present?
          gaps = gaps.by_severity(params[:severity]) if params[:severity].present?

          service = ::Ai::CodeFactory::HarnessGapService.new(account: current_account)

          render_success(harness_gaps: gaps, metrics: service.metrics, sla: service.check_sla_compliance)
        end

        # POST /api/v1/ai/code_factory/harness_gaps
        def create_harness_gap
          service = ::Ai::CodeFactory::HarnessGapService.new(account: current_account)
          gap = service.create_from_incident(
            incident_id: params[:incident_id],
            description: params[:description],
            severity: params[:severity] || "medium",
            incident_source: params[:incident_source] || "manual",
            risk_contract: params[:risk_contract_id].present? ? find_contract_by_id(params[:risk_contract_id]) : nil,
            sla_hours: (params[:sla_hours] || 72).to_i
          )
          render_success(harness_gap: gap, status: :created)
        rescue ::Ai::CodeFactory::HarnessGapService::GapError => e
          render_error(e.message, :unprocessable_content)
        end

        # PUT /api/v1/ai/code_factory/harness_gaps/:id/add_case
        def add_test_case
          gap = find_harness_gap!
          service = ::Ai::CodeFactory::HarnessGapService.new(account: current_account)
          service.add_test_case(harness_gap: gap, test_reference: params[:test_reference])
          render_success(harness_gap: gap.reload)
        end

        # PUT /api/v1/ai/code_factory/harness_gaps/:id/close
        def close_harness_gap
          gap = find_harness_gap!
          gap.close!(params[:resolution_notes])
          render_success(harness_gap: gap)
        end

        # POST /api/v1/ai/code_factory/webhook
        def webhook
          service = ::Ai::CodeFactory::OrchestratorService.new(account: current_account)
          result = service.process_pr_event(
            event_type: params[:event_type],
            pr_number: params[:pr_number].to_i,
            head_sha: params[:head_sha],
            changed_files: params[:changed_files] || [],
            repository: params[:repository_id].present? ? find_repository(params[:repository_id]) : nil
          )
          render_success(result: result)
        rescue ::Ai::CodeFactory::OrchestratorService::OrchestrationError => e
          render_error(e.message, :unprocessable_content)
        end

        private

        def authorize_read!
          unless has_permission?("ai.code_factory.read")
            render_error("Forbidden", :forbidden)
          end
        end

        def authorize_manage!
          unless has_permission?("ai.code_factory.manage")
            render_error("Forbidden", :forbidden)
          end
        end

        def find_contract!
          current_account.ai_code_factory_risk_contracts.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Risk contract not found", :not_found)
        end

        def find_contract_by_id(id)
          current_account.ai_code_factory_risk_contracts.find(id)
        end

        def find_review_state!
          current_account.ai_code_factory_review_states.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Review state not found", :not_found)
        end

        def find_review_state_by_id!(id)
          current_account.ai_code_factory_review_states.find(id)
        end

        def find_harness_gap!
          current_account.ai_code_factory_harness_gaps.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Harness gap not found", :not_found)
        end

        def find_repository(id)
          current_account.git_repositories.find_by(id: id)
        end

        def contract_params
          params.permit(:name, :repository_id, :status,
                        risk_tiers: [:tier, :evidence_required, :min_reviewers, patterns: [], required_checks: []],
                        merge_policy: {}, docs_drift_rules: {},
                        evidence_requirements: {}, remediation_config: {},
                        preflight_config: {}, metadata: {})
        end

        def include_associations
          { include: { repository: { only: [:id, :name, :full_name] },
                       created_by: { only: [:id, :name, :email] } } }
        end
      end
    end
  end
end
