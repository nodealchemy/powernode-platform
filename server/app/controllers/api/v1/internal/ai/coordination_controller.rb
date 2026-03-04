# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Ai
        class CoordinationController < InternalBaseController
          # POST /api/v1/internal/ai/coordination/decay_signals
          # Called by AiStigmergicSignalDecayJob — decay all signals across accounts
          def decay_signals
            total_decayed = 0

            Account.active.find_each do |account|
              next if account.ai_suspended?

              service = ::Ai::Coordination::StigmergicSignalService.new(account: account)
              total_decayed += service.decay_all!
            rescue StandardError => e
              Rails.logger.error "[CoordinationDecay] Signal decay failed for account #{account.id}: #{e.message}"
            end

            render_success(decayed: total_decayed)
          end

          # POST /api/v1/internal/ai/coordination/measure_all_fields
          # Called by AiPressureFieldMeasurementJob — re-measure all pressure fields
          def measure_all_fields
            total_measured = 0

            Account.active.find_each do |account|
              next if account.ai_suspended?

              service = ::Ai::Coordination::PressureFieldService.new(account: account)

              ::Ai::PressureField.for_account(account.id).find_each do |field|
                service.measure!(
                  artifact_ref: field.artifact_ref,
                  artifact_type: field.artifact_type,
                  field_type: field.field_type,
                  team_id: field.ai_agent_team_id
                )
                total_measured += 1
              rescue StandardError => e
                Rails.logger.error "[CoordinationMeasure] Field #{field.id} measurement failed: #{e.message}"
              end
            rescue StandardError => e
              Rails.logger.error "[CoordinationMeasure] Failed for account #{account.id}: #{e.message}"
            end

            render_success(measured: total_measured)
          end

          # POST /api/v1/internal/ai/coordination/decay_fields
          # Called by AiPressureFieldDecayJob — decay all pressure fields across accounts
          def decay_fields
            total_decayed = 0

            Account.active.find_each do |account|
              next if account.ai_suspended?

              service = ::Ai::Coordination::PressureFieldService.new(account: account)
              total_decayed += service.decay_all!
            rescue StandardError => e
              Rails.logger.error "[CoordinationDecay] Field decay failed for account #{account.id}: #{e.message}"
            end

            render_success(decayed: total_decayed)
          end
        end
      end
    end
  end
end
