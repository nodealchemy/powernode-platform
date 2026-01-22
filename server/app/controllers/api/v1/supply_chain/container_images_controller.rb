# frozen_string_literal: true

module Api
  module V1
    module SupplyChain
      class ContainerImagesController < BaseController
        before_action :require_read_permission, only: [:index, :show, :vulnerabilities, :sbom, :statistics]
        before_action :require_write_permission, only: [:create, :update, :destroy, :scan, :evaluate_policies, :quarantine, :verify]
        before_action :set_container_image, only: [:show, :update, :destroy, :scan, :evaluate_policies, :vulnerabilities, :sbom, :quarantine, :verify]

        # GET /api/v1/supply_chain/container_images
        def index
          images = current_account.supply_chain_container_images
                                  .order(created_at: :desc)

          images = images.where(status: params[:status]) if params[:status].present?
          images = images.where(registry: params[:registry]) if params[:registry].present?
          images = images.where(is_deployed: true) if params[:deployed] == "true"

          images = images.page(params[:page]).per(params[:per_page] || 20)

          render_success({
            container_images: images.map { |i| serialize_container_image(i) },
            meta: {
              total: images.total_count,
              page: images.current_page,
              per_page: images.limit_value
            }
          })
        rescue StandardError => e
          Rails.logger.error "[ContainerImagesController] List failed: #{e.message}"
          render_error("Failed to list container images", status: :internal_server_error)
        end

        # GET /api/v1/supply_chain/container_images/:id
        def show
          render_success({
            container_image: serialize_container_image_detail(@container_image)
          })

          log_audit_event("supply_chain.container_images.read", @container_image)
        end

        # POST /api/v1/supply_chain/container_images
        def create
          image = current_account.supply_chain_container_images.new(container_image_params)

          if image.save
            render_success({
              container_image: serialize_container_image(image),
              message: "Container image created successfully"
            }, status: :created)

            log_audit_event("supply_chain.container_images.create", image)
          else
            render_validation_error(image.errors)
          end
        end

        # PATCH/PUT /api/v1/supply_chain/container_images/:id
        def update
          if @container_image.update(container_image_params)
            render_success({
              container_image: serialize_container_image(@container_image),
              message: "Container image updated successfully"
            })

            log_audit_event("supply_chain.container_images.update", @container_image)
          else
            render_validation_error(@container_image.errors)
          end
        end

        # DELETE /api/v1/supply_chain/container_images/:id
        def destroy
          @container_image.destroy!

          render_success({ message: "Container image deleted successfully" })

          log_audit_event("supply_chain.container_images.delete", @container_image)
        rescue StandardError => e
          render_error("Failed to delete container image", status: :internal_server_error)
        end

        # POST /api/v1/supply_chain/container_images/:id/scan
        def scan
          scan_result = ::SupplyChain::ContainerScanService.new(
            account: current_account,
            image: @container_image,
            options: {
              scanner: params[:scanner] || "trivy",
              user: current_user
            }
          ).scan!

          render_success({
            container_image_id: @container_image.id,
            scan_id: scan_result.id,
            vulnerability_counts: {
              critical: scan_result.critical_count,
              high: scan_result.high_count,
              medium: scan_result.medium_count,
              low: scan_result.low_count,
              total: scan_result.total_vulnerabilities
            },
            message: "Container scan completed"
          })

          log_audit_event("supply_chain.container_images.scan", @container_image)
        rescue StandardError => e
          Rails.logger.error "[ContainerImagesController] Scan failed: #{e.message}"
          render_error("Scan failed: #{e.message}", status: :unprocessable_content)
        end

        # POST /api/v1/supply_chain/container_images/:id/evaluate_policies
        def evaluate_policies
          result = ::SupplyChain::ContainerScanService.new(
            account: current_account,
            image: @container_image
          ).evaluate_policies

          render_success({
            container_image_id: @container_image.id,
            passed: result[:passed],
            policy_results: result[:policy_results],
            message: result[:passed] ? "All policies passed" : "Policy violations detected"
          })

          log_audit_event("supply_chain.container_images.evaluate_policies", @container_image)
        rescue StandardError => e
          render_error("Policy evaluation failed: #{e.message}", status: :unprocessable_content)
        end

        # GET /api/v1/supply_chain/container_images/:id/vulnerabilities
        def vulnerabilities
          scans = @container_image.vulnerability_scans.order(created_at: :desc)
          latest_scan = scans.first

          if latest_scan.nil?
            render_success({
              vulnerabilities: [],
              message: "No scans available. Run a scan first."
            })
            return
          end

          render_success({
            scan_id: latest_scan.id,
            scanned_at: latest_scan.created_at,
            vulnerability_counts: {
              critical: latest_scan.critical_count,
              high: latest_scan.high_count,
              medium: latest_scan.medium_count,
              low: latest_scan.low_count
            },
            vulnerabilities: latest_scan.vulnerabilities || []
          })
        end

        # GET /api/v1/supply_chain/container_images/:id/sbom
        def sbom
          if @container_image.sbom.present?
            render_success({
              sbom: @container_image.sbom
            })
          else
            render_success({
              sbom: nil,
              message: "No SBOM available for this image"
            })
          end
        end

        # POST /api/v1/supply_chain/container_images/:id/quarantine
        def quarantine
          @container_image.quarantine!(params[:reason])

          render_success({
            container_image: serialize_container_image(@container_image),
            message: "Container image quarantined"
          })

          log_audit_event("supply_chain.container_images.quarantine", @container_image)
        rescue StandardError => e
          render_error("Quarantine failed: #{e.message}", status: :unprocessable_content)
        end

        # POST /api/v1/supply_chain/container_images/:id/verify
        def verify
          @container_image.verify!

          render_success({
            container_image: serialize_container_image(@container_image),
            message: "Container image verified"
          })

          log_audit_event("supply_chain.container_images.verify", @container_image)
        rescue StandardError => e
          render_error("Verification failed: #{e.message}", status: :unprocessable_content)
        end

        # GET /api/v1/supply_chain/container_images/statistics
        def statistics
          images = current_account.supply_chain_container_images

          render_success({
            total: images.count,
            by_status: images.group(:status).count,
            by_registry: images.group(:registry).count,
            deployed_count: images.where(is_deployed: true).count,
            with_critical_vulns: images.where("critical_vuln_count > 0").count,
            vulnerability_totals: {
              critical: images.sum(:critical_vuln_count),
              high: images.sum(:high_vuln_count),
              medium: images.sum(:medium_vuln_count),
              low: images.sum(:low_vuln_count)
            }
          })
        end

        private

        def set_container_image
          @container_image = current_account.supply_chain_container_images.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Container image not found", status: :not_found)
        end

        def container_image_params
          params.require(:container_image).permit(
            :registry,
            :repository,
            :tag,
            :digest,
            :is_deployed,
            deployment_contexts: []
          )
        end

        def serialize_container_image_detail(image)
          serialize_container_image(image).merge({
            layers: image.layers,
            base_image_id: image.base_image_id,
            attestation_id: image.attestation_id,
            sbom_available: image.sbom.present?,
            last_scan: image.vulnerability_scans.order(created_at: :desc).first&.then { |s|
              {
                id: s.id,
                scanner: s.scanner_name,
                scanned_at: s.created_at,
                total_vulnerabilities: s.total_vulnerabilities
              }
            }
          })
        end
      end
    end
  end
end
