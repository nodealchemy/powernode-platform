# frozen_string_literal: true

FactoryBot.define do
  factory :devops_kubernetes_cluster, class: "Devops::KubernetesCluster" do
    association :account
    sequence(:name) { |n| "K8s Cluster #{n}" }
    sequence(:slug) { |n| "k8s-cluster-#{n}" }
    sequence(:api_endpoint) { |n| "https://k8s-#{n}.example.com:6443" }
    flavor { "k3s" }
    environment { "development" }
    status { "pending" }
    auto_sync { true }
    sync_interval_seconds { 60 }

    trait :active do
      status { "active" }
      k8s_version { "v1.30.4+k3s1" }
    end

    trait :degraded do
      status { "degraded" }
      consecutive_failures { 5 }
    end

    trait :kubeadm do
      flavor { "kubeadm" }
      sequence(:k8s_version) { |_n| "v1.30.4" }
    end

    # Phase O4 — CNI plugin traits. Default is `flannel` (set on the
    # base factory via the column default at insert time). The traits
    # let specs name the heavyweight path explicitly.
    trait :cni_flannel do
      cni_plugin { "flannel" }
    end

    trait :cni_ovn_kubernetes do
      cni_plugin { "ovn_kubernetes" }
    end

    trait :with_kubeconfig do
      encrypted_kubeconfig { SecureRandom.hex(64) }
      encrypted_server_token { SecureRandom.hex(32) }
      encrypted_agent_token { SecureRandom.hex(32) }
      encryption_key_id { SecureRandom.uuid }
    end
  end

  factory :devops_kubernetes_node, class: "Devops::KubernetesNode" do
    association :kubernetes_cluster, factory: :devops_kubernetes_cluster
    # node_instance must be supplied by the caller — depends on the
    # system extension factories which assemble account + node + template.
    sequence(:name) { |n| "k8s-node-#{n}" }
    role { "agent" }
    status { "pending" }

    trait :server do
      role { "server" }
    end

    trait :agent do
      role { "agent" }
    end

    trait :control_plane do
      role { "control_plane" }
    end

    trait :worker do
      role { "worker" }
    end

    trait :active do
      status { "active" }
      k8s_version { "v1.30.4+k3s1" }
      last_heartbeat_at { Time.current }
    end
  end
end
