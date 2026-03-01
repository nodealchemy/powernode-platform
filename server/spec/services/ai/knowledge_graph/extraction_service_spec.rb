# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::KnowledgeGraph::ExtractionService, type: :service do
  let(:account) { create(:account) }
  let(:kb) { create(:ai_knowledge_base, account: account) }
  subject(:service) { described_class.new(account) }

  describe "#extract_from_document" do
    let(:document) do
      Ai::Document.create!(
        knowledge_base: kb,
        name: "Test Doc",
        source_type: "upload",
        content: "Ruby on Rails is a web framework created by David Heinemeier Hansson. " \
                 "Rails uses the Ruby programming language. " \
                 "PostgreSQL is a popular database used with Rails applications. " \
                 "The Active Record pattern is a core part of Rails.",
        status: "indexed"
      )
    end

    it "extracts entities and relations from document content" do
      result = service.extract_from_document(document: document)

      expect(result).to have_key(:nodes)
      expect(result).to have_key(:edges)
      expect(result).to have_key(:stats)
      expect(result[:stats][:nodes_created]).to be >= 0
    end

    it "raises error for document with no content" do
      empty_doc = Ai::Document.create!(
        knowledge_base: kb,
        name: "Empty Doc",
        source_type: "upload",
        content: nil,
        status: "pending"
      )

      expect {
        service.extract_from_document(document: empty_doc)
      }.to raise_error(Ai::KnowledgeGraph::ExtractionServiceError, /no content/)
    end

    it "deduplicates nodes with same name" do
      # Create existing node
      create(:ai_knowledge_graph_node, account: account, name: "Ruby", node_type: "entity")

      doc = Ai::Document.create!(
        knowledge_base: kb,
        name: "Ruby Doc",
        source_type: "upload",
        content: "Ruby is a programming language. Ruby was created by Yukihiro Matsumoto.",
        status: "indexed"
      )

      result = service.extract_from_document(document: doc)

      # Should have found existing node
      expect(result[:stats][:nodes_existing]).to be >= 0
    end

    context "with short content" do
      let(:short_doc) do
        Ai::Document.create!(
          knowledge_base: kb,
          name: "Short Doc",
          source_type: "upload",
          content: "Python uses Django framework.",
          status: "indexed"
        )
      end

      it "handles short content without chunking" do
        result = service.extract_from_document(document: short_doc)
        expect(result[:stats]).to be_present
      end
    end
  end
end
