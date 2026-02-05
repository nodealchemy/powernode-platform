# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::RagService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  subject(:service) { described_class.new(account) }

  describe '#initialize' do
    it 'initializes with account' do
      expect(service.account).to eq(account)
    end
  end

  describe 'Knowledge Base Operations' do
    describe '#create_knowledge_base' do
      it 'creates a knowledge base with default settings' do
        kb = service.create_knowledge_base({
          name: 'Test KB',
          description: 'A test knowledge base'
        }, user: user)

        expect(kb).to be_persisted
        expect(kb.name).to eq('Test KB')
        expect(kb.embedding_model).to eq('text-embedding-3-small')
        expect(kb.chunking_strategy).to eq('recursive')
        expect(kb.chunk_size).to eq(1000)
        expect(kb.chunk_overlap).to eq(200)
      end

      it 'creates with custom embedding settings' do
        kb = service.create_knowledge_base({
          name: 'Custom KB',
          description: 'Custom settings',
          embedding_model: 'text-embedding-ada-002',
          embedding_provider: 'openai',
          chunk_size: 500,
          chunk_overlap: 100
        }, user: user)

        expect(kb.embedding_model).to eq('text-embedding-ada-002')
        expect(kb.chunk_size).to eq(500)
        expect(kb.chunk_overlap).to eq(100)
      end

      it 'creates public knowledge base' do
        kb = service.create_knowledge_base({
          name: 'Public KB',
          description: 'Public',
          is_public: true
        })

        expect(kb.is_public).to be true
      end
    end

    describe '#get_knowledge_base' do
      let!(:kb) do
        service.create_knowledge_base({
          name: 'Lookup KB',
          description: 'For lookup'
        })
      end

      it 'finds knowledge base by id' do
        result = service.get_knowledge_base(kb.id)
        expect(result).to eq(kb)
      end

      it 'raises error for nonexistent id' do
        expect {
          service.get_knowledge_base(SecureRandom.uuid)
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    describe '#list_knowledge_bases' do
      before do
        service.create_knowledge_base({ name: 'KB 1', description: 'First' })
        service.create_knowledge_base({ name: 'KB 2', description: 'Second' })
      end

      it 'returns all knowledge bases' do
        results = service.list_knowledge_bases
        expect(results.count).to be >= 2
      end

      it 'filters by status' do
        results = service.list_knowledge_bases(status: 'active')
        expect(results).to respond_to(:each)
      end
    end

    describe '#update_knowledge_base' do
      let!(:kb) do
        service.create_knowledge_base({
          name: 'Original Name',
          description: 'Original description'
        })
      end

      it 'updates allowed attributes' do
        updated = service.update_knowledge_base(kb.id, {
          name: 'Updated Name',
          description: 'Updated description'
        })

        expect(updated.name).to eq('Updated Name')
        expect(updated.description).to eq('Updated description')
      end
    end

    describe '#delete_knowledge_base' do
      let!(:kb) do
        service.create_knowledge_base({
          name: 'Delete Me',
          description: 'Will be deleted'
        })
      end

      it 'deletes the knowledge base' do
        expect {
          service.delete_knowledge_base(kb.id)
        }.to change { account.ai_knowledge_bases.count }.by(-1)
      end
    end
  end

  describe 'Document Operations' do
    let!(:knowledge_base) do
      service.create_knowledge_base({
        name: 'Doc KB',
        description: 'For documents'
      })
    end

    describe '#create_document' do
      it 'creates a document with content' do
        doc = service.create_document(knowledge_base.id, {
          name: 'test-doc.txt',
          source_type: 'upload',
          content_type: 'text/plain',
          content: 'This is the document content for testing purposes.'
        }, user: user)

        expect(doc).to be_persisted
        expect(doc.name).to eq('test-doc.txt')
        expect(doc.content).to eq('This is the document content for testing purposes.')
        expect(doc.content_size_bytes).to be > 0
      end

      it 'calculates checksum for content' do
        doc = service.create_document(knowledge_base.id, {
          name: 'checksum-doc.txt',
          source_type: 'upload',
          content_type: 'text/plain',
          content: 'Content with checksum'
        })

        expect(doc.checksum).to be_present
      end
    end

    describe '#list_documents' do
      before do
        service.create_document(knowledge_base.id, {
          name: 'doc1.txt',
          source_type: 'upload',
          content: 'Content 1'
        })
        service.create_document(knowledge_base.id, {
          name: 'doc2.txt',
          source_type: 'upload',
          content: 'Content 2'
        })
      end

      it 'lists documents in knowledge base' do
        docs = service.list_documents(knowledge_base.id)
        expect(docs.count).to eq(2)
      end

      it 'filters by source_type' do
        docs = service.list_documents(knowledge_base.id, source_type: 'upload')
        expect(docs.count).to eq(2)
      end
    end

    describe '#get_document' do
      let!(:doc) do
        service.create_document(knowledge_base.id, {
          name: 'find-me.txt',
          source_type: 'upload',
          content: 'Find this document'
        })
      end

      it 'finds document by id' do
        result = service.get_document(knowledge_base.id, doc.id)
        expect(result).to eq(doc)
      end

      it 'raises error for nonexistent document' do
        expect {
          service.get_document(knowledge_base.id, SecureRandom.uuid)
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    describe '#delete_document' do
      let!(:doc) do
        service.create_document(knowledge_base.id, {
          name: 'delete-me.txt',
          source_type: 'upload',
          content: 'Will be deleted'
        })
      end

      it 'deletes the document' do
        expect {
          service.delete_document(knowledge_base.id, doc.id)
        }.to change { knowledge_base.documents.count }.by(-1)
      end
    end
  end

  describe 'Document Processing' do
    let!(:knowledge_base) do
      service.create_knowledge_base({
        name: 'Processing KB',
        description: 'For processing tests',
        chunking_strategy: 'fixed',
        chunk_size: 100,
        chunk_overlap: 20
      })
    end

    let!(:document) do
      long_content = "This is a paragraph about AI systems. " * 10 +
                     "\n\n" +
                     "This is another paragraph about machine learning. " * 10

      service.create_document(knowledge_base.id, {
        name: 'long-doc.txt',
        source_type: 'upload',
        content_type: 'text/plain',
        content: long_content
      })
    end

    describe '#process_document' do
      it 'creates chunks from document content' do
        processed = service.process_document(knowledge_base.id, document.id)

        expect(processed).to be_present
        expect(knowledge_base.document_chunks.count).to be > 0
      end

      it 'estimates token counts for chunks' do
        service.process_document(knowledge_base.id, document.id)

        knowledge_base.document_chunks.each do |chunk|
          expect(chunk.token_count).to be > 0
        end
      end
    end
  end

  describe 'Chunking Strategies (private)' do
    it 'handles fixed chunking' do
      content = "a" * 500
      chunks = service.send(:chunk_content, content, 'fixed', 100, 20)

      expect(chunks).to be_an(Array)
      expect(chunks.length).to be > 1
      chunks.each { |c| expect(c.length).to be <= 100 }
    end

    it 'handles sentence chunking' do
      content = "First sentence. Second sentence. Third sentence. Fourth sentence. Fifth sentence."
      chunks = service.send(:chunk_content, content, 'sentence', 50, 0)

      expect(chunks).to be_an(Array)
      expect(chunks.length).to be >= 1
    end

    it 'handles paragraph chunking' do
      content = "Paragraph one content.\n\nParagraph two content.\n\nParagraph three content."
      chunks = service.send(:chunk_content, content, 'paragraph', 1000, 0)

      expect(chunks.length).to eq(3)
    end

    it 'handles recursive chunking' do
      content = "Short paragraph.\n\n" + ("Long paragraph with lots of text. " * 20)
      chunks = service.send(:chunk_content, content, 'recursive', 200, 20)

      expect(chunks).to be_an(Array)
      expect(chunks.length).to be >= 2
    end

    it 'returns empty array for blank content' do
      chunks = service.send(:chunk_content, '', 'fixed', 100, 20)
      expect(chunks).to eq([])
    end

    it 'returns empty array for nil content' do
      chunks = service.send(:chunk_content, nil, 'fixed', 100, 20)
      expect(chunks).to eq([])
    end
  end

  describe 'Token Estimation (private)' do
    it 'estimates tokens from text length' do
      tokens = service.send(:estimate_tokens, "Hello world this is a test")
      # ~26 chars / 4 = ~7 tokens
      expect(tokens).to be_a(Integer)
      expect(tokens).to be > 0
    end

    it 'handles empty text' do
      tokens = service.send(:estimate_tokens, "")
      expect(tokens).to eq(0)
    end
  end

  describe 'Analytics' do
    let!(:knowledge_base) do
      service.create_knowledge_base({
        name: 'Analytics KB',
        description: 'For analytics'
      })
    end

    describe '#get_analytics' do
      it 'returns analytics structure' do
        analytics = service.get_analytics(knowledge_base.id)

        expect(analytics).to include(
          :total_queries,
          :successful_queries,
          :failed_queries,
          :document_count,
          :chunk_count
        )
      end

      it 'accepts custom period' do
        analytics = service.get_analytics(knowledge_base.id, period_days: 7)
        expect(analytics[:total_queries]).to be_a(Integer)
      end
    end
  end
end
