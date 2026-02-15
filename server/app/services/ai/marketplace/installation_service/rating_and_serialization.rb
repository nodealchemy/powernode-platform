# frozen_string_literal: true

module Ai
  module Marketplace
    class InstallationService
      module RatingAndSerialization
        extend ActiveSupport::Concern

        # Rate a template
        # @param template_id [String] Template to rate
        # @param rating [Integer] Rating value (1-5)
        # @param feedback [Hash] Optional feedback data
        # @return [Hash] Rating result
        def rate_template(template_id:, rating:, feedback: {})
          template = ::Ai::WorkflowTemplate.find(template_id)

          unless rating.between?(1, 5)
            return error_result("Rating must be between 1 and 5")
          end

          # Check if user has installed this template
          subscription = account.workflow_template_subscriptions
                                .find_by(subscribable: template)

          unless subscription
            return error_result("You must install a template before rating it")
          end

          # Check if already rated
          existing_rating = subscription.metadata&.dig("rating")
          if existing_rating && !feedback[:allow_update]
            return error_result("You have already rated this template")
          end

          ActiveRecord::Base.transaction do
            template.with_lock do
              template.reload
              # Update running average
              if existing_rating
                # Recalculate removing old rating
                current_total = template.rating * template.rating_count
                new_total = current_total - existing_rating + rating
                new_average = new_total / template.rating_count.to_f
                template.update!(rating: new_average.round(2))
              else
                # Add new rating
                current_total = template.rating * template.rating_count
                new_total = current_total + rating
                new_count = template.rating_count + 1
                new_average = new_total / new_count.to_f
                template.update!(
                  rating: new_average.round(2),
                  rating_count: new_count
                )
              end
            end

            # Store rating in subscription metadata
            subscription.update!(
              metadata: subscription.metadata.merge(
                "rating" => rating,
                "rating_feedback" => feedback,
                "rated_at" => Time.current.iso8601
              )
            )

            {
              success: true,
              template_id: template.id,
              rating: rating,
              new_average: template.rating,
              total_ratings: template.rating_count,
              message: existing_rating ? "Rating updated successfully" : "Template rated successfully"
            }
          end
        rescue ActiveRecord::RecordNotFound
          error_result("Template not found")
        end

        private

        def serialize_installation(subscription)
          template = subscription.subscribable
          workflow_id = subscription.metadata&.dig("workflow_id")

          {
            id: subscription.id,
            template_id: template&.id,
            template_name: template&.name,
            template_category: template&.category,
            installed_version: subscription.metadata&.dig("template_version"),
            installed_at: subscription.subscribed_at&.iso8601 || subscription.created_at.iso8601,
            workflow_id: workflow_id,
            has_update: template && subscription.metadata&.dig("template_version") != template.version
          }
        end

        def serialize_installation_detail(subscription)
          template = subscription.subscribable
          workflow_id = subscription.metadata&.dig("workflow_id")
          workflow = workflow_id ? account.ai_workflows.find_by(id: workflow_id) : nil

          serialize_installation(subscription).merge(
            template: template ? {
              id: template.id,
              name: template.name,
              description: template.description,
              category: template.category,
              difficulty_level: template.difficulty_level,
              version: template.version,
              rating: template.rating,
              rating_count: template.rating_count
            } : nil,
            workflow: workflow ? {
              id: workflow.id,
              name: workflow.name,
              description: workflow.description,
              status: workflow.status,
              created_at: workflow.created_at.iso8601
            } : nil,
            custom_configuration: subscription.configuration,
            user_rating: subscription.metadata&.dig("rating"),
            installation_notes: subscription.subscription_notes
          )
        end
      end
    end
  end
end
