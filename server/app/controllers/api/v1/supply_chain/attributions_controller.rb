# frozen_string_literal: true

require "csv"

module Api
  module V1
    module SupplyChain
      class AttributionsController < BaseController
        before_action :require_read_permission, only: [ :index, :show, :export ]
        before_action :require_write_permission, only: [ :create, :update, :destroy, :generate_notice_file ]
        before_action :set_attribution, only: [ :show, :update, :destroy ]

        # GET /api/v1/supply_chain/attributions
        def index
          @attributions = current_account.supply_chain_attributions
                                         .includes(:sbom_component, :license)
                                         .order(created_at: :desc)

          @attributions = @attributions.where(requires_attribution: true) if params[:type] == "requires_attribution"
          @attributions = @attributions.where(license_id: params[:license_id]) if params[:license_id].present?

          if params[:sbom_component_id].present?
            @attributions = @attributions.where(sbom_component_id: params[:sbom_component_id])
          end

          @attributions = paginate(@attributions)

          render_success(
            { attributions: @attributions.map { |a| serialize_attribution(a) } },
            meta: pagination_meta
          )
        end

        # GET /api/v1/supply_chain/attributions/:id
        def show
          render_success({ attribution: serialize_attribution(@attribution, include_details: true) })
        end

        # POST /api/v1/supply_chain/attributions
        def create
          @attribution = current_account.supply_chain_attributions.build(attribution_params)

          if @attribution.save
            render_success({ attribution: serialize_attribution(@attribution) }, status: :created)
          else
            render_error(@attribution.errors.full_messages.join(", "), status: :unprocessable_content)
          end
        end

        # PATCH/PUT /api/v1/supply_chain/attributions/:id
        def update
          if @attribution.update(attribution_params)
            render_success({ attribution: serialize_attribution(@attribution) })
          else
            render_error(@attribution.errors.full_messages.join(", "), status: :unprocessable_content)
          end
        end

        # DELETE /api/v1/supply_chain/attributions/:id
        def destroy
          @attribution.destroy
          render_success(message: "Attribution deleted")
        end

        # POST /api/v1/supply_chain/attributions/generate_notice_file
        def generate_notice_file
          sbom_id = params[:sbom_id]
          format = params[:format] || "text"

          if sbom_id.blank?
            return render_error("sbom_id is required", status: :unprocessable_content)
          end

          sbom = current_account.supply_chain_sboms.find(sbom_id)

          result = ::SupplyChain::AttributionService.generate_notice_file(
            sbom: sbom,
            format: format,
            include_full_license_text: params[:include_full_text] == "true",
            user: current_user
          )

          if result[:success]
            render_success(
              {
                notice_file: {
                  content: result[:content],
                  format: result[:format],
                  component_count: result[:component_count],
                  license_count: result[:license_count]
                }
              },
              message: "Notice file generated"
            )
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        rescue ActiveRecord::RecordNotFound
          render_error("SBOM not found", status: :not_found)
        end

        # GET /api/v1/supply_chain/attributions/export
        def export
          format = params[:export_format] || "json"

          attributions = current_account.supply_chain_attributions
                                        .includes(:sbom_component, :license)

          if params[:sbom_component_id].present?
            attributions = attributions.where(sbom_component_id: params[:sbom_component_id])
          end

          case format
          when "json"
            render_success({
              attributions: attributions.map { |a| serialize_attribution(a, include_details: true) },
              exported_at: Time.current.iso8601,
              total_count: attributions.count
            })
          when "csv"
            csv_content = generate_csv(attributions)
            send_data csv_content, filename: "attributions-#{Date.current}.csv", type: "text/csv"
          when "spdx"
            spdx_content = generate_spdx(attributions)
            render_success(spdx_content)
          else
            render_error("Unsupported format: #{format}", status: :unprocessable_content)
          end
        end

        private

        def set_attribution
          @attribution = current_account.supply_chain_attributions.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Attribution not found", status: :not_found)
        end

        def attribution_params
          params.require(:attribution).permit(
            :sbom_component_id, :license_id,
            :package_name, :package_version,
            :copyright_holder, :copyright_year,
            :license_text, :notice_text, :attribution_url,
            :requires_attribution, :requires_license_copy, :requires_source_disclosure,
            metadata: {}
          )
        end

        def serialize_attribution(attribution, include_details: false)
          data = {
            id: attribution.id,
            package_name: attribution.package_name,
            package_version: attribution.package_version,
            sbom_component: attribution.sbom_component ? {
              id: attribution.sbom_component.id,
              name: attribution.sbom_component.respond_to?(:full_name) ? attribution.sbom_component.full_name : attribution.sbom_component.name,
              version: attribution.sbom_component.version
            } : nil,
            license: attribution.license ? {
              id: attribution.license.id,
              spdx_id: attribution.license.spdx_id,
              name: attribution.license.name
            } : nil,
            copyright_holder: attribution.copyright_holder,
            copyright_year: attribution.copyright_year,
            requires_attribution: attribution.requires_attribution,
            requires_license_copy: attribution.requires_license_copy,
            requires_source_disclosure: attribution.requires_source_disclosure,
            created_at: attribution.created_at
          }

          if include_details
            data[:license_text] = attribution.license_text
            data[:notice_text] = attribution.notice_text
            data[:attribution_url] = attribution.attribution_url
            data[:metadata] = attribution.metadata
          end

          data
        end

        def generate_csv(attributions)
          CSV.generate(headers: true) do |csv|
            csv << [ "Package", "Version", "License", "Copyright Holder", "Copyright Year" ]
            attributions.each do |attr|
              csv << [
                attr.package_name,
                attr.package_version,
                attr.license&.spdx_id,
                attr.copyright_holder,
                attr.copyright_year
              ]
            end
          end
        end

        def generate_spdx(attributions)
          # Generate SPDX-compatible attribution document
          {
            spdxVersion: "SPDX-2.3",
            dataLicense: "CC0-1.0",
            SPDXID: "SPDXRef-DOCUMENT",
            name: "Attribution Export",
            documentNamespace: "https://powernode.io/spdx/#{SecureRandom.uuid}",
            creationInfo: {
              created: Time.current.iso8601,
              creators: [ "Tool: Powernode" ]
            },
            packages: attributions.map do |attr|
              {
                SPDXID: "SPDXRef-Package-#{attr.id}",
                name: attr.package_name || "Unknown",
                versionInfo: attr.package_version || "Unknown",
                licenseConcluded: attr.license&.spdx_id || "NOASSERTION",
                copyrightText: attr.copyright_holder || "NOASSERTION"
              }
            end
          }
        end
      end
    end
  end
end
