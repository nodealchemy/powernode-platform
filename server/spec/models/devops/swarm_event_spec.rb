# frozen_string_literal: true

require 'rails_helper'

# Characterization spec for Devops::SwarmEvent (previously untested), added with
# the IMP-195e606d9747 refactor that moved the shared event behavior into
# Devops::AcknowledgeableEvent. Focuses on the swarm-specific parameterization of
# that concern: its own SOURCE_TYPES, the :cluster owner association, and the
# cluster_id surfaced in #event_details. The shared behavior is also exercised on
# the docker side by docker_event_spec (22 examples).
RSpec.describe Devops::SwarmEvent do
  let(:cluster) { create(:devops_swarm_cluster) }

  def build_event(**attrs)
    described_class.new({
      cluster: cluster, event_type: 'node_join', severity: 'info',
      source_type: 'node', message: 'node joined'
    }.merge(attrs))
  end

  describe 'validations (shared concern + swarm SOURCE_TYPES)' do
    it 'is valid with a swarm source type' do
      expect(build_event(source_type: 'service')).to be_valid
    end

    it 'rejects a docker-only source type (host)' do
      expect(build_event(source_type: 'host')).not_to be_valid
    end

    it 'validates severity inclusion via the shared concern' do
      expect(build_event(severity: 'bogus')).not_to be_valid
      expect(build_event(severity: 'critical')).to be_valid
    end

    it 'requires event_type and message (shared concern)' do
      expect(build_event(event_type: nil)).not_to be_valid
      expect(build_event(message: nil)).not_to be_valid
    end
  end

  describe 'shared concern behavior' do
    it '#acknowledge! records the acknowledger' do
      user = create(:user)
      event = build_event.tap(&:save!)
      event.acknowledge!(user)
      expect(event.acknowledged).to be true
      expect(event.acknowledged_by).to eq(user)
    end

    it '.critical scope filters by severity' do
      build_event(severity: 'critical').save!
      build_event(severity: 'info').save!
      expect(described_class.critical.count).to eq(1)
    end
  end

  describe '#event_details surfaces the cluster owner FK' do
    it 'includes cluster_id (not docker_host_id)' do
      event = build_event.tap(&:save!)
      details = event.event_details

      expect(details).to include(cluster_id: event.cluster_id)
      expect(details).not_to have_key(:docker_host_id)
      expect(details.keys).to include(:source_id, :metadata, :acknowledged_by, :acknowledged_at)
    end
  end
end
