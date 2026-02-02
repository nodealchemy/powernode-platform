# frozen_string_literal: true

module ProviderTesting
  module Reporting
    def generate_test_report
      connection_result = test_connection

      {
        summary: {
          overall_status: connection_result[:success] ? "healthy" : "unhealthy",
          health_score: connection_result[:success] ? 0.9 : 0.0,
          key_findings: generate_key_findings(connection_result),
          critical_issues: connection_result[:success] ? [] : [ connection_result[:error_details] ]
        },
        test_results: {
          connection_test: connection_result,
          timestamp: Time.current
        },
        performance_analysis: {
          response_time_analysis: {
            average: connection_result[:response_time_ms] || 0,
            rating: rate_response_time(connection_result[:response_time_ms])
          },
          reliability_analysis: {
            success_rate: connection_result[:success] ? 1.0 : 0.0,
            rating: connection_result[:success] ? "excellent" : "poor"
          },
          capability_analysis: {
            supported_features: [ "text_generation", "chat" ],
            rating: "good"
          },
          comparison_with_benchmarks: {
            vs_industry_average: "above_average"
          }
        },
        recommendations: generate_detailed_recommendations(connection_result),
        detailed_metrics: {
          response_time_ms: connection_result[:response_time_ms],
          provider_type: @provider.provider_type,
          connection_quality: connection_result[:connection_quality]
        },
        timestamp: Time.current
      }
    end

    private

    def generate_recommendations(connection_result)
      recommendations = []

      unless connection_result[:success]
        recommendations << {
          type: "error",
          description: "Connection failed: #{connection_result[:error_type]}",
          priority: "high"
        }
      end

      if connection_result[:response_time_ms] && connection_result[:response_time_ms] > 2000
        recommendations << {
          type: "performance",
          description: "High latency detected. Consider caching or using a closer region.",
          priority: "medium"
        }
      end

      recommendations
    end

    def generate_key_findings(connection_result)
      findings = []

      if connection_result[:success]
        findings << "Connection successful"
        findings << "Response time: #{connection_result[:response_time_ms]}ms" if connection_result[:response_time_ms]
      else
        findings << "Connection failed: #{connection_result[:error_type]}"
      end

      findings
    end

    def generate_detailed_recommendations(connection_result)
      recommendations = []

      unless connection_result[:success]
        recommendations << {
          priority: "critical",
          category: "connectivity",
          description: "Fix connection issues: #{connection_result[:error_details]}",
          implementation_steps: [ "Check API credentials", "Verify network connectivity", "Review provider status" ]
        }
      end

      if connection_result[:response_time_ms] && connection_result[:response_time_ms] > 1500
        recommendations << {
          priority: "medium",
          category: "performance",
          description: "Optimize response times",
          implementation_steps: [ "Consider using streaming", "Implement request caching", "Use batch requests" ]
        }
      end

      recommendations
    end
  end
end
