# frozen_string_literal: true

module Ai
  module Intelligence
    class SupplyChainAnalysisService < BaseIntelligenceService
      SEVERITY_WEIGHTS = { "critical" => 10, "high" => 7, "medium" => 4, "low" => 1, "none" => 0, "unknown" => 0 }.freeze

      # AI-powered vulnerability triage with context-aware scoring
      def triage_vulnerabilities(sbom_id:)
        sbom = find_sbom!(sbom_id)
        return sbom unless sbom.is_a?(SupplyChain::Sbom)

        vulns = sbom.vulnerabilities.actionable.includes(:component)
        return success_response(sbom_id: sbom.id, total_actionable: 0, prioritized: [], summary: "No actionable vulnerabilities found") if vulns.empty?

        prioritized = vulns.map { |v| score_vulnerability(v) }.sort_by { |v| [-v[:priority_score], -v[:cvss_score].to_f] }
        audit_action("triage_vulnerabilities", "SupplyChain::Sbom", sbom.id, context: { vulnerability_count: prioritized.size })

        success_response(
          sbom_id: sbom.id, total_actionable: prioritized.size, prioritized: prioritized,
          severity_breakdown: severity_breakdown(vulns),
          triage_summary: {
            immediate_action: prioritized.count { |v| v[:urgency] == "immediate" },
            high_priority: prioritized.count { |v| v[:urgency] == "high" },
            medium_priority: prioritized.count { |v| v[:urgency] == "medium" },
            low_priority: prioritized.count { |v| v[:urgency] == "low" },
            with_fix_available: prioritized.count { |v| v[:has_fix] },
            exploits_known: prioritized.count { |v| v[:exploit_in_wild] }
          },
          triaged_at: Time.current.iso8601
        )
      rescue StandardError => e
        error_response("triage_vulnerabilities", e)
      end

      # Generate AI remediation plan with upgrade recommendations
      def generate_remediation_plan(sbom_id:, vulnerability_ids: nil)
        sbom = find_sbom!(sbom_id)
        return sbom unless sbom.is_a?(SupplyChain::Sbom)

        vulns = vulnerability_ids.present? ? sbom.vulnerabilities.where(id: vulnerability_ids).actionable.includes(:component) : sbom.vulnerabilities.actionable.includes(:component)
        return error_hash("No actionable vulnerabilities found for remediation") if vulns.empty?

        upgrade_recs = build_upgrade_recommendations(vulns)
        breaking = detect_breaking_changes(upgrade_recs)
        confidence = calculate_plan_confidence(vulns, upgrade_recs, breaking)

        plan = SupplyChain::RemediationPlan.create!(
          account: @account, sbom: sbom, plan_type: "ai_generated", status: "draft",
          confidence_score: confidence, auto_executable: confidence >= 0.85 && breaking.empty?,
          target_vulnerabilities: vulns.map(&:id), upgrade_recommendations: upgrade_recs,
          breaking_changes: breaking,
          metadata: { generated_by: "ai_intelligence", vulnerability_count: vulns.size, generated_at: Time.current.iso8601 }
        )

        audit_action("generate_remediation_plan", "SupplyChain::RemediationPlan", plan.id, context: { vulnerability_count: vulns.size, confidence: confidence })
        risk_level = breaking.size > 3 ? "high" : breaking.any? ? "medium" : "low"

        success_response(
          plan_id: plan.id, plan_type: plan.plan_type, status: plan.status,
          confidence_score: confidence, auto_executable: plan.auto_executable,
          target_vulnerability_count: vulns.size, upgrade_recommendations: upgrade_recs,
          breaking_changes: breaking,
          risk_assessment: { risk_level: risk_level, total_upgrades: upgrade_recs.size, breaking_change_count: breaking.size },
          created_at: plan.created_at.iso8601
        )
      rescue StandardError => e
        error_response("generate_remediation_plan", e)
      end

      # Analyze vulnerability risk trends over a time period
      def analyze_risk_trends(period_days: 30)
        cutoff = period_days.days.ago
        vulns = account_vulnerabilities
        current_open = vulns.actionable
        current_counts = current_open.group(:severity).count

        discovered = vulns.where("created_at >= ?", cutoff).group(:severity).count
        fixed = vulns.fixed.where("updated_at >= ?", cutoff).group(:severity).count
        dismissed = vulns.dismissed.where("updated_at >= ?", cutoff).group(:severity).count

        weekly = build_weekly_trends(vulns, period_days)
        fixed_vulns = vulns.fixed.where("updated_at >= ?", cutoff)
        mttr = fixed_vulns.any? ? { average_days: (fixed_vulns.sum { |v| (v.updated_at - v.created_at).to_f / 1.day } / fixed_vulns.count).round(1), sample_size: fixed_vulns.count } : nil

        success_response(
          period_days: period_days,
          current_state: { total_open: current_open.count, by_severity: norm_sev(current_counts), risk_score: calculate_aggregate_risk_score(current_open) },
          period_activity: {
            discovered: norm_sev(discovered), fixed: norm_sev(fixed), dismissed: norm_sev(dismissed),
            net_change: { new_vulnerabilities: discovered.values.sum, resolved: fixed.values.sum + dismissed.values.sum, net: discovered.values.sum - fixed.values.sum - dismissed.values.sum }
          },
          weekly_trends: weekly, mean_time_to_remediation: mttr,
          trajectory: trend_trajectory(weekly), analyzed_at: Time.current.iso8601
        )
      rescue StandardError => e
        error_response("analyze_risk_trends", e)
      end

      # Run license compliance audit and return structured findings
      def license_audit(sbom_id:)
        sbom = find_sbom!(sbom_id)
        return sbom unless sbom.is_a?(SupplyChain::Sbom)

        svc = SupplyChain::LicenseComplianceService.new(account: @account, sbom: sbom)
        evaluation = svc.evaluate!
        gpl_check = svc.check_gpl_contamination

        audit_action("license_audit", "SupplyChain::Sbom", sbom.id, context: { compliant: evaluation[:compliant], violation_count: evaluation[:violation_count].to_i })

        recs = []
        recs << { type: "compliance", priority: "high", message: "#{evaluation[:violation_count]} license violations require review" } unless evaluation[:compliant]
        recs << { type: "copyleft_risk", priority: "critical", message: "#{gpl_check[:contamination_count]} strong copyleft components detected" } if gpl_check[:contaminated]
        recs << { type: "status", priority: "info", message: "All licenses compliant with current policy" } if evaluation[:compliant] && !gpl_check[:contaminated]

        license_dist = sbom.components.where.not(license_spdx_id: nil).group(:license_spdx_id).count.sort_by { |_, c| -c }.first(20).to_h

        success_response(
          sbom_id: sbom.id, compliant: evaluation[:compliant], policy: evaluation[:policy],
          violation_count: evaluation[:violation_count].to_i, violations: evaluation[:violations],
          gpl_contamination: gpl_check, existing_open_violations: sbom.license_violations.where(status: "open").count,
          license_distribution: license_dist, recommendations: recs, audited_at: Time.current.iso8601
        )
      rescue StandardError => e
        error_response("license_audit", e)
      end

      # Overall security posture score with multi-factor breakdown
      def security_posture(sbom_id: nil)
        sbom_id.present? ? posture_for_sbom(find_sbom!(sbom_id).tap { |s| return s unless s.is_a?(SupplyChain::Sbom) }) : posture_for_account
      rescue StandardError => e
        error_response("security_posture", e)
      end

      private

      def score_vulnerability(vuln)
        base = vuln.contextual_score || vuln.cvss_score || 0
        factors = vuln.context_factors&.with_indifferent_access || {}
        score = base
        score += 2.0 if factors[:exploit_in_wild] || factors[:poc_available]
        score += 1.5 if vuln.has_fix?
        score += 1.0 if vuln.published_at.present? && vuln.published_at > 14.days.ago
        depth = vuln.component.respond_to?(:depth) ? vuln.component.depth.to_i : 0
        score -= 0.5 * depth if depth > 1
        score = [[score, 0].max, 15].min

        action = if vuln.has_fix? && score >= 8 then "Upgrade immediately to #{vuln.fixed_version}"
                 elsif vuln.has_fix? && score >= 5 then "Schedule upgrade to #{vuln.fixed_version}"
                 elsif score >= 8 then "Apply workaround or mitigating controls - no fix available"
                 elsif score >= 5 then "Monitor for fix availability and apply mitigations"
                 else "Monitor and review during next maintenance window"
                 end

        urgency = score >= 9 ? "immediate" : score >= 7 ? "high" : score >= 5 ? "medium" : "low"

        {
          vulnerability_id: vuln.id, cve: vuln.vulnerability_id, severity: vuln.severity,
          cvss_score: vuln.cvss_score, contextual_score: vuln.contextual_score, priority_score: score.round(2),
          component: vuln.component.respond_to?(:versioned_name) ? vuln.component.versioned_name : vuln.component.id,
          has_fix: vuln.has_fix?, fixed_version: vuln.fixed_version,
          exploit_in_wild: factors[:exploit_in_wild] || false, poc_available: factors[:poc_available] || false,
          recommended_action: action, urgency: urgency
        }
      end

      def build_upgrade_recommendations(vulns)
        vulns.group_by(&:component_id).filter_map do |_, group|
          component = group.first.component
          fixable = group.select(&:has_fix?)
          next if fixable.empty?

          target = fixable.map(&:fixed_version).compact.max_by { |v| Gem::Version.new(v) rescue v }
          {
            package_name: component.respond_to?(:name) ? component.name : component.id,
            current_version: component.respond_to?(:version) ? component.version : nil,
            target_version: target, vulnerabilities_addressed: fixable.size, total_vulnerabilities: group.size,
            max_severity: group.map { |v| SEVERITY_WEIGHTS[v.severity] || 0 }.max,
            reason: "Addresses #{fixable.size} known vulnerabilities (#{group.map(&:severity).tally})"
          }
        end.sort_by { |r| -(r[:max_severity] || 0) }
      end

      def detect_breaking_changes(recs)
        recs.filter_map do |rec|
          next unless rec[:current_version].present? && rec[:target_version].present?
          begin
            cur = Gem::Version.new(rec[:current_version])
            tgt = Gem::Version.new(rec[:target_version])
            if tgt.segments.first > cur.segments.first
              { package_name: rec[:package_name], from_version: rec[:current_version], to_version: rec[:target_version],
                type: "major_version_bump", description: "Major version upgrade from #{cur.segments.first}.x to #{tgt.segments.first}.x may include breaking API changes" }
            end
          rescue ArgumentError
            { package_name: rec[:package_name], from_version: rec[:current_version], to_version: rec[:target_version],
              type: "version_format_unknown", description: "Unable to determine semver compatibility - manual review recommended" }
          end
        end
      end

      def calculate_plan_confidence(vulns, upgrade_recs, breaking)
        return 0.0 if vulns.empty?
        coverage = upgrade_recs.sum { |r| r[:vulnerabilities_addressed] }.to_f / vulns.size
        [[coverage * 0.7 + 0.3 - breaking.size * 0.1, 0.0].max, 1.0].min.round(3)
      end

      def build_weekly_trends(vulns, period_days)
        weeks = (period_days / 7.0).ceil
        cutoff = period_days.days.ago.beginning_of_week
        (0...weeks).map do |i|
          ws = cutoff + i.weeks
          we = ws + 1.week
          opened = vulns.where(created_at: ws..we).count
          closed = vulns.where(remediation_status: %w[fixed dismissed wont_fix]).where(updated_at: ws..we).count
          { week_start: ws.to_date.iso8601, opened: opened, closed: closed, net: opened - closed }
        end
      end

      def trend_trajectory(weekly)
        return "insufficient_data" if weekly.size < 2
        recent_avg = weekly.last(2).sum { |w| w[:net] }.to_f / 2
        older_avg = weekly.first([weekly.size - 2, 1].max).sum { |w| w[:net] }.to_f / [weekly.size - 2, 1].max
        recent_avg < older_avg - 1 ? "improving" : recent_avg > older_avg + 1 ? "worsening" : "stable"
      end

      def posture_for_sbom(sbom)
        sev_counts = sbom.vulnerabilities.actionable.group(:severity).count
        total_comp = sbom.component_count
        vuln_s = vuln_posture_score(sev_counts, total_comp)
        total = sbom.components.count
        lic_s = total.zero? ? 100 : (sbom.components.where(license_compliance_status: "compliant").count.to_f / total * 100).round(1)
        comp_s = sbom.ntia_minimum_compliant ? 100 : 50
        overall = (vuln_s * 0.50 + lic_s * 0.30 + comp_s * 0.20).round(1)

        success_response(
          scope: "sbom", sbom_id: sbom.id, overall_score: overall, grade: grade(overall),
          breakdown: { vulnerability: { score: vuln_s, weight: 0.50 }, license_compliance: { score: lic_s, weight: 0.30 }, sbom_completeness: { score: comp_s, weight: 0.20 } },
          vulnerability_summary: norm_sev(sev_counts), total_components: total_comp,
          risk_level: risk_level(overall), assessed_at: Time.current.iso8601
        )
      end

      def posture_for_account
        sboms = SupplyChain::Sbom.where(account: @account).completed
        vulns = account_vulnerabilities.actionable
        sev_counts = vulns.group(:severity).count
        total_comp = [sboms.sum(:component_count), 1].max
        vuln_s = vuln_posture_score(sev_counts, total_comp)

        total_actionable = account_vulnerabilities.actionable.count
        rem_coverage = total_actionable.zero? ? 100 : [account_vulnerabilities.in_progress.count.to_f / total_actionable * 100, 100].min.round(1)
        plans = SupplyChain::RemediationPlan.where(account: @account)
        plan_total = plans.where.not(status: "draft").count
        plan_eff = plan_total.zero? ? 50 : (plans.completed.count.to_f / plan_total * 100).round(1)
        overall = (vuln_s * 0.5 + rem_coverage * 0.3 + plan_eff * 0.2).round(1)

        success_response(
          scope: "account", overall_score: overall, grade: grade(overall),
          breakdown: { vulnerability: { score: vuln_s, weight: 0.50 }, remediation_coverage: { score: rem_coverage, weight: 0.30 }, plan_effectiveness: { score: plan_eff, weight: 0.20 } },
          vulnerability_summary: norm_sev(sev_counts), sbom_count: sboms.count,
          total_components: total_comp, total_actionable_vulnerabilities: vulns.count,
          risk_level: risk_level(overall), assessed_at: Time.current.iso8601
        )
      end

      def vuln_posture_score(sev_counts, total_components)
        return 100 if sev_counts.empty?
        weighted = sev_counts.sum { |s, c| (SEVERITY_WEIGHTS[s] || 0) * c }
        [100 - (weighted.to_f / [total_components, 1].max) * 10, 0].max.round(1)
      end

      def calculate_aggregate_risk_score(vulns)
        return 0 if vulns.empty?
        total_weight = vulns.sum { |v| SEVERITY_WEIGHTS[v.severity] || 0 }
        [total_weight.to_f / [vulns.count, 1].max * 10, 100].min.round(1)
      end

      def grade(score)
        case score when 90..100 then "A" when 80..89 then "B" when 70..79 then "C" when 60..69 then "D" else "F" end
      end

      def risk_level(score)
        case score when 80..100 then "low" when 60..79 then "medium" when 40..59 then "high" else "critical" end
      end

      def find_sbom!(sbom_id)
        SupplyChain::Sbom.where(account: @account).find_by(id: sbom_id) || error_hash("SBOM not found: #{sbom_id}")
      end

      def account_vulnerabilities
        SupplyChain::SbomVulnerability.where(account: @account)
      end

      def severity_breakdown(vulns)
        norm_sev(vulns.group(:severity).count)
      end

      def norm_sev(counts)
        { critical: counts["critical"] || 0, high: counts["high"] || 0, medium: counts["medium"] || 0, low: counts["low"] || 0 }
      end

    end
  end
end
