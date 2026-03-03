# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Devops
        class MaintenanceController < ApplicationController
          skip_before_action :authenticate_request
          before_action :authenticate_worker!

          # POST /api/v1/internal/devops/maintenance/reconcile_instances
          # Reconciles container instances whose Docker containers have vanished.
          def reconcile_instances
            reconciled_count = 0
            timed_out_count = 0

            # Instances stuck in pending for >15 minutes
            ::Devops::ContainerInstance.pending
              .where("created_at < ?", 15.minutes.ago)
              .find_each do |instance|
                instance.fail!("Reconciled: stuck in pending state")
                reconciled_count += 1
              end

            # Instances stuck in provisioning for >10 minutes
            ::Devops::ContainerInstance.provisioning
              .where("created_at < ?", 10.minutes.ago)
              .find_each do |instance|
                instance.fail!("Reconciled: stuck in provisioning state")
                reconciled_count += 1
              end

            # Running instances with no status updates for >30 minutes
            ::Devops::ContainerInstance.running
              .where("updated_at < ?", 30.minutes.ago)
              .find_each do |instance|
                instance.fail!("Reconciled: no status updates for 30+ minutes")
                reconciled_count += 1
              end

            # Running instances that have exceeded their timeout
            ::Devops::ContainerInstance.running
              .where.not(timeout_seconds: nil)
              .where.not(started_at: nil)
              .find_each do |instance|
                if instance.started_at + instance.timeout_seconds.seconds < Time.current
                  instance.mark_timeout!
                  timed_out_count += 1
                end
              end

            Rails.logger.info "[ContainerReconciliation] Reconciled #{reconciled_count} stale, #{timed_out_count} timed out"

            render_success(
              reconciled_count: reconciled_count,
              timed_out_count: timed_out_count
            )
          end

          # POST /api/v1/internal/devops/maintenance/cleanup_expired_ports
          # Releases port allocations that have exceeded their TTL.
          def cleanup_expired_ports
            released_count = ::Devops::PortAllocatorService.new.cleanup_expired!

            Rails.logger.info "[PortCleanup] Released #{released_count} expired port allocations"

            render_success(released_count: released_count)
          end

          # POST /api/v1/internal/devops/maintenance/archive_stale_templates
          # Archives unused templates and cleans up old image builds.
          def archive_stale_templates
            stale_days = params[:stale_days]&.to_i || 90
            build_retention_days = params[:build_retention_days]&.to_i || 30
            builds_to_keep = params[:builds_to_keep]&.to_i || 5

            archived_count = archive_unused_templates(stale_days)
            builds_cleaned = cleanup_old_builds(build_retention_days, builds_to_keep)

            Rails.logger.info "[TemplateMaintenance] Archived #{archived_count} templates, cleaned #{builds_cleaned} builds"

            render_success(
              archived_count: archived_count,
              builds_cleaned: builds_cleaned
            )
          end

          private

          def authenticate_worker!
            token = request.headers["Authorization"]&.split(" ")&.last
            return render_error("Unauthorized", status: :unauthorized) unless token

            begin
              payload = Security::JwtService.decode(token)
              worker = ::Worker.find_by(id: payload[:sub]) if payload[:type] == "worker"
            rescue StandardError
              worker = nil
            end

            unless worker&.active?
              render_error("Unauthorized", status: :unauthorized)
            end
          end

          def archive_unused_templates(stale_days)
            cutoff = stale_days.days.ago

            ::Devops::ContainerTemplate
              .where(status: "active")
              .where("last_used_at IS NULL OR last_used_at < ?", cutoff)
              .where("created_at < ?", cutoff)
              .where.not(account_id: nil) # Don't archive system templates
              .update_all(status: "archived", updated_at: Time.current)
          end

          def cleanup_old_builds(retention_days, keep_count)
            cutoff = retention_days.days.ago
            cleaned = 0

            ::Devops::ContainerTemplate.find_each do |template|
              old_builds = template.image_builds
                .where("created_at < ?", cutoff)
                .order(created_at: :desc)

              # Keep the most recent N builds per template
              builds_to_delete = old_builds.offset(keep_count)
              cleaned += builds_to_delete.delete_all
            end

            cleaned
          end
        end
      end
    end
  end
end
