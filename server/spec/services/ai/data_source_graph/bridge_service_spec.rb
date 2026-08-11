# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::DataSourceGraph::BridgeService, type: :service do
  let(:account) { create(:account) }
  subject(:service) { described_class.new(account) }

  # Keep the suite hermetic:
  #   - the model's after_commit would otherwise call the bridge (and thus the
  #     embedding backend) on every create/update that touches name/description/
  #     source_type/slug, so stub it out and drive the bridge explicitly.
  #   - stub the embedding backend so no outbound HTTP/model call is made; the
  #     deterministic 1536-dim vector mirrors the real pgvector dimension.
  before do
    allow_any_instance_of(Ai::DataSource).to receive(:sync_to_knowledge_graph)
    allow_any_instance_of(Ai::Memory::EmbeddingService)
      .to receive(:generate).and_return(Array.new(1536, 0.1))
  end

  # 019ff21c. index_ai_kg_nodes_on_ai_data_source_id was a PARTIAL index, not
  # UNIQUE, so multiple KG nodes for one data source were legal and unprevented —
  # which made the bare has_one return an ARBITRARY one of them, including to
  # #effectiveness_score's kg_confidence term.
  #
  # The invariant sync_data_source actually implements is at most ONE node per
  # data source TOTAL, not one per status: its revive branch flips an existing
  # node back to status "active" rather than creating a second, and it is the only
  # writer of ai_data_source_id on a node. The index now enforces exactly that,
  # which makes the association deterministic WITHOUT a scope — a status scope
  # here would send the revive path down the create branch and manufacture the
  # very duplicate this closes.
  describe "one KG node per data source (uniqueness)" do
    let(:data_source) { create(:ai_data_source, account: account, name: "Ledger API") }

    def node_for(ds, status: "active")
      Ai::KnowledgeGraphNode.create!(
        account: account, name: "n-#{SecureRandom.hex(4)}", node_type: "entity",
        entity_type: "data_source", status: status, confidence: 1.0,
        ai_data_source_id: ds.id
      )
    end

    it "refuses a second node for the same data source" do
      node_for(data_source)

      expect { node_for(data_source) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "refuses a second node even when the first is archived" do
      node_for(data_source, status: "archived")

      expect { node_for(data_source) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "still allows nodes that belong to no data source" do
      expect {
        2.times do
          Ai::KnowledgeGraphNode.create!(
            account: account, name: "plain-#{SecureRandom.hex(4)}", node_type: "entity",
            entity_type: "technology", status: "active", confidence: 1.0
          )
        end
      }.not_to raise_error
    end

    # The control the index must not break: an archived node is REVIVED, not
    # duplicated. This is the regression a status-scoped read would have caused.
    it "revives an archived node rather than creating a second" do
      existing = node_for(data_source, status: "archived")

      result = service.sync_data_source(data_source)

      expect(result).to eq(existing)
      expect(existing.reload.status).to eq("active")
      expect(Ai::KnowledgeGraphNode.where(ai_data_source_id: data_source.id).count).to eq(1)
    end
  end

  describe "#sync_data_source" do
    let(:data_source) do
      create(
        :ai_data_source,
        account: account,
        name: "Weather API",
        description: "Live weather observations",
        source_type: "open_meteo",
        protocol: "rest",
        auth_scheme: "none",
        health_status: "healthy"
      )
    end

    it "upserts a knowledge graph node linked to the data source" do
      node = service.sync_data_source(data_source)

      expect(node).to be_persisted
      expect(node.name).to eq("Weather API")
      expect(node.description).to eq("Live weather observations")
      expect(node.node_type).to eq("entity")
      expect(node.entity_type).to eq("data_source")
      expect(node.ai_data_source_id).to eq(data_source.id)
      expect(node.account).to eq(account)
      expect(node.status).to eq("active")
      expect(node.confidence).to eq(1.0)
    end

    it "is discoverable through the data_source scopes" do
      node = service.sync_data_source(data_source)

      expect(account.ai_knowledge_graph_nodes.data_source_nodes).to include(node)
      expect(account.ai_knowledge_graph_nodes.for_data_source(data_source.id)).to include(node)
    end

    it "stores data source properties on the node" do
      data_source.update_columns(effectiveness_score: 0.7, usage_count: 12)
      create(:ai_data_source_endpoint, data_source: data_source)

      node = service.sync_data_source(data_source.reload)

      props = node.properties
      expect(props["source_type"]).to eq("open_meteo")
      expect(props["protocol"]).to eq("rest")
      expect(props["auth_scheme"]).to eq("none")
      expect(props["health_status"]).to eq("healthy")
      expect(props["is_active"]).to be(true)
      expect(props["effectiveness_score"]).to eq(0.7)
      expect(props["usage_count"]).to eq(12)
      expect(props["endpoint_count"]).to eq(1)
    end

    it "generates an embedding for the node" do
      node = service.sync_data_source(data_source)
      expect(node.embedding).to be_present
    end

    context "on re-sync" do
      it "updates the existing node rather than creating a duplicate" do
        first_node = service.sync_data_source(data_source)

        # Mutate via update_columns so the (stubbed-out) after_commit guard is
        # irrelevant — we are asserting the bridge itself is idempotent.
        data_source.update_columns(name: "Weather API v2", description: "Updated")

        expect {
          second_node = service.sync_data_source(data_source.reload)
          expect(second_node.id).to eq(first_node.id)
          expect(second_node.name).to eq("Weather API v2")
          expect(second_node.description).to eq("Updated")
        }.not_to change(Ai::KnowledgeGraphNode, :count)
      end

      it "refreshes the embedding on re-sync" do
        node = service.sync_data_source(data_source)
        node.update_columns(embedding: nil)

        refreshed = service.sync_data_source(data_source.reload)
        expect(refreshed.embedding).to be_present
      end
    end

    context "without an embedding backend (graceful degradation)" do
      before do
        allow_any_instance_of(Ai::Memory::EmbeddingService)
          .to receive(:generate).and_return(nil)
      end

      it "still upserts the node with a nil embedding on initial sync" do
        node = nil
        expect { node = service.sync_data_source(data_source) }
          .to change(Ai::KnowledgeGraphNode, :count).by(1)

        expect(node).to be_persisted
        expect(node.entity_type).to eq("data_source")
        expect(node.ai_data_source_id).to eq(data_source.id)
        expect(node.embedding).to be_nil
      end

      it "does not clobber an existing embedding when re-sync yields no vector" do
        # First sync with a working backend so the node has an embedding.
        allow_any_instance_of(Ai::Memory::EmbeddingService)
          .to receive(:generate).and_return(Array.new(1536, 0.1))
        node = service.sync_data_source(data_source)
        expect(node.embedding).to be_present

        # Now the backend is unavailable; re-sync must not wipe the embedding.
        allow_any_instance_of(Ai::Memory::EmbeddingService)
          .to receive(:generate).and_return(nil)
        refreshed = service.sync_data_source(data_source.reload)
        expect(refreshed.id).to eq(node.id)
        expect(refreshed.embedding).to be_present
      end
    end

    it "returns nil and logs on error" do
      allow_any_instance_of(Ai::KnowledgeGraph::GraphService)
        .to receive(:create_node).and_raise(StandardError, "DB exploded")

      expect(Rails.logger)
        .to receive(:error).with(/DataSourceGraph::BridgeService\] sync_data_source failed/)

      expect(service.sync_data_source(data_source)).to be_nil
    end
  end

  describe "#build_embedding_text (private)" do
    let(:data_source) do
      create(
        :ai_data_source,
        account: account,
        name: "Weather API",
        description: "Live weather observations",
        source_type: "open_meteo"
      )
    end

    subject(:text) { service.send(:build_embedding_text, data_source) }

    it "includes the name" do
      expect(text).to include("Weather API")
    end

    it "includes the source_type labelled as category" do
      expect(text).to include("category: open_meteo")
    end

    it "includes endpoint names" do
      create(:ai_data_source_endpoint, data_source: data_source, name: "Current Conditions")
      create(:ai_data_source_endpoint, data_source: data_source, name: "Forecast")

      result = service.send(:build_embedding_text, data_source.reload)
      expect(result).to include("Current Conditions")
      expect(result).to include("Forecast")
    end

    it "omits the description segment when description is blank" do
      data_source.update_columns(description: nil)
      result = service.send(:build_embedding_text, data_source.reload)
      expect(result).to include("Weather API")
      expect(result).not_to include("Live weather observations")
    end
  end

  describe "#sync_all_data_sources" do
    before do
      create(:ai_data_source, account: account, name: "Source A", source_type: "open_meteo")
      create(:ai_data_source, account: account, name: "Source B", source_type: "fred")
      # Inactive source must be skipped (scope is .active).
      create(:ai_data_source, :inactive, account: account, name: "Source C")
      # Another account's source must not be picked up (scoped to current_account).
      create(:ai_data_source, account: create(:account), name: "Other Account Source")
    end

    it "counts only active sources for the current account as synced" do
      result = service.sync_all_data_sources

      expect(result).to eq(synced: 2, failed: 0)
    end

    it "tallies failures separately when a sync returns nil" do
      call_count = 0
      allow(service).to receive(:sync_data_source) do
        call_count += 1
        # Fail the second active source, succeed the first.
        call_count == 2 ? nil : instance_double(Ai::KnowledgeGraphNode)
      end

      result = service.sync_all_data_sources
      expect(result).to eq(synced: 1, failed: 1)
    end

    it "creates one node per active source" do
      expect { service.sync_all_data_sources }
        .to change { account.ai_knowledge_graph_nodes.data_source_nodes.count }.from(0).to(2)
    end
  end
end
