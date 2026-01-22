# frozen_string_literal: true

module Api
  module V1
    module SupplyChain
      class DashboardController < BaseController
        before_action :require_read_permission

        # GET /api/v1/supply_chain/dashboard
        def index
          render_success({
            overview: build_overview,
            recent_activity: build_recent_activity,
            alerts: build_alerts,
            quick_stats: build_quick_stats
          })
        end

        # GET /api/v1/supply_chain/analytics
        def analytics
          render_success({
            vulnerability_trends: build_vulnerability_trends,
            sbom_metrics: build_sbom_metrics,
            container_metrics: build_container_metrics,
            vendor_risk_metrics: build_vendor_risk_metrics,
            compliance_metrics: build_compliance_metrics
          })
        end

        # GET /api/v1/supply_chain/compliance_summary
        def compliance_summary
          render_success({
            overall_status: calculate_overall_compliance_status,
            ntia_compliance: build_ntia_compliance,
            slsa_compliance: build_slsa_compliance,
            license_compliance: build_license_compliance,
            vendor_compliance: build_vendor_compliance,
            recommendations: build_compliance_recommendations
          })
        end

        private

        def build_overview
          {
            sboms: {
              total: current_account.supply_chain_sboms.count,
              with_vulnerabilities: current_account.supply_chain_sboms.where("vulnerability_count > 0").count,
              ntia_compliant: current_account.supply_chain_sboms.where(ntia_minimum_compliant: true).count
            },
            vulnerabilities: {
              total: current_account.supply_chain_sbom_vulnerabilities.count,
              critical: current_account.supply_chain_sbom_vulnerabilities.where(severity: "critical").count,
              high: current_account.supply_chain_sbom_vulnerabilities.where(severity: "high").count,
              open: current_account.supply_chain_sbom_vulnerabilities.where(remediation_status: "open").count
            },
            attestations: {
              total: current_account.supply_chain_attestations.count,
              signed: current_account.supply_chain_attestations.where.not(signature: nil).count,
              verified: current_account.supply_chain_attestations.where(verification_status: "verified").count
            },
            container_images: {
              total: current_account.supply_chain_container_images.count,
              verified: current_account.supply_chain_container_images.where(status: "verified").count,
              quarantined: current_account.supply_chain_container_images.where(status: "quarantined").count
            },
            vendors: {
              total: current_account.supply_chain_vendors.count,
              active: current_account.supply_chain_vendors.where(status: "active").count,
              high_risk: current_account.supply_chain_vendors.where(risk_tier: ["critical", "high"]).count
            }
          }
        end

        def build_recent_activity
          activities = []

          # Recent SBOMs
          current_account.supply_chain_sboms.order(created_at: :desc).limit(5).each do |sbom|
            activities << {
              type: "sbom_created",
              title: "SBOM generated: #{sbom.name}",
              timestamp: sbom.created_at,
              details: {
                id: sbom.id,
                components: sbom.component_count,
                vulnerabilities: sbom.vulnerability_count
              }
            }
          end

          # Recent scans
          current_account.supply_chain_vulnerability_scans.order(created_at: :desc).limit(5).each do |scan|
            activities << {
              type: "scan_completed",
              title: "Container scan completed",
              timestamp: scan.created_at,
              details: {
                id: scan.id,
                vulnerabilities: scan.total_vulnerabilities
              }
            }
          end

          # Recent attestations
          current_account.supply_chain_attestations.order(created_at: :desc).limit(5).each do |att|
            activities << {
              type: "attestation_created",
              title: "Attestation created: #{att.subject_name}",
              timestamp: att.created_at,
              details: {
                id: att.id,
                slsa_level: att.slsa_level,
                signed: att.signed?
              }
            }
          end

          activities.sort_by { |a| a[:timestamp] }.reverse.first(10)
        end

        def build_alerts
          alerts = []

          # Critical vulnerabilities
          critical_count = current_account.supply_chain_sbom_vulnerabilities
                                          .where(severity: "critical", remediation_status: "open")
                                          .count
          if critical_count > 0
            alerts << {
              severity: "critical",
              type: "vulnerability",
              message: "#{critical_count} critical vulnerabilities require immediate attention",
              action_url: "/supply-chain/vulnerabilities?severity=critical&status=open"
            }
          end

          # Expiring certifications
          expiring_vendors = current_account.supply_chain_vendors
                                            .where(status: "active")
                                            .select { |v| v.certifications&.any? { |c| c["expires_at"].present? && Time.parse(c["expires_at"]) < 30.days.from_now } }
          if expiring_vendors.any?
            alerts << {
              severity: "warning",
              type: "vendor",
              message: "#{expiring_vendors.count} vendors have expiring certifications",
              action_url: "/supply-chain/vendors?expiring_certs=true"
            }
          end

          # Assessments overdue
          overdue_vendors = current_account.supply_chain_vendors.where(status: "active").select(&:needs_assessment?)
          if overdue_vendors.any?
            alerts << {
              severity: "warning",
              type: "vendor",
              message: "#{overdue_vendors.count} vendors require risk assessment",
              action_url: "/supply-chain/vendors?assessment_due=true"
            }
          end

          # Quarantined images
          quarantined = current_account.supply_chain_container_images.where(status: "quarantined").count
          if quarantined > 0
            alerts << {
              severity: "high",
              type: "container",
              message: "#{quarantined} container images are quarantined",
              action_url: "/supply-chain/containers?status=quarantined"
            }
          end

          # License violations
          violations = current_account.supply_chain_license_violations.where(status: "open").count
          if violations > 0
            alerts << {
              severity: "warning",
              type: "license",
              message: "#{violations} license violations require review",
              action_url: "/supply-chain/licenses/violations"
            }
          end

          alerts
        end

        def build_quick_stats
          {
            sboms_this_month: current_account.supply_chain_sboms.where("created_at > ?", 30.days.ago).count,
            scans_this_month: current_account.supply_chain_vulnerability_scans.where("created_at > ?", 30.days.ago).count,
            attestations_this_month: current_account.supply_chain_attestations.where("created_at > ?", 30.days.ago).count,
            average_risk_score: current_account.supply_chain_sboms.average(:risk_score)&.round(2)
          }
        end

        def build_vulnerability_trends
          # Group vulnerabilities by week
          current_account.supply_chain_sbom_vulnerabilities
                         .where("supply_chain_sbom_vulnerabilities.created_at > ?", 90.days.ago)
                         .group("date_trunc('week', supply_chain_sbom_vulnerabilities.created_at)")
                         .group(:severity)
                         .count
        end

        def build_sbom_metrics
          sboms = current_account.supply_chain_sboms

          {
            total: sboms.count,
            by_format: sboms.group(:format).count,
            average_components: sboms.average(:component_count)&.round(0),
            average_vulnerabilities: sboms.average(:vulnerability_count)&.round(0),
            ntia_compliance_rate: sboms.any? ? (sboms.where(ntia_minimum_compliant: true).count.to_f / sboms.count * 100).round(1) : 0
          }
        end

        def build_container_metrics
          images = current_account.supply_chain_container_images

          {
            total: images.count,
            by_status: images.group(:status).count,
            deployed: images.where(is_deployed: true).count,
            total_vulnerabilities: {
              critical: images.sum(:critical_vuln_count),
              high: images.sum(:high_vuln_count),
              medium: images.sum(:medium_vuln_count),
              low: images.sum(:low_vuln_count)
            }
          }
        end

        def build_vendor_risk_metrics
          vendors = current_account.supply_chain_vendors.where(status: "active")

          {
            total_active: vendors.count,
            by_risk_tier: vendors.group(:risk_tier).count,
            by_type: vendors.group(:vendor_type).count,
            average_risk_score: vendors.where.not(risk_score: nil).average(:risk_score)&.round(2),
            assessments_completed: current_account.supply_chain_risk_assessments.where(status: "completed").count
          }
        end

        def build_compliance_metrics
          {
            license_violations: current_account.supply_chain_license_violations.where(status: "open").count,
            policy_violations: current_account.supply_chain_license_violations.group(:violation_type).count,
            compliant_sboms: current_account.supply_chain_sboms.where(ntia_minimum_compliant: true).count,
            signed_attestations: current_account.supply_chain_attestations.where.not(signature: nil).count
          }
        end

        def calculate_overall_compliance_status
          scores = []

          # NTIA compliance
          sboms = current_account.supply_chain_sboms
          if sboms.any?
            scores << (sboms.where(ntia_minimum_compliant: true).count.to_f / sboms.count * 100)
          end

          # License compliance
          violations = current_account.supply_chain_license_violations.where(status: "open").count
          scores << [100 - (violations * 10), 0].max

          # Vendor compliance
          vendors = current_account.supply_chain_vendors.where(status: "active")
          if vendors.any?
            assessed = vendors.reject(&:needs_assessment?).count
            scores << (assessed.to_f / vendors.count * 100)
          end

          average = scores.any? ? (scores.sum / scores.length).round(1) : 100

          {
            score: average,
            status: average >= 80 ? "good" : (average >= 60 ? "warning" : "critical")
          }
        end

        def build_ntia_compliance
          sboms = current_account.supply_chain_sboms

          {
            compliant_count: sboms.where(ntia_minimum_compliant: true).count,
            total_count: sboms.count,
            compliance_rate: sboms.any? ? (sboms.where(ntia_minimum_compliant: true).count.to_f / sboms.count * 100).round(1) : 100
          }
        end

        def build_slsa_compliance
          attestations = current_account.supply_chain_attestations

          {
            total: attestations.count,
            by_level: attestations.group(:slsa_level).count,
            signed_percentage: attestations.any? ? (attestations.where.not(signature: nil).count.to_f / attestations.count * 100).round(1) : 0,
            rekor_logged_percentage: attestations.any? ? (attestations.where.not(rekor_log_id: nil).count.to_f / attestations.count * 100).round(1) : 0
          }
        end

        def build_license_compliance
          {
            policies_active: current_account.supply_chain_license_policies.where(is_active: true).count,
            violations_open: current_account.supply_chain_license_violations.where(status: "open").count,
            violations_by_type: current_account.supply_chain_license_violations.where(status: "open").group(:violation_type).count
          }
        end

        def build_vendor_compliance
          vendors = current_account.supply_chain_vendors.where(status: "active")

          {
            total_active: vendors.count,
            with_dpa: vendors.where(handles_pii: true, has_dpa: true).count,
            pii_without_dpa: vendors.where(handles_pii: true, has_dpa: false).count,
            with_baa: vendors.where(handles_phi: true, has_baa: true).count,
            phi_without_baa: vendors.where(handles_phi: true, has_baa: false).count,
            assessments_current: vendors.reject(&:needs_assessment?).count
          }
        end

        def build_compliance_recommendations
          recommendations = []

          # Check for SBOMs without NTIA compliance
          non_compliant = current_account.supply_chain_sboms.where(ntia_minimum_compliant: false).count
          if non_compliant > 0
            recommendations << {
              priority: "high",
              category: "sbom",
              recommendation: "Update #{non_compliant} SBOMs to meet NTIA minimum elements",
              action: "Review SBOM generation settings and ensure all required fields are populated"
            }
          end

          # Check for unsigned attestations
          unsigned = current_account.supply_chain_attestations.where(signature: nil).count
          if unsigned > 0
            recommendations << {
              priority: "medium",
              category: "attestation",
              recommendation: "Sign #{unsigned} attestations for supply chain security",
              action: "Configure signing keys and enable automatic signing"
            }
          end

          # Check for open critical vulnerabilities
          critical_open = current_account.supply_chain_sbom_vulnerabilities
                                         .where(severity: "critical", remediation_status: "open")
                                         .count
          if critical_open > 0
            recommendations << {
              priority: "critical",
              category: "vulnerability",
              recommendation: "Address #{critical_open} critical vulnerabilities immediately",
              action: "Review affected components and apply patches or mitigations"
            }
          end

          # Check for vendors needing assessment
          needing_assessment = current_account.supply_chain_vendors
                                              .where(status: "active")
                                              .select(&:needs_assessment?)
                                              .count
          if needing_assessment > 0
            recommendations << {
              priority: "medium",
              category: "vendor",
              recommendation: "Complete risk assessments for #{needing_assessment} vendors",
              action: "Schedule and conduct vendor risk assessments"
            }
          end

          recommendations
        end
      end
    end
  end
end
