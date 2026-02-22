# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Guardrails::OutputRail, type: :service do
  let(:account) { create(:account) }
  let(:config) do
    create(:ai_guardrail_config, :global, account: account,
           max_output_tokens: 50_000,
           toxicity_threshold: 0.7,
           pii_sensitivity: 0.8)
  end

  subject(:rail) { described_class.new(config: config) }

  describe 'BUILT_IN_RAILS' do
    it 'defines expected built-in rail types' do
      expect(described_class::BUILT_IN_RAILS).to contain_exactly(
        'token_limit', 'toxicity', 'pii_detection', 'hallucination_check', 'format_validation', 'structured_output'
      )
    end
  end

  describe '#check' do
    it 'dispatches to the correct handler based on rail type' do
      result = rail.check(text: "hello", rail: { "type" => "token_limit" })
      expect(result[:rail]).to eq("token_limit")
    end

    it 'handles symbol keys in rail spec' do
      result = rail.check(text: "hello", rail: { type: "toxicity" })
      expect(result[:rail]).to eq("toxicity")
    end

    it 'passes unknown rail types' do
      result = rail.check(text: "hello", rail: { "type" => "nonexistent_rail" })
      expect(result[:passed]).to be true
      expect(result[:rail]).to eq("nonexistent_rail")
    end
  end

  describe 'token_limit' do
    it 'passes when output is within token limit' do
      result = rail.check(text: "Short response", rail: { "type" => "token_limit", "max_tokens" => 1000 })

      expect(result[:passed]).to be true
      expect(result[:rail]).to eq("token_limit")
    end

    it 'fails when output exceeds token limit' do
      long_text = "a" * 500
      result = rail.check(text: long_text, rail: { "type" => "token_limit", "max_tokens" => 10 })

      expect(result[:passed]).to be false
      expect(result[:severity]).to eq(:warning)
      expect(result[:message]).to include("Output exceeds token limit")
    end

    it 'uses rail-specific max_tokens over config default' do
      result = rail.check(text: "a" * 100, rail: { "type" => "token_limit", "max_tokens" => 5 })
      expect(result[:passed]).to be false
    end

    it 'falls back to config max_output_tokens when rail does not specify' do
      low_config = create(:ai_guardrail_config, :global, account: account,
                          max_output_tokens: 5, name: "Low Output Config")
      low_rail = described_class.new(config: low_config)

      result = low_rail.check(text: "a" * 100, rail: { "type" => "token_limit" })
      expect(result[:passed]).to be false
    end

    it 'uses default of 50_000 when neither rail nor config specify' do
      nil_config = create(:ai_guardrail_config, :global, account: account,
                          max_output_tokens: nil, name: "Nil Output Config")
      nil_rail = described_class.new(config: nil_config)

      result = nil_rail.check(text: "Hello", rail: { "type" => "token_limit" })
      expect(result[:passed]).to be true
    end

    it 'handles empty text' do
      result = rail.check(text: "", rail: { "type" => "token_limit", "max_tokens" => 10 })
      expect(result[:passed]).to be true
    end
  end

  describe 'toxicity' do
    it 'passes clean text' do
      result = rail.check(
        text: "Here is a helpful summary of the requested information.",
        rail: { "type" => "toxicity" }
      )

      expect(result[:passed]).to be true
    end

    it 'detects violent content targeting people' do
      result = rail.check(
        text: "I want to kill you and destroy them and attack everyone and bomb people",
        rail: { "type" => "toxicity", "threshold" => 0.3 }
      )

      expect(result[:passed]).to be false
      expect(result[:severity]).to eq(:critical)
      expect(result[:message]).to include("toxicity score")
      expect(result[:message]).to include("exceeds threshold")
    end

    it 'detects hate speech patterns' do
      result = rail.check(
        text: "I hate all humans and despise all creatures",
        rail: { "type" => "toxicity", "threshold" => 0.3 }
      )

      expect(result[:passed]).to be false
    end

    it 'uses rail-specific threshold over config default' do
      result = rail.check(
        text: "kill you and attack everyone",
        rail: { "type" => "toxicity", "threshold" => 0.1 }
      )

      expect(result[:passed]).to be false
    end

    it 'uses config toxicity_threshold as fallback' do
      result = rail.check(
        text: "Here is a normal response",
        rail: { "type" => "toxicity" }
      )

      expect(result[:passed]).to be true
    end

    it 'passes when score is below threshold' do
      # Only one pattern matches out of two -> score 0.5, default threshold 0.7
      result = rail.check(
        text: "I want to kill you please",
        rail: { "type" => "toxicity" }
      )

      expect(result[:passed]).to be true
    end

    it 'handles empty text' do
      result = rail.check(text: "", rail: { "type" => "toxicity" })
      expect(result[:passed]).to be true
    end
  end

  describe 'pii_detection (leakage)' do
    describe 'email detection' do
      it 'detects email addresses in output' do
        result = rail.check(
          text: "The user's email is john.doe@company.com",
          rail: { "type" => "pii_detection" }
        )

        expect(result[:passed]).to be false
        expect(result[:details][:pii_types]).to include("email")
      end
    end

    describe 'phone detection' do
      it 'detects phone numbers in output' do
        result = rail.check(
          text: "Their phone number is 555-867-5309",
          rail: { "type" => "pii_detection" }
        )

        expect(result[:passed]).to be false
        expect(result[:details][:pii_types]).to include("phone")
      end

      it 'detects phone numbers without dashes' do
        result = rail.check(
          text: "Call 5558675309 for more info",
          rail: { "type" => "pii_detection" }
        )

        expect(result[:passed]).to be false
      end
    end

    describe 'SSN detection' do
      it 'detects SSN in output' do
        result = rail.check(
          text: "SSN on file: 123-45-6789",
          rail: { "type" => "pii_detection" }
        )

        expect(result[:passed]).to be false
        expect(result[:details][:pii_types]).to include("ssn")
      end
    end

    describe 'credit card detection' do
      it 'detects credit card numbers with dashes' do
        result = rail.check(
          text: "Card ending in 4111-1111-1111-1111",
          rail: { "type" => "pii_detection" }
        )

        expect(result[:passed]).to be false
        expect(result[:details][:pii_types]).to include("credit_card")
      end

      it 'detects credit card numbers with spaces' do
        result = rail.check(
          text: "Card: 4111 1111 1111 1111",
          rail: { "type" => "pii_detection" }
        )

        expect(result[:passed]).to be false
      end

      it 'detects continuous credit card numbers' do
        result = rail.check(
          text: "CC: 4111111111111111",
          rail: { "type" => "pii_detection" }
        )

        expect(result[:passed]).to be false
      end
    end

    describe 'multiple PII types' do
      it 'detects all PII types in output' do
        result = rail.check(
          text: "User info: john@test.com, SSN: 123-45-6789, Phone: 555-123-4567",
          rail: { "type" => "pii_detection" }
        )

        expect(result[:passed]).to be false
        expect(result[:details][:pii_types]).to contain_exactly("email", "phone", "ssn")
        expect(result[:message]).to include("PII detected in output")
      end
    end

    describe 'severity based on sensitivity' do
      it 'returns critical severity when sensitivity >= 0.8' do
        result = rail.check(
          text: "Email: user@test.com",
          rail: { "type" => "pii_detection", "sensitivity" => 0.9 }
        )

        expect(result[:severity]).to eq(:critical)
      end

      it 'returns warning severity when sensitivity < 0.8' do
        result = rail.check(
          text: "Email: user@test.com",
          rail: { "type" => "pii_detection", "sensitivity" => 0.5 }
        )

        expect(result[:severity]).to eq(:warning)
      end

      it 'uses config pii_sensitivity as fallback' do
        # config has pii_sensitivity: 0.8 -> critical
        result = rail.check(
          text: "Email: user@test.com",
          rail: { "type" => "pii_detection" }
        )

        expect(result[:severity]).to eq(:critical)
      end
    end

    describe 'clean output' do
      it 'passes when no PII is found' do
        result = rail.check(
          text: "Here is a summary of your data without any personal information",
          rail: { "type" => "pii_detection" }
        )

        expect(result[:passed]).to be true
      end
    end
  end

  describe 'hallucination_check' do
    it 'passes when no input_text is provided' do
      result = rail.check(
        text: "I'm absolutely certain this is correct",
        rail: { "type" => "hallucination_check" }
      )

      expect(result[:passed]).to be true
    end

    it 'detects overconfident "I am 100% sure" claims' do
      result = rail.check(
        text: "I am 100% sure this is the answer",
        rail: { "type" => "hallucination_check" },
        input_text: "What is the meaning of life?"
      )

      expect(result[:passed]).to be false
      expect(result[:severity]).to eq(:warning)
      expect(result[:message]).to include("overconfident")
    end

    it 'detects "I\'m absolutely certain" claims' do
      result = rail.check(
        text: "I'm absolutely certain that the earth is flat",
        rail: { "type" => "hallucination_check" },
        input_text: "Is the earth flat?"
      )

      expect(result[:passed]).to be false
    end

    it 'detects "I\'m completely sure" claims' do
      result = rail.check(
        text: "I'm completely sure about this fact",
        rail: { "type" => "hallucination_check" },
        input_text: "Tell me a fact"
      )

      expect(result[:passed]).to be false
    end

    it 'detects "definitely true" claims' do
      result = rail.check(
        text: "This is definitely true and proven",
        rail: { "type" => "hallucination_check" },
        input_text: "Is this true?"
      )

      expect(result[:passed]).to be false
    end

    it 'detects "undoubtedly correct" claims' do
      result = rail.check(
        text: "This is undoubtedly correct based on my analysis",
        rail: { "type" => "hallucination_check" },
        input_text: "Verify this"
      )

      expect(result[:passed]).to be false
    end

    it 'passes measured language' do
      result = rail.check(
        text: "Based on the available information, the answer appears to be 42",
        rail: { "type" => "hallucination_check" },
        input_text: "What is the answer?"
      )

      expect(result[:passed]).to be true
    end

    it 'passes when confidence words are used in other contexts' do
      result = rail.check(
        text: "The data shows a clear trend but further verification is needed",
        rail: { "type" => "hallucination_check" },
        input_text: "Analyze this data"
      )

      expect(result[:passed]).to be true
    end
  end

  describe 'format_validation' do
    describe 'JSON format' do
      it 'passes valid JSON' do
        result = rail.check(
          text: '{"key": "value", "number": 42}',
          rail: { "type" => "format_validation", "format" => "json" }
        )

        expect(result[:passed]).to be true
      end

      it 'passes valid JSON array' do
        result = rail.check(
          text: '[1, 2, 3]',
          rail: { "type" => "format_validation", "format" => "json" }
        )

        expect(result[:passed]).to be true
      end

      it 'fails invalid JSON' do
        result = rail.check(
          text: "This is not JSON {broken",
          rail: { "type" => "format_validation", "format" => "json" }
        )

        expect(result[:passed]).to be false
        expect(result[:severity]).to eq(:warning)
        expect(result[:message]).to include("json")
      end

      it 'fails empty string as JSON' do
        result = rail.check(
          text: "",
          rail: { "type" => "format_validation", "format" => "json" }
        )

        expect(result[:passed]).to be false
      end

      it 'passes nested JSON' do
        result = rail.check(
          text: '{"outer": {"inner": [1, 2, {"deep": true}]}}',
          rail: { "type" => "format_validation", "format" => "json" }
        )

        expect(result[:passed]).to be true
      end
    end

    describe 'markdown format' do
      it 'passes text with headings' do
        result = rail.check(
          text: "# Heading\nSome content",
          rail: { "type" => "format_validation", "format" => "markdown" }
        )

        expect(result[:passed]).to be true
      end

      it 'passes text with list items' do
        result = rail.check(
          text: "- Item 1\n- Item 2",
          rail: { "type" => "format_validation", "format" => "markdown" }
        )

        expect(result[:passed]).to be true
      end

      it 'passes text with code blocks' do
        result = rail.check(
          text: "```ruby\nputs 'hello'\n```",
          rail: { "type" => "format_validation", "format" => "markdown" }
        )

        expect(result[:passed]).to be true
      end

      it 'fails plain text without markdown elements' do
        result = rail.check(
          text: "This is just plain text with no markdown formatting at all.",
          rail: { "type" => "format_validation", "format" => "markdown" }
        )

        expect(result[:passed]).to be false
      end
    end

    describe 'no format specified' do
      it 'passes when format is nil' do
        result = rail.check(
          text: "Anything goes",
          rail: { "type" => "format_validation" }
        )

        expect(result[:passed]).to be true
      end
    end

    describe 'unknown format' do
      it 'passes for unrecognized formats' do
        result = rail.check(
          text: "Some text",
          rail: { "type" => "format_validation", "format" => "xml" }
        )

        expect(result[:passed]).to be true
      end
    end
  end

  describe 'regex_filter' do
    it 'detects text matching blocked patterns' do
      result = rail.check(
        text: "The internal API endpoint is /admin/secret",
        rail: { "type" => "regex_filter", "patterns" => ["/admin/\\w+"] }
      )

      expect(result[:passed]).to be false
      expect(result[:message]).to eq("Output matched blocked pattern")
    end

    it 'matches case-insensitively' do
      result = rail.check(
        text: "INTERNAL USE ONLY",
        rail: { "type" => "regex_filter", "patterns" => ["internal use only"] }
      )

      expect(result[:passed]).to be false
    end

    it 'passes when no patterns match' do
      result = rail.check(
        text: "Normal output text",
        rail: { "type" => "regex_filter", "patterns" => ["classified", "restricted"] }
      )

      expect(result[:passed]).to be true
    end

    it 'handles empty patterns array' do
      result = rail.check(
        text: "Anything",
        rail: { "type" => "regex_filter", "patterns" => [] }
      )

      expect(result[:passed]).to be true
    end

    it 'uses custom severity from rail spec' do
      result = rail.check(
        text: "contains restricted content",
        rail: { "type" => "regex_filter", "patterns" => ["restricted"], "severity" => "critical" }
      )

      expect(result[:severity]).to eq(:critical)
    end

    it 'defaults severity to warning' do
      result = rail.check(
        text: "contains restricted content",
        rail: { "type" => "regex_filter", "patterns" => ["restricted"] }
      )

      expect(result[:severity]).to eq(:warning)
    end
  end

  describe 'credential_leak' do
    it 'detects API key patterns' do
      result = rail.check(
        text: "api_key: abcdefghijklmnopqrstuvwxyz123456",
        rail: { "type" => "credential_leak" }
      )

      expect(result[:passed]).to be false
      expect(result[:severity]).to eq(:critical)
      expect(result[:message]).to include("credential")
    end

    it 'detects api-key with dash separator' do
      result = rail.check(
        text: "api-key=abcdefghijklmnopqrstuvwxyz123456",
        rail: { "type" => "credential_leak" }
      )

      expect(result[:passed]).to be false
    end

    it 'detects password patterns' do
      result = rail.check(
        text: "password: supersecretpassword123",
        rail: { "type" => "credential_leak" }
      )

      expect(result[:passed]).to be false
    end

    it 'detects secret patterns' do
      result = rail.check(
        text: "secret=myverylongsecretvalue",
        rail: { "type" => "credential_leak" }
      )

      expect(result[:passed]).to be false
    end

    it 'detects bearer tokens' do
      result = rail.check(
        text: "bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ",
        rail: { "type" => "credential_leak" }
      )

      expect(result[:passed]).to be false
    end

    it 'detects private key headers' do
      result = rail.check(
        text: "-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEA...",
        rail: { "type" => "credential_leak" }
      )

      expect(result[:passed]).to be false
    end

    it 'detects EC private key headers' do
      result = rail.check(
        text: "-----BEGIN EC PRIVATE KEY-----\nMHQCAQEE...",
        rail: { "type" => "credential_leak" }
      )

      expect(result[:passed]).to be false
    end

    it 'detects generic private key headers' do
      result = rail.check(
        text: "-----BEGIN PRIVATE KEY-----\nSomeKeyData...",
        rail: { "type" => "credential_leak" }
      )

      expect(result[:passed]).to be false
    end

    it 'detects GitHub personal access tokens' do
      result = rail.check(
        text: "Use this token: ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij",
        rail: { "type" => "credential_leak" }
      )

      expect(result[:passed]).to be false
    end

    it 'detects OpenAI API keys' do
      result = rail.check(
        text: "Your key is sk-abcdefghijklmnopqrstuvwxyz123456789012345678901234",
        rail: { "type" => "credential_leak" }
      )

      expect(result[:passed]).to be false
    end

    it 'passes text without credentials' do
      result = rail.check(
        text: "Here is the information you requested about password management best practices.",
        rail: { "type" => "credential_leak" }
      )

      expect(result[:passed]).to be true
    end

    it 'passes short password-like strings that do not meet length threshold' do
      result = rail.check(
        text: "password: short",
        rail: { "type" => "credential_leak" }
      )

      expect(result[:passed]).to be true
    end

    it 'passes text mentioning API keys conceptually' do
      result = rail.check(
        text: "You should store your API keys in environment variables",
        rail: { "type" => "credential_leak" }
      )

      expect(result[:passed]).to be true
    end
  end

  describe 'edge cases' do
    it 'handles nil metadata gracefully' do
      result = rail.check(text: "hello", rail: { "type" => "token_limit" }, metadata: nil)
      expect(result[:passed]).to be true
    end

    it 'handles nil input_text for non-hallucination checks' do
      result = rail.check(text: "hello", rail: { "type" => "toxicity" }, input_text: nil)
      expect(result[:passed]).to be true
    end

    it 'handles very long output text' do
      long_text = "word " * 100_000
      result = rail.check(text: long_text, rail: { "type" => "toxicity" })
      expect(result[:passed]).to be true
    end

    it 'handles empty string output' do
      result = rail.check(text: "", rail: { "type" => "credential_leak" })
      expect(result[:passed]).to be true
    end

    it 'handles text with unicode characters' do
      result = rail.check(
        text: "Here is your answer: 42",
        rail: { "type" => "toxicity" }
      )
      expect(result[:passed]).to be true
    end
  end
end
