# frozen_string_literal: true

module Api
  module V1
    module SupplyChain
      class LicensesController < BaseController
        before_action :set_license, only: [:show]

        # GET /api/v1/supply_chain/licenses
        def index
          @licenses = ::SupplyChain::License.all

          # Filters
          @licenses = @licenses.by_category(params[:category]) if params[:category].present?
          @licenses = @licenses.osi_approved if params[:osi_approved] == "true"
          @licenses = @licenses.copyleft if params[:copyleft] == "true"
          @licenses = @licenses.strong_copyleft if params[:strong_copyleft] == "true"
          @licenses = @licenses.network_copyleft if params[:network_copyleft] == "true"
          @licenses = @licenses.active unless params[:include_deprecated] == "true"

          # Search
          @licenses = @licenses.search(params[:q]) if params[:q].present?

          @licenses = @licenses.alphabetical
          @licenses = paginate(@licenses)

          render_success(
            licenses: @licenses.map { |l| serialize_license(l) },
            meta: pagination_meta(@licenses)
          )
        end

        # GET /api/v1/supply_chain/licenses/:id
        def show
          render_success(license: serialize_license(@license, include_details: true))
        end

        # GET /api/v1/supply_chain/licenses/categories
        def categories
          render_success(
            categories: ::SupplyChain::License::CATEGORIES.map do |cat|
              {
                id: cat,
                name: cat.humanize,
                count: ::SupplyChain::License.by_category(cat).count
              }
            end
          )
        end

        # POST /api/v1/supply_chain/licenses/check_compatibility
        def check_compatibility
          license1 = ::SupplyChain::License.find_by_spdx(params[:license1])
          license2 = ::SupplyChain::License.find_by_spdx(params[:license2])

          if license1.nil? || license2.nil?
            render_error("One or both licenses not found", status: :not_found)
            return
          end

          compatible = license1.compatible_with?(license2)

          render_success(
            license1: serialize_license(license1),
            license2: serialize_license(license2),
            compatible: compatible,
            explanation: compatibility_explanation(license1, license2, compatible)
          )
        end

        private

        def set_license
          @license = ::SupplyChain::License.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          @license = ::SupplyChain::License.find_by_spdx(params[:id])
          raise ActiveRecord::RecordNotFound unless @license
        end

        def serialize_license(license, include_details: false)
          data = {
            id: license.id,
            spdx_id: license.spdx_id,
            name: license.name,
            category: license.category,
            is_osi_approved: license.is_osi_approved,
            is_copyleft: license.is_copyleft,
            is_strong_copyleft: license.is_strong_copyleft,
            is_network_copyleft: license.is_network_copyleft,
            is_deprecated: license.is_deprecated,
            risk_level: license.risk_level,
            url: license.url
          }

          if include_details
            data[:description] = license.description
            data[:license_text] = license.license_text
            data[:requires_attribution] = license.requires_attribution?
            data[:requires_license_copy] = license.requires_license_copy?
            data[:requires_source_disclosure] = license.requires_source_disclosure?
            data[:compatibility] = license.compatibility
          end

          data
        end

        def compatibility_explanation(l1, l2, compatible)
          if compatible
            if l1.permissive? && l2.permissive?
              "Both licenses are permissive and fully compatible"
            elsif l1.public_domain? || l2.public_domain?
              "Public domain works are compatible with all licenses"
            else
              "These licenses are compatible based on their terms"
            end
          else
            if l1.copyleft? && l2.copyleft?
              "Both licenses are copyleft with incompatible terms"
            elsif l1.network_copyleft? || l2.network_copyleft?
              "Network copyleft licenses have strict requirements"
            else
              "License terms conflict - review required"
            end
          end
        end
      end
    end
  end
end
