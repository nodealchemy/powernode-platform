# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mcp::ConditionalEvaluator, type: :service do
  describe '#evaluate' do
    context 'with numeric comparisons' do
      it 'evaluates greater than (>) correctly' do
        evaluator = described_class.new(
          condition: { expression: 'score > threshold' },
          context: { threshold: 0.8 },
          node_result: { score: 0.9 }
        )

        expect(evaluator.evaluate).to be true
      end

      it 'evaluates less than (<) correctly' do
        evaluator = described_class.new(
          condition: { expression: 'score < threshold' },
          context: { threshold: 0.8 },
          node_result: { score: 0.5 }
        )

        expect(evaluator.evaluate).to be true
      end

      it 'evaluates greater than or equal (>=) correctly' do
        evaluator = described_class.new(
          condition: { expression: 'score >= threshold' },
          context: { threshold: 0.8 },
          node_result: { score: 0.8 }
        )

        expect(evaluator.evaluate).to be true
      end

      it 'evaluates less than or equal (<=) correctly' do
        evaluator = described_class.new(
          condition: { expression: 'score <= threshold' },
          context: { threshold: 0.8 },
          node_result: { score: 0.8 }
        )

        expect(evaluator.evaluate).to be true
      end

      it 'evaluates equality (==) correctly' do
        evaluator = described_class.new(
          condition: { expression: 'count == expected' },
          context: { expected: 5 },
          node_result: { count: 5 }
        )

        expect(evaluator.evaluate).to be true
      end

      it 'evaluates inequality (!=) correctly' do
        evaluator = described_class.new(
          condition: { expression: 'status != error' },
          context: { error: 'failed' },
          node_result: { status: 'success' }
        )

        expect(evaluator.evaluate).to be true
      end

      it 'returns false when condition not met' do
        evaluator = described_class.new(
          condition: { expression: 'score > threshold' },
          context: { threshold: 0.8 },
          node_result: { score: 0.7 }
        )

        expect(evaluator.evaluate).to be false
      end
    end

    context 'with literal values' do
      it 'compares variable against numeric literal' do
        evaluator = described_class.new(
          condition: { expression: 'score > 0.8' },
          context: {},
          node_result: { score: 0.9 }
        )

        expect(evaluator.evaluate).to be true
      end

      it 'compares variable against integer literal' do
        evaluator = described_class.new(
          condition: { expression: 'count >= 5' },
          context: {},
          node_result: { count: 10 }
        )

        expect(evaluator.evaluate).to be true
      end

      it 'compares variable against negative number' do
        evaluator = described_class.new(
          condition: { expression: 'temperature < -10' },
          context: {},
          node_result: { temperature: -15 }
        )

        expect(evaluator.evaluate).to be true
      end
    end

    context 'with output_data nested structure' do
      it 'resolves variables from output_data hash' do
        evaluator = described_class.new(
          condition: { expression: 'score > threshold' },
          context: { threshold: 0.8 },
          node_result: { output_data: { score: 0.9 } }
        )

        expect(evaluator.evaluate).to be true
      end

      it 'resolves variables from input_variables in context' do
        evaluator = described_class.new(
          condition: { expression: 'score > threshold' },
          context: { input_variables: { threshold: 0.8 } },
          node_result: { score: 0.9 }
        )

        expect(evaluator.evaluate).to be true
      end

      it 'resolves variables from variables key in execution context' do
        evaluator = described_class.new(
          condition: { expression: 'score > threshold' },
          context: { variables: { score: 0.9, threshold: 0.8 } },
          node_result: {}
        )

        expect(evaluator.evaluate).to be true
      end
    end

    context 'with symbol keys' do
      it 'handles symbol keys in condition' do
        evaluator = described_class.new(
          condition: { expression: 'score > threshold' },
          context: { threshold: 0.8 },
          node_result: { score: 0.9 }
        )

        expect(evaluator.evaluate).to be true
      end

      it 'resolves variables with symbol keys' do
        evaluator = described_class.new(
          condition: { expression: 'score > threshold' },
          context: { threshold: 0.8 },
          node_result: { score: 0.9 }
        )

        expect(evaluator.evaluate).to be true
      end
    end

    context 'with boolean literals' do
      it 'compares boolean variable against true literal' do
        evaluator = described_class.new(
          condition: { expression: 'success == true' },
          context: {},
          node_result: { success: true }
        )

        expect(evaluator.evaluate).to be true
      end

      it 'compares boolean variable against false literal' do
        evaluator = described_class.new(
          condition: { expression: 'failed == false' },
          context: {},
          node_result: { failed: false }
        )

        expect(evaluator.evaluate).to be true
      end
    end

    context 'with string literals' do
      it 'compares string variable against double-quoted literal' do
        evaluator = described_class.new(
          condition: { expression: 'status == "active"' },
          context: {},
          node_result: { status: 'active' }
        )

        expect(evaluator.evaluate).to be true
      end

      it 'compares string variable against single-quoted literal' do
        evaluator = described_class.new(
          condition: { expression: "status == 'active'" },
          context: {},
          node_result: { status: 'active' }
        )

        expect(evaluator.evaluate).to be true
      end
    end

    context 'with error handling' do
      it 'raises ArgumentError for blank expression' do
        evaluator = described_class.new(
          condition: { expression: '' },
          context: {},
          node_result: {}
        )

        expect { evaluator.evaluate }.to raise_error(ArgumentError, /cannot be blank/)
      end

      it 'raises ArgumentError for missing expression' do
        evaluator = described_class.new(
          condition: {},
          context: {},
          node_result: {}
        )

        expect { evaluator.evaluate }.to raise_error(ArgumentError, /cannot be blank/)
      end

      it 'raises ArgumentError for invalid expression format' do
        evaluator = described_class.new(
          condition: { expression: 'score threshold' },
          context: {},
          node_result: {}
        )

        expect { evaluator.evaluate }.to raise_error(ArgumentError, /Invalid expression format/)
      end

      it 'raises ArgumentError for unsupported operator' do
        evaluator = described_class.new(
          condition: { expression: 'score && threshold' },
          context: {},
          node_result: {}
        )

        expect { evaluator.evaluate }.to raise_error(ArgumentError, /Invalid expression format/)
      end

      it 'raises ArgumentError for undefined variable' do
        evaluator = described_class.new(
          condition: { expression: 'unknown_var > threshold' },
          context: { threshold: 0.8 },
          node_result: {}
        )

        expect { evaluator.evaluate }.to raise_error(ArgumentError, /Variable 'unknown_var' not found/)
      end
    end

    context 'with edge cases' do
      it 'handles expressions with extra whitespace' do
        evaluator = described_class.new(
          condition: { expression: '  score   >   threshold  ' },
          context: { threshold: 0.8 },
          node_result: { score: 0.9 }
        )

        expect(evaluator.evaluate).to be true
      end

      it 'handles decimal numbers correctly' do
        evaluator = described_class.new(
          condition: { expression: 'score > 0.75' },
          context: {},
          node_result: { score: 0.9 }
        )

        expect(evaluator.evaluate).to be true
      end

      it 'handles zero values correctly' do
        evaluator = described_class.new(
          condition: { expression: 'count > 0' },
          context: {},
          node_result: { count: 5 }
        )

        expect(evaluator.evaluate).to be true
      end
    end
  end
end
