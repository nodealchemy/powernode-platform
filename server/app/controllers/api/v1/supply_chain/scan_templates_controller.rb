# frozen_string_literal: true

module Api
  module V1
    module SupplyChain
      class ScanTemplatesController < BaseController
        before_action :set_scan_template, only: [:show, :update, :destroy, :install, :publish, :unpublish]

        # GET /api/v1/supply_chain/scan_templates
        def index
          @templates = ::SupplyChain::ScanTemplate.all

          # Filter by ownership
          case params[:scope]
          when "mine"
            @templates = @templates.where(account_id: current_account.id)
          when "marketplace"
            @templates = @templates.where(is_published: true)
          when "system"
            @templates = @templates.where(is_system: true)
          else
            # Show account's own + published + system
            @templates = @templates.where(account_id: current_account.id)
                                   .or(@templates.where(is_published: true))
                                   .or(@templates.where(is_system: true))
          end

          @templates = @templates.where(template_type: params[:type]) if params[:type].present?
          @templates = @templates.where(ecosystem: params[:ecosystem]) if params[:ecosystem].present?

          @templates = @templates.order(created_at: :desc)
          @templates = paginate(@templates)

          render_success(
            scan_templates: @templates.map { |t| serialize_template(t) },
            meta: pagination_meta(@templates)
          )
        end

        # GET /api/v1/supply_chain/scan_templates/:id
        def show
          render_success(scan_template: serialize_template(@template, include_details: true))
        end

        # POST /api/v1/supply_chain/scan_templates
        def create
          @template = current_account.supply_chain_scan_templates.build(template_params)
          @template.created_by = current_user

          if @template.save
            render_success(scan_template: serialize_template(@template), status: :created)
          else
            render_error(@template.errors.full_messages.join(", "), status: :unprocessable_entity)
          end
        end

        # PATCH/PUT /api/v1/supply_chain/scan_templates/:id
        def update
          unless can_modify?(@template)
            render_error("Cannot modify this template", status: :forbidden)
            return
          end

          if @template.update(template_params)
            render_success(scan_template: serialize_template(@template))
          else
            render_error(@template.errors.full_messages.join(", "), status: :unprocessable_entity)
          end
        end

        # DELETE /api/v1/supply_chain/scan_templates/:id
        def destroy
          unless can_modify?(@template)
            render_error("Cannot delete this template", status: :forbidden)
            return
          end

          @template.destroy
          render_success(message: "Scan template deleted")
        end

        # POST /api/v1/supply_chain/scan_templates/:id/install
        def install
          instance = current_account.supply_chain_scan_instances.build(
            scan_template: @template,
            name: params[:name] || @template.name,
            configuration: params[:configuration] || @template.default_configuration,
            created_by: current_user
          )

          if instance.save
            render_success(
              scan_instance: serialize_instance(instance),
              message: "Template installed successfully"
            )
          else
            render_error(instance.errors.full_messages.join(", "), status: :unprocessable_entity)
          end
        end

        # POST /api/v1/supply_chain/scan_templates/:id/publish
        def publish
          unless can_modify?(@template)
            render_error("Cannot publish this template", status: :forbidden)
            return
          end

          @template.publish!

          render_success(
            scan_template: serialize_template(@template),
            message: "Template published to marketplace"
          )
        rescue StandardError => e
          render_error("Failed to publish: #{e.message}", status: :unprocessable_entity)
        end

        # POST /api/v1/supply_chain/scan_templates/:id/unpublish
        def unpublish
          unless can_modify?(@template)
            render_error("Cannot unpublish this template", status: :forbidden)
            return
          end

          @template.unpublish!

          render_success(
            scan_template: serialize_template(@template),
            message: "Template removed from marketplace"
          )
        rescue StandardError => e
          render_error("Failed to unpublish: #{e.message}", status: :unprocessable_entity)
        end

        private

        def set_scan_template
          @template = ::SupplyChain::ScanTemplate.find(params[:id])
        end

        def can_modify?(template)
          template.account_id == current_account.id && !template.is_system
        end

        def template_params
          params.require(:scan_template).permit(
            :name, :description, :template_type, :ecosystem, :version,
            :scanner_type, :scanner_version,
            default_configuration: {}, scan_rules: {}, metadata: {}
          )
        end

        def serialize_template(template, include_details: false)
          data = {
            id: template.id,
            name: template.name,
            description: template.description,
            template_type: template.template_type,
            ecosystem: template.ecosystem,
            version: template.version,
            scanner_type: template.scanner_type,
            is_system: template.is_system,
            is_published: template.is_published,
            install_count: template.install_count,
            created_at: template.created_at
          }

          if include_details
            data[:default_configuration] = template.default_configuration
            data[:scan_rules] = template.scan_rules
            data[:scanner_version] = template.scanner_version
            data[:account_id] = template.account_id
            data[:metadata] = template.metadata
          end

          data
        end

        def serialize_instance(instance)
          {
            id: instance.id,
            name: instance.name,
            scan_template_id: instance.scan_template_id,
            configuration: instance.configuration,
            created_at: instance.created_at
          }
        end
      end
    end
  end
end
