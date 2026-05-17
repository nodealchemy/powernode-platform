# frozen_string_literal: true

# ClusterMemberPgReplicaSetupJob — async PG replication slot + credential
# materialization for a cluster_member spawn child.
#
# Enqueued by `System::SpawnPlatformService` when spawn_mode ==
# "cluster_member". POSTs to the server's worker_api endpoint which
# invokes `System::ClusterMember::PgReplicaSetupService#run!`.
#
# Idempotent on the server side: re-running for an already-prepared peer
# is a no-op. The default retry count is 3 so transient PG hiccups
# self-resolve without the operator intervening; persistent errors
# surface in the dashboard via FleetEvent.
#
# Plan reference: Decentralized Federation §H + P6.4.
class ClusterMemberPgReplicaSetupJob < BaseJob
  sidekiq_options queue: :system, retry: 3

  def execute(peer_id)
    log_info "[ClusterMemberPgReplicaSetupJob] starting setup peer_id=#{peer_id}"

    response = api_client.post(
      "/api/v1/system/worker_api/cluster_member/pg_replica_setup",
      { peer_id: peer_id }
    )

    if response["success"]
      data = response["data"] || {}
      log_info "[ClusterMemberPgReplicaSetupJob] setup ok " \
               "peer_id=#{peer_id} slot=#{data['slot_name']} " \
               "already_prepared=#{data['already_prepared']}"
      data
    else
      log_warn "[ClusterMemberPgReplicaSetupJob] setup API returned non-success: #{response.inspect}"
      { ok: false, error: response["error"] }
    end
  rescue StandardError => e
    log_error "[ClusterMemberPgReplicaSetupJob] setup failed peer_id=#{peer_id}", e
    raise
  end
end
