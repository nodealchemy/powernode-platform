# frozen_string_literal: true

FactoryBot.define do
  factory :devops_swarm_cluster, class: "Devops::SwarmCluster" do
    account
    sequence(:name) { |n| "swarm-cluster-#{n}" }
    sequence(:slug) { |n| "swarm-cluster-#{n}" }
    api_endpoint { "https://swarm.example.com:2377" }
    environment { "production" }
    status { "connected" }
    sync_interval_seconds { 60 }
  end
end
