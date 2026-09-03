# frozen_string_literal: true

module Ai
  module Tools
    class PlatformApiToolRegistry
      TOOLS = {
        # System extension fleet (Golden Eclipse M5)
        # === Storage assignment ownership (fleet-wide identity model) ===
        "system_assign_storage_owner"               => "Ai::Tools::SystemStorageOwnerTool",
        "system_list_storage_assignments_by_owner"  => "Ai::Tools::SystemStorageOwnerTool",
        "system_storage_chown_status"               => "Ai::Tools::SystemStorageOwnerTool",
        "system_storage_chown_retry"                => "Ai::Tools::SystemStorageOwnerTool",

        # === Infrastructure blast-radius (RCP v2 campaign, increment P0-d) ===
        "system_blast_radius" => "Ai::Tools::SystemBlastRadiusTool",

        # === Ingress / service exposure (public + local /svc) / ACME provisioning ===
        "system_reverse_proxy_compose"      => "Ai::Tools::SystemIngressTool",
        "system_expose_service_publicly"    => "Ai::Tools::SystemIngressTool",
        "system_expose_service_local"       => "Ai::Tools::SystemIngressTool",
        "system_acme_provision_certificate" => "Ai::Tools::SystemIngressTool",
        # Sdwan::Service CRUD + local-exposure lifecycle (inline in the tool)
        "system_create_service"             => "Ai::Tools::SystemIngressTool",
        "system_list_services"              => "Ai::Tools::SystemIngressTool",
        "system_get_service"                => "Ai::Tools::SystemIngressTool",
        "system_update_service"             => "Ai::Tools::SystemIngressTool",
        "system_delete_service"             => "Ai::Tools::SystemIngressTool",
        "system_unexpose_service_local"     => "Ai::Tools::SystemIngressTool",
        # Path B (public TLS-carrying TCP) — sole owner of public_enabled, both directions
        "system_expose_service_public_tcp"   => "Ai::Tools::SystemIngressTool",
        "system_unexpose_service_public_tcp" => "Ai::Tools::SystemIngressTool",
        # APO-3d — declarative backend set + per-service load-balancer overrides (gated)
        "system_set_service_backends"        => "Ai::Tools::SystemIngressTool",

        # === ACME certificate lifecycle (DNS-01 issuance, renewal, revocation) ===
        "system_acme_get_certificate"       => "Ai::Tools::SystemAcmeTool",
        "system_acme_renew_certificate"     => "Ai::Tools::SystemAcmeTool",
        "system_acme_revoke_certificate"    => "Ai::Tools::SystemAcmeTool",
        "system_acme_create_dns_credential" => "Ai::Tools::SystemAcmeTool",

        "system_list_nodes" => "Ai::Tools::SystemFleetTool",
        "system_get_node" => "Ai::Tools::SystemFleetTool",
        "system_create_node" => "Ai::Tools::SystemFleetTool",
        "system_update_node" => "Ai::Tools::SystemFleetTool",
        "system_delete_node" => "Ai::Tools::SystemFleetTool",
        "system_delete_template" => "Ai::Tools::SystemFleetTool",
        "system_update_template" => "Ai::Tools::SystemFleetTool",
        "system_clone_template" => "Ai::Tools::SystemFleetTool",
        "system_create_module" => "Ai::Tools::SystemFleetTool",
        "system_update_module" => "Ai::Tools::SystemFleetTool",
        "system_unmark_module_canary" => "Ai::Tools::SystemFleetTool",
        "system_delete_module" => "Ai::Tools::SystemFleetTool",
        "system_refresh_instance_modules" => "Ai::Tools::SystemFleetTool",
        "system_list_instances" => "Ai::Tools::SystemFleetTool",
        "system_get_instance" => "Ai::Tools::SystemFleetTool",
        "system_find_node_with_gpu" => "Ai::Tools::SystemFleetTool",
        "system_list_instance_types_by_gpu" => "Ai::Tools::SystemFleetTool",
        "system_deploy_inference_server" => "Ai::Tools::SystemFleetTool",
        "system_grant_instance_mcp_tools" => "Ai::Tools::SystemFleetTool",
        "system_grant_instance_peer_skills" => "Ai::Tools::SystemFleetTool",
        "system_discover_peers" => "Ai::Tools::SystemFleetTool",
        "system_authorize_peer_call" => "Ai::Tools::SystemFleetTool",
        "system_launch_agent_fleet" => "Ai::Tools::SystemFleetTool",
        "system_agent_fleet_status" => "Ai::Tools::SystemFleetTool",
        "system_reap_agent_fleet" => "Ai::Tools::SystemFleetTool",
        "system_mint_peer_capability_token" => "Ai::Tools::SystemFleetTool",
        "system_list_isolation_tiers" => "Ai::Tools::SystemFleetTool",
        "system_provision_instance" => "Ai::Tools::SystemFleetTool",
        "system_terminate_instance" => "Ai::Tools::SystemFleetTool",
        # IMP-4e49eb79c5e0 — the disaster-recovery lane's two doors. Both are
        # approval-gated on the tool (declare_action), and both replay a skill
        # executor rather than the action body. Without these rows the
        # declarations are inert: BaseTool#execute is only reached because this
        # map routes the action name onto the serving class.
        "system_replace_instance" => "Ai::Tools::SystemFleetTool",
        "system_reap_instance" => "Ai::Tools::SystemFleetTool",
        "system_destroy_instance" => "Ai::Tools::SystemFleetTool",
        "system_start_instance" => "Ai::Tools::SystemFleetTool",
        "system_stop_instance" => "Ai::Tools::SystemFleetTool",
        "system_reboot_instance" => "Ai::Tools::SystemFleetTool",
        "system_upgrade_boot_image" => "Ai::Tools::SystemFleetTool",
        # IMP-b2f80e6d1c65 — operator ops hold (2026-07-27 incident response):
        # had ACTION_PERMISSIONS + dispatch but no registry key, so it was
        # reachable only by smuggling the action into another tool's name.
        "system_instance_hold" => "Ai::Tools::SystemFleetTool",
        "system_instance_hold_status" => "Ai::Tools::SystemFleetTool",
        "system_instance_release_hold" => "Ai::Tools::SystemFleetTool",
        "system_list_providers"     => "Ai::Tools::SystemFleetTool",
        "system_get_provider"       => "Ai::Tools::SystemFleetTool",
        "system_update_provider"    => "Ai::Tools::SystemFleetTool",
        "system_create_provider"    => "Ai::Tools::SystemFleetTool",
        "system_delete_provider"    => "Ai::Tools::SystemFleetTool",
        # F4-07 — complete the provisionable chain (provider + connection +
        # region + instance type) for agent self-serve substrate onboarding.
        "system_create_provider_connection"    => "Ai::Tools::SystemFleetTool",
        "system_create_provider_region"        => "Ai::Tools::SystemFleetTool",
        "system_create_provider_instance_type" => "Ai::Tools::SystemFleetTool",
        "system_recycle_pool"       => "Ai::Tools::SystemFleetTool",

        # === Package repository management (apt/rpm catalog) ===
        "system_list_package_repositories"    => "Ai::Tools::SystemPackageRepositoryTool",
        "system_get_package_repository"       => "Ai::Tools::SystemPackageRepositoryTool",
        "system_create_package_repository"    => "Ai::Tools::SystemPackageRepositoryTool",
        "system_update_package_repository"    => "Ai::Tools::SystemPackageRepositoryTool",
        "system_delete_package_repository"    => "Ai::Tools::SystemPackageRepositoryTool",
        "system_sync_package_repository"      => "Ai::Tools::SystemPackageRepositoryTool",
        "system_link_repository_platform"     => "Ai::Tools::SystemPackageRepositoryTool",
        "system_unlink_repository_platform"   => "Ai::Tools::SystemPackageRepositoryTool",
        "system_search_packages"              => "Ai::Tools::SystemPackageRepositoryTool",
        "system_discover_packages"            => "Ai::Tools::SystemPackageRepositoryTool",
        "system_get_package"                  => "Ai::Tools::SystemPackageRepositoryTool",
        "system_resolve_package_dependencies" => "Ai::Tools::SystemPackageRepositoryTool",
        "system_create_module_from_package"   => "Ai::Tools::SystemPackageRepositoryTool",
        "system_list_package_module_links"    => "Ai::Tools::SystemPackageRepositoryTool",
        "system_refresh_package_module"       => "Ai::Tools::SystemPackageRepositoryTool",
        "system_suggest_architectures_for_fleet" => "Ai::Tools::SystemPackageRepositoryTool",

        # === Architecture catalog (platform-wide CPU arches + AI parity) ===
        "system_list_architectures"    => "Ai::Tools::SystemArchitectureCatalogTool",
        "system_get_architecture"      => "Ai::Tools::SystemArchitectureCatalogTool",
        "system_create_architecture"   => "Ai::Tools::SystemArchitectureCatalogTool",
        "system_update_architecture"   => "Ai::Tools::SystemArchitectureCatalogTool",
        "system_delete_architecture"   => "Ai::Tools::SystemArchitectureCatalogTool",
        "system_propose_architecture"  => "Ai::Tools::SystemArchitectureCatalogTool",

        "system_list_templates" => "Ai::Tools::SystemFleetTool",
        "system_get_template" => "Ai::Tools::SystemFleetTool",
        "system_create_template" => "Ai::Tools::SystemFleetTool",
        "system_update_instance" => "Ai::Tools::SystemFleetTool",
        "system_assign_module_to_template" => "Ai::Tools::SystemFleetTool",
        "system_update_template_module" => "Ai::Tools::SystemFleetTool",
        "system_compose_preview_template" => "Ai::Tools::SystemFleetTool",
        "system_list_modules" => "Ai::Tools::SystemFleetTool",
        "system_get_module" => "Ai::Tools::SystemFleetTool",
        "system_list_module_versions" => "Ai::Tools::SystemFleetTool",
        # Semantic catalog discovery — the reuse-first gate over modules/templates
        "system_discover_modules" => "Ai::Tools::SystemFleetTool",
        "system_discover_templates" => "Ai::Tools::SystemFleetTool",
        "system_promote_module_version" => "Ai::Tools::SystemFleetTool",
        "system_drift_report" => "Ai::Tools::SystemFleetTool",
        # Fleet observability & runbooks
        "system_module_diff" => "Ai::Tools::SystemFleetTool",
        # IMP-b2f80e6d1c65 — same "declared but unroutable" gap as the ops
        # hold above, from the same 2026-07-27 incident response commits.
        "system_module_publish_target" => "Ai::Tools::SystemFleetTool",
        "system_module_publication_integrity" => "Ai::Tools::SystemFleetTool",
        "system_compliance_snapshot" => "Ai::Tools::SystemFleetTool",
        "system_runbook_generate" => "Ai::Tools::SystemFleetTool",
        "system_cve_runbook_generate" => "Ai::Tools::SystemFleetTool",
        "system_cve_triage" => "Ai::Tools::SystemFleetTool",
        "system_recent_signals" => "Ai::Tools::SystemFleetTool",
        "system_attribute_failure" => "Ai::Tools::SystemFleetTool",
        "system_inspect_correlation" => "Ai::Tools::SystemFleetTool",
        "system_list_tasks" => "Ai::Tools::SystemFleetTool",
        "system_get_task" => "Ai::Tools::SystemFleetTool",
        "system_cancel_task" => "Ai::Tools::SystemFleetTool",
        "system_abort_task" => "Ai::Tools::SystemFleetTool",
        # Slice 7 — instance pools
        "system_list_instance_pools" => "Ai::Tools::SystemFleetTool",
        "system_get_instance_pool" => "Ai::Tools::SystemFleetTool",
        "system_create_instance_pool" => "Ai::Tools::SystemFleetTool",
        "system_update_instance_pool" => "Ai::Tools::SystemFleetTool",
        "system_drain_instance_pool" => "Ai::Tools::SystemFleetTool",
        "system_acquire_pooled_instance" => "Ai::Tools::SystemFleetTool",
        "system_replenish_instance_pool" => "Ai::Tools::SystemFleetTool",
        # Gap remediation slice 1 — operator-runbook-driven actions
        "system_drain_instance" => "Ai::Tools::SystemFleetTool",
        # IMP-0467eee9fc57 — cordon-only (unschedulable) mode, the reversible
        # half of the drain; both directions approval-gated in the tool.
        "system_cordon_instance" => "Ai::Tools::SystemFleetTool",
        "system_uncordon_instance" => "Ai::Tools::SystemFleetTool",
        "system_get_silent_instances" => "Ai::Tools::SystemFleetTool",
        # IMP-ca485128072e (APO-2e) — operator-tunable fleet sensor thresholds.
        "system_get_sensor_config" => "Ai::Tools::SystemFleetTool",
        "system_update_sensor_config" => "Ai::Tools::SystemFleetTool",
        "system_validate_module_manifest" => "Ai::Tools::SystemFleetTool",
        # Gap remediation slice 2 — CVE catalog + module assignment cleanup
        "system_get_cve" => "Ai::Tools::SystemFleetTool",
        "system_get_cve_exposure" => "Ai::Tools::SystemFleetTool",
        "system_create_cve" => "Ai::Tools::SystemFleetTool",
        "system_delete_cve" => "Ai::Tools::SystemFleetTool",
        "system_unassign_module_from_template" => "Ai::Tools::SystemFleetTool",
        "system_update_module_assignment" => "Ai::Tools::SystemFleetTool",
        # Gap remediation slice 3 — pool ops + canary marking
        "system_return_pooled_instance" => "Ai::Tools::SystemFleetTool",
        "system_delete_instance_pool" => "Ai::Tools::SystemFleetTool",
        "system_module_mark_canary" => "Ai::Tools::SystemFleetTool",
        # Platform deployment + storage volume MCP surface (D1.2 + MCP.1 + MCP.2)
        "system_deploy_platform" => "Ai::Tools::SystemFleetTool",
        "system_list_volumes" => "Ai::Tools::SystemFleetTool",
        "system_get_volume" => "Ai::Tools::SystemFleetTool",
        "system_create_volume" => "Ai::Tools::SystemFleetTool",
        "system_update_volume" => "Ai::Tools::SystemFleetTool",
        "system_delete_volume" => "Ai::Tools::SystemFleetTool",
        "system_attach_volume" => "Ai::Tools::SystemFleetTool",
        "system_detach_volume" => "Ai::Tools::SystemFleetTool",
        "system_test_nfs_export" => "Ai::Tools::SystemFleetTool",
        # Volume snapshots / restore (APO-5 / DR-2) — project data protection
        "system_snapshot_volume" => "Ai::Tools::SystemFleetTool",
        "system_list_volume_snapshots" => "Ai::Tools::SystemFleetTool",
        "system_delete_volume_snapshot" => "Ai::Tools::SystemFleetTool",
        "system_restore_volume_snapshot" => "Ai::Tools::SystemFleetTool",
        "system_get_storage_recommendations" => "Ai::Tools::SystemFleetTool",
        "system_update_storage_recommendations" => "Ai::Tools::SystemFleetTool",
        "system_migrate_storage_component" => "Ai::Tools::SystemFleetTool",
        "system_list_storage_migrations" => "Ai::Tools::SystemFleetTool",
        "system_get_storage_migration" => "Ai::Tools::SystemFleetTool",
        "system_approve_storage_migration" => "Ai::Tools::SystemFleetTool",
        "system_cancel_storage_migration" => "Ai::Tools::SystemFleetTool",
        "system_report_storage_migration_progress" => "Ai::Tools::SystemFleetTool",
        # Increment 9 (campaign 019f3458) — revert_binding! (R) / cleanup (C)
        "system_revert_storage_migration_binding" => "Ai::Tools::SystemFleetTool",
        "system_cleanup_storage_migration"        => "Ai::Tools::SystemFleetTool",
        "system_platform_maintenance" => "Ai::Tools::SystemFleetTool",
        "system_platform_resilience" => "Ai::Tools::SystemFleetTool",
        # Gap remediation slice 5 — disk image CI
        "system_list_disk_image_publications" => "Ai::Tools::SystemFleetTool",
        "system_set_default_disk_image_publication" => "Ai::Tools::SystemFleetTool",
        "system_revert_disk_image" => "Ai::Tools::SystemFleetTool",
        "system_set_disk_image_retention" => "Ai::Tools::SystemFleetTool",
        "system_provision_ci_worker" => "Ai::Tools::SystemFleetTool",
        "system_terminate_ci_worker" => "Ai::Tools::SystemFleetTool",
        "system_list_ci_workers" => "Ai::Tools::SystemFleetTool",
        "system_lease_ci_runner" => "Ai::Tools::SystemFleetTool",
        "system_release_ci_runner" => "Ai::Tools::SystemFleetTool",
        "system_list_ci_runner_leases" => "Ai::Tools::SystemFleetTool",
        "system_list_disk_image_webhooks" => "Ai::Tools::SystemFleetTool",
        # Campaign 019f5885 inc9 — native module-build batch orchestration
        "system_dispatch_module_build_batch" => "Ai::Tools::SystemFleetTool",
        "system_cancel_module_build_batch" => "Ai::Tools::SystemFleetTool",
        "system_rollback_module_version" => "Ai::Tools::SystemFleetTool",
        # Missing-features slice 6a — GitOps reconciler MCP surface
        "system_gitops_register_repository" => "Ai::Tools::SystemFleetTool",
        "system_gitops_sync_repository" => "Ai::Tools::SystemFleetTool",
        "system_gitops_get_sync_run" => "Ai::Tools::SystemFleetTool",
        "system_gitops_get_drift_report" => "Ai::Tools::SystemFleetTool",
        # IMP-f07be27ba0b0 — the read half: nothing in the family above returns
        # a repository, so its projection was reachable only on the create.
        "system_gitops_list_repositories" => "Ai::Tools::SystemFleetTool",
        "system_gitops_get_repository" => "Ai::Tools::SystemFleetTool",
        # Missing-features slice Vault DR-3 — pepper rotation
        "system_rotate_vault_transit_pepper" => "Ai::Tools::SystemFleetTool",
        # Missing-features slice 6b — GitOps apply path
        "system_gitops_apply_proposal" => "Ai::Tools::SystemFleetTool",
        # SDWAN overlay (Slice 1 of we-are-continuing-development-spicy-bear.md)
        "system_sdwan_list_networks"   => "Ai::Tools::SdwanTool",
        "system_sdwan_get_network"     => "Ai::Tools::SdwanTool",
        "system_sdwan_create_network"  => "Ai::Tools::SdwanTool",
        "system_sdwan_update_network"  => "Ai::Tools::SdwanTool",
        "system_sdwan_delete_network"  => "Ai::Tools::SdwanTool",
        "system_sdwan_list_peers"      => "Ai::Tools::SdwanTool",
        "system_sdwan_get_peer"        => "Ai::Tools::SdwanTool",
        "system_sdwan_set_peer_tags"   => "Ai::Tools::SdwanTool",
        "system_sdwan_attach_peer"     => "Ai::Tools::SdwanTool",
        "system_sdwan_update_peer"     => "Ai::Tools::SdwanTool",
        "system_sdwan_detach_peer"     => "Ai::Tools::SdwanTool",
        "system_sdwan_get_topology"    => "Ai::Tools::SdwanTool",
        # Slice 2: firewall
        "system_sdwan_list_firewall_rules"  => "Ai::Tools::SdwanTool",
        "system_sdwan_get_firewall_rule"    => "Ai::Tools::SdwanTool",
        "system_sdwan_create_firewall_rule" => "Ai::Tools::SdwanTool",
        "system_sdwan_update_firewall_rule" => "Ai::Tools::SdwanTool",
        "system_sdwan_delete_firewall_rule" => "Ai::Tools::SdwanTool",
        # Slice 4: user VPN
        "system_sdwan_list_access_grants"   => "Ai::Tools::SdwanTool",
        "system_sdwan_create_access_grant"  => "Ai::Tools::SdwanTool",
        "system_sdwan_revoke_access_grant"  => "Ai::Tools::SdwanTool",
        "system_sdwan_list_user_devices"    => "Ai::Tools::SdwanTool",
        "system_sdwan_issue_user_device"    => "Ai::Tools::SdwanTool",
        "system_sdwan_revoke_user_device"   => "Ai::Tools::SdwanTool",
        # Slice 6: federation
        "system_sdwan_list_federation_peers"   => "Ai::Tools::SdwanTool",
        "system_sdwan_get_federation_peer"     => "Ai::Tools::SdwanTool",
        "system_sdwan_propose_federation_peer" => "Ai::Tools::SdwanTool",
        "system_sdwan_accept_federation_peer"  => "Ai::Tools::SdwanTool",
        "system_sdwan_update_federation_peer"  => "Ai::Tools::SdwanTool",
        "system_sdwan_revoke_federation_peer"  => "Ai::Tools::SdwanTool",
        "system_sdwan_federation_scan"         => "Ai::Tools::SdwanTool",
        "system_sdwan_set_data_residency"      => "Ai::Tools::SdwanTool",
        "system_sdwan_get_audit_log"           => "Ai::Tools::SdwanTool",
        # Phase 3 (Federation & Multi-Site) — SDWAN-first composer skills
        "system_sdwan_federation_compose"      => "Ai::Tools::SdwanTool",
        "system_multi_tenant_isolation"        => "Ai::Tools::SdwanTool",
        "system_service_discovery_compose"     => "Ai::Tools::SdwanTool",
        # Slice 9a: routing layer (static subnet routing)
        "system_sdwan_update_peer_lan_subnets"        => "Ai::Tools::SdwanTool",
        "system_sdwan_update_network_routing_mode"    => "Ai::Tools::SdwanTool",
        "system_sdwan_list_subnet_advertisements"  => "Ai::Tools::SdwanTool",
        "system_sdwan_get_routing_summary"         => "Ai::Tools::SdwanTool",
        # Slice 9b: virtual IPs
        "system_sdwan_create_virtual_ip"           => "Ai::Tools::SdwanTool",
        "system_sdwan_list_virtual_ips"            => "Ai::Tools::SdwanTool",
        "system_sdwan_get_virtual_ip"              => "Ai::Tools::SdwanTool",
        "system_sdwan_update_virtual_ip"           => "Ai::Tools::SdwanTool",
        "system_sdwan_delete_virtual_ip"           => "Ai::Tools::SdwanTool",
        "system_sdwan_failover_virtual_ip"         => "Ai::Tools::SdwanTool",
        "system_sdwan_list_vip_assignments"        => "Ai::Tools::SdwanTool",
        # Slice 9c: iBGP / FRR control plane
        "system_sdwan_get_account_bgp"             => "Ai::Tools::SdwanTool",
        "system_sdwan_update_account_as_number"       => "Ai::Tools::SdwanTool",
        "system_sdwan_get_bgp_sessions"            => "Ai::Tools::SdwanTool",
        "system_sdwan_get_bgp_config_for_peer"     => "Ai::Tools::SdwanTool",
        # Slice 9e: route policies
        "system_sdwan_list_route_policies"         => "Ai::Tools::SdwanTool",
        "system_sdwan_get_route_policy"            => "Ai::Tools::SdwanTool",
        "system_sdwan_create_route_policy"         => "Ai::Tools::SdwanTool",
        "system_sdwan_update_route_policy"         => "Ai::Tools::SdwanTool",
        "system_sdwan_delete_route_policy"         => "Ai::Tools::SdwanTool",
        "system_sdwan_compile_route_policy"        => "Ai::Tools::SdwanTool",
        # Slice 7b: hub port mappings
        "system_sdwan_list_port_mappings"          => "Ai::Tools::SdwanTool",
        "system_sdwan_get_port_mapping"            => "Ai::Tools::SdwanTool",
        "system_sdwan_create_port_mapping"         => "Ai::Tools::SdwanTool",
        "system_sdwan_update_port_mapping"         => "Ai::Tools::SdwanTool",
        "system_sdwan_delete_port_mapping"         => "Ai::Tools::SdwanTool",
        # Phase O6: host bridges (O1) + OVN deployment/switches/ports (O3) + IPFIX (O5)
        "system_sdwan_create_host_bridge"              => "Ai::Tools::SdwanTool",
        "system_sdwan_list_host_bridges"               => "Ai::Tools::SdwanTool",
        "system_sdwan_get_host_bridge"                 => "Ai::Tools::SdwanTool",
        "system_sdwan_activate_host_bridge"            => "Ai::Tools::SdwanTool",
        "system_sdwan_release_host_bridge"             => "Ai::Tools::SdwanTool",
        "system_sdwan_create_ovn_deployment"           => "Ai::Tools::SdwanTool",
        "system_sdwan_create_ovn_logical_switch"       => "Ai::Tools::SdwanTool",
        "system_sdwan_create_ovn_logical_switch_port"  => "Ai::Tools::SdwanTool",
        "system_sdwan_activate_ovn_logical_switch"      => "Ai::Tools::SdwanTool",
        "system_sdwan_activate_ovn_logical_switch_port" => "Ai::Tools::SdwanTool",
        "system_sdwan_compile_ovn_plan"                => "Ai::Tools::SdwanTool",
        "system_sdwan_create_ipfix_collector"          => "Ai::Tools::SdwanTool",
        "system_sdwan_list_ipfix_collectors"           => "Ai::Tools::SdwanTool",
        "system_sdwan_create_ovn_acl"                  => "Ai::Tools::SdwanTool",
        "system_sdwan_list_ovn_acls"                   => "Ai::Tools::SdwanTool",
        "system_sdwan_delete_ovn_acl"                  => "Ai::Tools::SdwanTool",
        "system_sdwan_delete_ovn_logical_switch"       => "Ai::Tools::SdwanTool",
        "system_sdwan_delete_ovn_deployment"           => "Ai::Tools::SdwanTool",
        "system_sdwan_list_ovn_deployments"            => "Ai::Tools::SdwanTool",
        "system_sdwan_get_ovn_deployment"              => "Ai::Tools::SdwanTool",
        "system_sdwan_list_ovn_logical_switches"       => "Ai::Tools::SdwanTool",
        "system_sdwan_delete_ovn_logical_switch_port"  => "Ai::Tools::SdwanTool",
        "system_sdwan_delete_ipfix_collector"          => "Ai::Tools::SdwanTool",
        # IMP-6bbe5c673c38 — the state toggle and the single-row read that
        # closed the IPFIX collector verb split. Without the toggle the only
        # agent-reachable way to stop a collector exporting was the delete
        # above, which cascades the collector's flow samples.
        "system_sdwan_get_ipfix_collector"             => "Ai::Tools::SdwanTool",
        "system_sdwan_update_ipfix_collector"          => "Ai::Tools::SdwanTool",
        # Phase B: Docker daemon auto-provisioning on NodeInstances.
        # Distinct from the docker_* family below — those tools manage
        # *external*, operator-registered hosts; these manage *managed*
        # hosts whose lifecycle is bound to a System::NodeInstance.
        "system_provision_docker_runtime"          => "Ai::Tools::DockerProvisioningTool",
        "system_decommission_docker_runtime"       => "Ai::Tools::DockerProvisioningTool",
        "system_mark_docker_ready"                 => "Ai::Tools::DockerProvisioningTool",
        "system_list_managed_docker_hosts"         => "Ai::Tools::DockerProvisioningTool",
        # Phase 2: Kubernetes (K3s today, kubeadm in Phase 3).
        # Cluster *creation* is implicit via module assignment +
        # agent-driven bootstrap — there is no kubernetes_create_cluster
        # action. The MCP surface is read + decommission + kubeconfig.
        "kubernetes_list_clusters"                 => "Ai::Tools::KubernetesClusterTool",
        "kubernetes_get_cluster"                   => "Ai::Tools::KubernetesClusterTool",
        "kubernetes_list_nodes"                    => "Ai::Tools::KubernetesClusterTool",
        "kubernetes_decommission_cluster"          => "Ai::Tools::KubernetesProvisioningTool",
        "kubernetes_get_kubeconfig"                => "Ai::Tools::KubernetesProvisioningTool",
        # AI-driven provisioning (Golden Eclipse M0) — natural-language conversation
        # surface that drives capture → compose → approve → execute → adapt
        # via the three Ai::Provisioning::* services + system_provisioning mission template.
        "platform_provisioning_capture_brief" => "Ai::Tools::ProvisioningTool",
        "platform_provisioning_compose_plan"  => "Ai::Tools::ProvisioningTool",
        "platform_provisioning_approve_plan"  => "Ai::Tools::ProvisioningTool",
        "platform_provisioning_status"        => "Ai::Tools::ProvisioningTool",
        "platform_provisioning_adapt"         => "Ai::Tools::ProvisioningTool",
        # Project & CI/CD
        "create_gitea_repository" => "Ai::Tools::ProjectInitTool",
        "update_gitea_repository" => "Ai::Tools::RepoManagementTool",
        "dispatch_to_runner" => "Ai::Tools::RunnerDispatchTool",
        # Gitea Actions: secrets management + workflow_dispatch + run monitoring.
        # Plan: docs/plans/wondrous-yawning-anchor.md (Phase 2 — operator-driven CI).
        "list_git_runners"               => "Ai::Tools::GitRunnerInventoryTool",
        "prune_stale_git_runners"        => "Ai::Tools::GitRunnerInventoryTool",
        "set_gitea_action_secret"        => "Ai::Tools::GiteaActionsTool",
        "set_gitea_action_secrets_bulk"  => "Ai::Tools::GiteaActionsTool",
        "list_gitea_action_secrets"      => "Ai::Tools::GiteaActionsTool",
        "delete_gitea_action_secret"     => "Ai::Tools::GiteaActionsTool",
        "dispatch_gitea_workflow"        => "Ai::Tools::GiteaActionsTool",
        "list_gitea_workflows"           => "Ai::Tools::GiteaActionsTool",
        "list_gitea_workflow_runs"       => "Ai::Tools::GiteaActionsTool",
        "get_gitea_workflow_run"         => "Ai::Tools::GiteaActionsTool",
        "get_gitea_job_logs"             => "Ai::Tools::GiteaActionsTool",
        "cancel_gitea_workflow_run"      => "Ai::Tools::GiteaActionsTool",
        "delete_gitea_workflow_run"      => "Ai::Tools::GiteaActionsTool",
        "rerun_gitea_workflow"           => "Ai::Tools::GiteaActionsTool",
        "rerun_gitea_workflow_failed_jobs" => "Ai::Tools::GiteaActionsTool",
        "rerun_gitea_job"                => "Ai::Tools::GiteaActionsTool",
        "list_gitea_run_artifacts"       => "Ai::Tools::GiteaActionsTool",
        "create_gitea_user_token"        => "Ai::Tools::GiteaActionsTool",
        "list_gitea_user_tokens"         => "Ai::Tools::GiteaActionsTool",
        "delete_gitea_user_token"        => "Ai::Tools::GiteaActionsTool",
        # Platform-side disk-image operator wrappers (one MCP call =
        # one operator-meaningful step). Plan: docs/plans/wondrous-yawning-anchor.md.
        "provision_disk_image_webhook"   => "Ai::Tools::DiskImageOperatorTool",
        "provision_ci_worker"            => "Ai::Tools::DiskImageOperatorTool",
        "bootstrap_disk_image_ci"        => "Ai::Tools::DiskImageOperatorTool",
        # Container deployment & management
        "deploy_container_agent" => "Ai::Tools::ContainerDeploymentTool",
        "agent_container_status" => "Ai::Tools::ContainerStatusTool",
        "agent_container_logs" => "Ai::Tools::ContainerLogsTool",
        "agent_container_terminate" => "Ai::Tools::ContainerTerminateTool",
        # Integration health
        "integration_health" => "Ai::Tools::IntegrationHealthTool",
        # Tool catalog detail (IMP-7e84ae0ccc91): tools/list is one line per
        # tool; this returns the full entry on demand.
        "describe_tool" => "Ai::Tools::ToolCatalogTool",
        # Ralph Loop management (autonomous agent duty cycles)
        "list_ralph_loops" => "Ai::Tools::RalphLoopTool",
        "get_ralph_loop" => "Ai::Tools::RalphLoopTool",
        "pause_ralph_loop" => "Ai::Tools::RalphLoopTool",
        "resume_ralph_loop" => "Ai::Tools::RalphLoopTool",
        "update_ralph_loop" => "Ai::Tools::RalphLoopTool",
        "delete_ralph_loop" => "Ai::Tools::RalphLoopTool",
        "get_ralph_loop_statistics" => "Ai::Tools::RalphLoopTool",
        "reopen_ralph_loop" => "Ai::Tools::RalphLoopTool",
        # Dev-loop executor bridge (pull-based task queue for Claude Code / platform executors)
        "dev_next_task" => "Ai::Tools::DevLoopTool",
        "dev_complete_task" => "Ai::Tools::DevLoopTool",
        "dev_list_tasks" => "Ai::Tools::DevLoopTool",
        "dev_update_task" => "Ai::Tools::DevLoopTool",
        "delegate_ralph_task" => "Ai::Tools::DevLoopTool",
        # Autonomous Improvement Campaigns: a durable wrapper that drives the dev-improve loop
        "campaign_propose" => "Ai::Tools::CampaignTool",
        "campaign_list_proposals" => "Ai::Tools::CampaignTool",
        "campaign_update_proposal" => "Ai::Tools::CampaignTool",
        "campaign_approve_proposal" => "Ai::Tools::CampaignTool",
        "campaign_reject_proposal" => "Ai::Tools::CampaignTool",
        "campaign_delegate" => "Ai::Tools::CampaignTool",
        "campaign_start" => "Ai::Tools::CampaignTool",
        "campaign_list" => "Ai::Tools::CampaignTool",
        "campaign_status" => "Ai::Tools::CampaignTool",
        "campaign_claim" => "Ai::Tools::CampaignTool",
        "campaign_release" => "Ai::Tools::CampaignTool",
        "campaign_answer_question" => "Ai::Tools::CampaignTool",
        "campaign_record_increment" => "Ai::Tools::CampaignTool",
        "campaign_check_rebase" => "Ai::Tools::CampaignTool",
        "campaign_stop" => "Ai::Tools::CampaignTool",
        # Progressive delivery (Ai::Delivery on Ai::Deploy) — deliver a ref via a strategy
        "deliver" => "Ai::Tools::DeliveryTool",
        "delivery_status" => "Ai::Tools::DeliveryTool",
        "delivery_list" => "Ai::Tools::DeliveryTool",
        # Improvement-discovery loop (Tier-1): offer -> approve -> dev-improve task
        "discover_improvements" => "Ai::Tools::ImprovementTool",
        "create_improvement" => "Ai::Tools::ImprovementTool",
        "list_improvements" => "Ai::Tools::ImprovementTool",
        "approve_improvement" => "Ai::Tools::ImprovementTool",
        "dismiss_improvement" => "Ai::Tools::ImprovementTool",
        "revert_improvement" => "Ai::Tools::ImprovementTool",
        "enable_autonomy" => "Ai::Tools::ImprovementTool",
        "disable_autonomy" => "Ai::Tools::ImprovementTool",
        "scoreboard" => "Ai::Tools::ImprovementTool",
        # Cross-plane federation (invoke a tool on a peer deployment)
        "federation_invoke_tool" => "Ai::Tools::FederationTool",
        "federation_list_partners" => "Ai::Tools::FederationTool",
        # Agent management
        "create_agent" => "Ai::Tools::AgentManagementTool",
        "list_agents" => "Ai::Tools::AgentManagementTool",
        "execute_agent" => "Ai::Tools::AgentManagementTool",
        "get_agent" => "Ai::Tools::AgentManagementTool",
        "update_agent" => "Ai::Tools::AgentManagementTool",
        "set_agent_autonomy_level" => "Ai::Tools::AgentManagementTool",
        "update_agent_trust_score" => "Ai::Tools::AgentManagementTool",
        "delete_agent" => "Ai::Tools::AgentManagementTool",
        "spawn_task" => "Ai::Tools::AgentManagementTool",
        "check_task_status" => "Ai::Tools::AgentManagementTool",
        "wait_for_task" => "Ai::Tools::AgentManagementTool",
        # Team management
        "create_team" => "Ai::Tools::TeamManagementTool",
        "add_team_member" => "Ai::Tools::TeamManagementTool",
        "remove_team_member" => "Ai::Tools::TeamManagementTool",
        "execute_team" => "Ai::Tools::TeamManagementTool",
        "get_team" => "Ai::Tools::TeamManagementTool",
        "list_teams" => "Ai::Tools::TeamManagementTool",
        "update_team" => "Ai::Tools::TeamManagementTool",
        "delete_team" => "Ai::Tools::TeamManagementTool",
        # Pipeline management
        "trigger_pipeline" => "Ai::Tools::PipelineManagementTool",
        "list_pipelines" => "Ai::Tools::PipelineManagementTool",
        "get_pipeline_status" => "Ai::Tools::PipelineManagementTool",
        # Memory management
        "write_shared_memory" => "Ai::Tools::MemoryTool",
        "read_shared_memory" => "Ai::Tools::MemoryTool",
        "delete_shared_memory" => "Ai::Tools::MemoryTool",
        "search_memory" => "Ai::Tools::MemoryTool",
        "consolidate_memory" => "Ai::Tools::MemoryTool",
        "memory_stats" => "Ai::Tools::MemoryTool",
        "list_pools" => "Ai::Tools::MemoryTool",
        "create_memory_pool" => "Ai::Tools::MemoryTool",
        "delete_memory_pool" => "Ai::Tools::MemoryTool",
        # Agent-managed memory (MemGPT-style)
        "agent_remember" => "Ai::Tools::AgentMemoryManagementTool",
        "agent_forget" => "Ai::Tools::AgentMemoryManagementTool",
        "agent_reflect" => "Ai::Tools::AgentMemoryManagementTool",
        "agent_recall" => "Ai::Tools::AgentMemoryManagementTool",
        # Knowledge & RAG
        "query_knowledge_base" => "Ai::Tools::KnowledgeTool",
        "list_knowledge_bases" => "Ai::Tools::RagManagementTool",
        "create_knowledge_base" => "Ai::Tools::RagManagementTool",
        "add_document" => "Ai::Tools::RagManagementTool",
        "process_document" => "Ai::Tools::RagManagementTool",
        "search_documents" => "Ai::Tools::RagManagementTool",
        "delete_document" => "Ai::Tools::RagManagementTool",
        "get_api_reference" => "Ai::Tools::ApiReferenceTool",
        # KB Article management
        "list_kb_articles" => "Ai::Tools::KbArticleManagementTool",
        "get_kb_article" => "Ai::Tools::KbArticleManagementTool",
        "create_kb_article" => "Ai::Tools::KbArticleManagementTool",
        "update_kb_article" => "Ai::Tools::KbArticleManagementTool",
        # Page management
        "list_pages" => "Ai::Tools::PageManagementTool",
        "get_page" => "Ai::Tools::PageManagementTool",
        "create_page" => "Ai::Tools::PageManagementTool",
        "update_page" => "Ai::Tools::PageManagementTool",
        # Compound learning
        "query_learnings" => "Ai::Tools::LearningTool",
        "reinforce_learning" => "Ai::Tools::LearningTool",
        "learning_metrics" => "Ai::Tools::LearningTool",
        "create_learning" => "Ai::Tools::LearningTool",
        # Shared knowledge
        "search_knowledge" => "Ai::Tools::SharedKnowledgeTool",
        "create_knowledge" => "Ai::Tools::SharedKnowledgeTool",
        "update_knowledge" => "Ai::Tools::SharedKnowledgeTool",
        "promote_knowledge" => "Ai::Tools::SharedKnowledgeTool",
        "delete_knowledge" => "Ai::Tools::SharedKnowledgeTool",
        # Skills
        "list_skills" => "Ai::Tools::SkillTool",
        "get_skill" => "Ai::Tools::SkillTool",
        "discover_skills" => "Ai::Tools::SkillTool",
        "get_skill_context" => "Ai::Tools::SkillTool",
        "skill_health" => "Ai::Tools::SkillTool",
        "skill_metrics" => "Ai::Tools::SkillTool",
        "create_skill" => "Ai::Tools::SkillTool",
        "update_skill" => "Ai::Tools::SkillTool",
        "clone_skill" => "Ai::Tools::SkillTool",
        "delete_skill" => "Ai::Tools::SkillTool",
        "toggle_skill" => "Ai::Tools::SkillTool",
        "attach_skill_to_agent" => "Ai::Tools::SkillTool",
        "detach_skill_from_agent" => "Ai::Tools::SkillTool",
        # Knowledge quality
        "verify_learning" => "Ai::Tools::KnowledgeQualityTool",
        "dispute_learning" => "Ai::Tools::KnowledgeQualityTool",
        "resolve_contradiction" => "Ai::Tools::KnowledgeQualityTool",
        "rate_knowledge" => "Ai::Tools::KnowledgeQualityTool",
        "knowledge_health" => "Ai::Tools::KnowledgeQualityTool",
        "unsupersede_learning" => "Ai::Tools::KnowledgeQualityTool",
        "verify_learning_batch" => "Ai::Tools::KnowledgeQualityTool",
        # Knowledge graph
        "search_knowledge_graph" => "Ai::Tools::KnowledgeGraphTool",
        "reason_knowledge_graph" => "Ai::Tools::KnowledgeGraphTool",
        "get_graph_node" => "Ai::Tools::KnowledgeGraphTool",
        "list_graph_nodes" => "Ai::Tools::KnowledgeGraphTool",
        "get_graph_neighbors" => "Ai::Tools::KnowledgeGraphTool",
        "graph_statistics" => "Ai::Tools::KnowledgeGraphTool",
        "get_subgraph" => "Ai::Tools::KnowledgeGraphTool",
        "extract_to_knowledge_graph" => "Ai::Tools::KnowledgeGraphTool",
        # Conversations (unified — workspaces, agent chats, concierge)
        "send_message" => "Ai::Tools::ConversationTool",
        "send_concierge_message" => "Ai::Tools::ConversationTool",
        "confirm_concierge_action" => "Ai::Tools::ConversationTool",
        "list_messages" => "Ai::Tools::ConversationTool",
        "get_conversation_messages" => "Ai::Tools::ConversationTool",
        "list_conversations" => "Ai::Tools::ConversationTool",
        "list_workspaces" => "Ai::Tools::ConversationTool",
        "create_workspace" => "Ai::Tools::ConversationTool",
        "invite_agent" => "Ai::Tools::ConversationTool",
        "active_sessions" => "Ai::Tools::ConversationTool",
        "pin_conversation" => "Ai::Tools::ConversationTool",
        "unpin_conversation" => "Ai::Tools::ConversationTool",
        "tag_conversation" => "Ai::Tools::ConversationTool",
        # Activity monitoring
        "get_activity_feed" => "Ai::Tools::ActivityMonitorTool",
        "get_mission_status" => "Ai::Tools::ActivityMonitorTool",
        "get_notifications" => "Ai::Tools::ActivityMonitorTool",
        "dismiss_notification" => "Ai::Tools::ActivityMonitorTool",
        "dismiss_all_notifications" => "Ai::Tools::ActivityMonitorTool",
        "mark_all_notifications_read" => "Ai::Tools::ActivityMonitorTool",
        "get_system_health" => "Ai::Tools::ActivityMonitorTool",
        # Kill switch
        "emergency_halt" => "Ai::Tools::KillSwitchTool",
        "emergency_resume" => "Ai::Tools::KillSwitchTool",
        "kill_switch_status" => "Ai::Tools::KillSwitchTool",
        # Agent autonomy
        "create_agent_goal" => "Ai::Tools::AgentAutonomyTool",
        "list_agent_goals" => "Ai::Tools::AgentAutonomyTool",
        "update_agent_goal" => "Ai::Tools::AgentAutonomyTool",
        "agent_introspect" => "Ai::Tools::AgentAutonomyTool",
        "propose_feature" => "Ai::Tools::AgentAutonomyTool",
        "send_proactive_notification" => "Ai::Tools::AgentAutonomyTool",
        "discover_claude_sessions" => "Ai::Tools::AgentAutonomyTool",
        "request_code_change" => "Ai::Tools::AgentAutonomyTool",
        "create_proposal" => "Ai::Tools::AgentAutonomyTool",
        "escalate" => "Ai::Tools::AgentAutonomyTool",
        "request_feedback" => "Ai::Tools::AgentAutonomyTool",
        "report_issue" => "Ai::Tools::AgentAutonomyTool",
        # Goal decomposition (autonomous planning).
        # validate_plan / approve_plan were unregistered in IMP-4707960fc610:
        # their bodies constantized services that exist nowhere, so both were
        # permanently inert behind a `rescue NameError`.
        "decompose_goal" => "Ai::Tools::AgentAutonomyTool",
        # Intervention policies + deferred operations (operator control over autonomy)
        "list_intervention_policies" => "Ai::Tools::AgentAutonomyTool",
        "create_intervention_policy" => "Ai::Tools::AgentAutonomyTool",
        "update_intervention_policy" => "Ai::Tools::AgentAutonomyTool",
        "delete_intervention_policy" => "Ai::Tools::AgentAutonomyTool",
        "list_deferred_operations" => "Ai::Tools::AgentAutonomyTool",
        "approve_deferred_operation" => "Ai::Tools::AgentAutonomyTool",
        "reject_deferred_operation" => "Ai::Tools::AgentAutonomyTool",
        # Self-improvement (skill mutation, challenges)
        "generate_self_challenge" => "Ai::Tools::SelfImprovementTool",
        "list_challenges" => "Ai::Tools::SelfImprovementTool",
        "get_challenge_result" => "Ai::Tools::SelfImprovementTool",
        "mutate_skill" => "Ai::Tools::SelfImprovementTool",
        "compose_skills" => "Ai::Tools::SelfImprovementTool",
        "auto_evolve_skill" => "Ai::Tools::SelfImprovementTool",
        # Governance (monitoring, collusion detection)
        "governance_scan" => "Ai::Tools::GovernanceTool",
        "list_governance_reports" => "Ai::Tools::GovernanceTool",
        "get_governance_report" => "Ai::Tools::GovernanceTool",
        "resolve_governance_report" => "Ai::Tools::GovernanceTool",
        "detect_collusion" => "Ai::Tools::GovernanceTool",
        "governance_dashboard" => "Ai::Tools::GovernanceTool",
        # Coordination (stigmergic signals, pressure fields, self-organizing teams)
        "emit_signal" => "Ai::Tools::CoordinationTool",
        "perceive_signals" => "Ai::Tools::CoordinationTool",
        "reinforce_signal" => "Ai::Tools::CoordinationTool",
        "measure_pressure" => "Ai::Tools::CoordinationTool",
        "perceive_pressure" => "Ai::Tools::CoordinationTool",
        "optimize_team" => "Ai::Tools::CoordinationTool",
        "recruit_agent" => "Ai::Tools::CoordinationTool",
        # Image generation
        "generate_image" => "Ai::Tools::ImageGenerationTool",
        "list_generated_images" => "Ai::Tools::ImageGenerationTool",
        # Content production missions (multi-modal content generation)
        "start_content_production" => "Ai::Tools::ContentProductionMissionTool",
        "content_production_status" => "Ai::Tools::ContentProductionMissionTool",
        # Paid media generation — Runway (video) + ElevenLabs (audio/voiceover)
        "generate_video" => "Ai::Tools::VideoGenerationTool",
        "generate_audio" => "Ai::Tools::AudioGenerationTool",
        # Docker infrastructure management — containers
        "docker_list_containers" => "Ai::Tools::DockerContainerTool",
        "docker_get_container" => "Ai::Tools::DockerContainerTool",
        "docker_create_container" => "Ai::Tools::DockerContainerTool",
        "docker_start_container" => "Ai::Tools::DockerContainerTool",
        "docker_stop_container" => "Ai::Tools::DockerContainerTool",
        "docker_restart_container" => "Ai::Tools::DockerContainerTool",
        "docker_delete_container" => "Ai::Tools::DockerContainerTool",
        "docker_container_logs" => "Ai::Tools::DockerContainerTool",
        "docker_container_stats" => "Ai::Tools::DockerContainerTool",
        "docker_container_exec" => "Ai::Tools::DockerContainerTool",
        # Docker infrastructure management — Swarm services
        "docker_list_services" => "Ai::Tools::DockerServiceTool",
        "docker_get_service" => "Ai::Tools::DockerServiceTool",
        "docker_create_service" => "Ai::Tools::DockerServiceTool",
        "docker_update_service" => "Ai::Tools::DockerServiceTool",
        "docker_scale_service" => "Ai::Tools::DockerServiceTool",
        "docker_rollback_service" => "Ai::Tools::DockerServiceTool",
        "docker_delete_service" => "Ai::Tools::DockerServiceTool",
        "docker_service_logs" => "Ai::Tools::DockerServiceTool",
        "docker_service_tasks" => "Ai::Tools::DockerServiceTool",
        # AI data sources — governed external data fetch + CRUD (1:1 REST parity)
        "data_source_list" => "Ai::Tools::DataSourceTool",
        "data_source_get" => "Ai::Tools::DataSourceTool",
        "data_source_describe" => "Ai::Tools::DataSourceTool",
        "data_source_query" => "Ai::Tools::DataSourceTool",
        "data_source_health" => "Ai::Tools::DataSourceTool",
        "data_source_validate_config" => "Ai::Tools::DataSourceTool",
        # AI data sources — discovery + provenance + impact (effectiveness/trust)
        "data_source_discover" => "Ai::Tools::DataSourceTool",
        "data_source_provenance" => "Ai::Tools::DataSourceTool",
        "data_source_impact" => "Ai::Tools::DataSourceTool",
        # AI data sources — Phase 2b observability (schema drift, quality, contract, introspect)
        "data_source_schema_history" => "Ai::Tools::DataSourceTool",
        "data_source_quality" => "Ai::Tools::DataSourceTool",
        "data_source_introspect" => "Ai::Tools::DataSourceTool",
        "data_source_contract" => "Ai::Tools::DataSourceTool",
        "data_source_subscribe" => "Ai::Tools::DataSourceTool",
        "data_source_unsubscribe" => "Ai::Tools::DataSourceTool",
        "data_source_create" => "Ai::Tools::DataSourceTool",
        "data_source_update" => "Ai::Tools::DataSourceTool",
        "data_source_delete" => "Ai::Tools::DataSourceTool",
        # AI data sources — surrogate-key / scoped response-cache invalidation
        "data_source_invalidate_cache" => "Ai::Tools::DataSourceTool",
        # AI data sources — Phase 4b-3b onboarding portability (export/import,
        # template library, config versioning + rollback)
        "data_source_export" => "Ai::Tools::DataSourceTool",
        "data_source_import" => "Ai::Tools::DataSourceTool",
        "data_source_list_templates" => "Ai::Tools::DataSourceTool",
        "data_source_install_template" => "Ai::Tools::DataSourceTool",
        "data_source_config_versions" => "Ai::Tools::DataSourceTool",
        "data_source_rollback_config" => "Ai::Tools::DataSourceTool",
        # AI data sources — Phase 4b-3 multi-source coordination (reconcile/failover/
        # replay) + RAG ingestion bridge (fetch -> embed into a knowledge base)
        "data_source_reconcile" => "Ai::Tools::DataSourceTool",
        "data_source_failover_query" => "Ai::Tools::DataSourceTool",
        "data_source_replay" => "Ai::Tools::DataSourceTool",
        "data_source_ingest_to_kb" => "Ai::Tools::DataSourceTool",
        # Docker infrastructure management — Swarm stacks
        "docker_list_stacks" => "Ai::Tools::DockerStackTool",
        "docker_get_stack" => "Ai::Tools::DockerStackTool",
        "docker_deploy_stack" => "Ai::Tools::DockerStackTool",
        "docker_delete_stack" => "Ai::Tools::DockerStackTool",
        "docker_adopt_stack" => "Ai::Tools::DockerStackTool",
        # Docker infrastructure management — clusters, nodes, secrets, configs
        "docker_list_clusters" => "Ai::Tools::DockerClusterTool",
        "docker_get_cluster" => "Ai::Tools::DockerClusterTool",
        "docker_cluster_health" => "Ai::Tools::DockerClusterTool",
        "docker_list_nodes" => "Ai::Tools::DockerClusterTool",
        "docker_node_promote" => "Ai::Tools::DockerClusterTool",
        "docker_node_demote" => "Ai::Tools::DockerClusterTool",
        "docker_node_drain" => "Ai::Tools::DockerClusterTool",
        "docker_node_activate" => "Ai::Tools::DockerClusterTool",
        "docker_list_secrets" => "Ai::Tools::DockerClusterTool",
        "docker_create_secret" => "Ai::Tools::DockerClusterTool",
        "docker_delete_secret" => "Ai::Tools::DockerClusterTool",
        "docker_list_configs" => "Ai::Tools::DockerClusterTool",
        "docker_create_config" => "Ai::Tools::DockerClusterTool",
        "docker_delete_config" => "Ai::Tools::DockerClusterTool",
        # Docker infrastructure management — hosts
        "docker_list_hosts" => "Ai::Tools::DockerHostTool",
        "docker_get_host" => "Ai::Tools::DockerHostTool",
        "docker_sync_host" => "Ai::Tools::DockerHostTool",
        "docker_test_host" => "Ai::Tools::DockerHostTool",
        # Docker infrastructure management — images
        "docker_list_images" => "Ai::Tools::DockerImageTool",
        "docker_pull_image" => "Ai::Tools::DockerImageTool",
        "docker_delete_image" => "Ai::Tools::DockerImageTool",
        "docker_tag_image" => "Ai::Tools::DockerImageTool",
        # Docker infrastructure management — networks and volumes
        "docker_list_networks" => "Ai::Tools::DockerNetworkVolumeTool",
        "docker_create_network" => "Ai::Tools::DockerNetworkVolumeTool",
        "docker_delete_network" => "Ai::Tools::DockerNetworkVolumeTool",
        "docker_list_volumes" => "Ai::Tools::DockerNetworkVolumeTool",
        "docker_create_volume" => "Ai::Tools::DockerNetworkVolumeTool",
        "docker_delete_volume" => "Ai::Tools::DockerNetworkVolumeTool",
        # Codebase Intelligence — Discovery
        "code_context_tree" => "Ai::Tools::CodeDiscoveryTool",
        "code_file_skeleton" => "Ai::Tools::CodeDiscoveryTool",
        "code_semantic_search" => "Ai::Tools::CodeDiscoveryTool",
        "code_identifier_search" => "Ai::Tools::CodeDiscoveryTool",
        "code_semantic_navigate" => "Ai::Tools::CodeDiscoveryTool",
        "code_feature_hub" => "Ai::Tools::CodeDiscoveryTool",
        # Codebase Intelligence — Analysis
        "code_blast_radius" => "Ai::Tools::CodeAnalysisTool",
        "code_static_analysis" => "Ai::Tools::CodeAnalysisTool",
        "code_index_status" => "Ai::Tools::CodeAnalysisTool",
        "code_dead_code" => "Ai::Tools::CodeAnalysisTool",
        "code_find_duplicates" => "Ai::Tools::CodeAnalysisTool",
        "code_analyze_section" => "Ai::Tools::CodeAnalysisTool",
        # Codebase Intelligence — Memory
        "code_upsert_node" => "Ai::Tools::CodeMemoryTool",
        "code_create_relation" => "Ai::Tools::CodeMemoryTool",
        "code_search_graph" => "Ai::Tools::CodeMemoryTool",
        "code_prune_stale" => "Ai::Tools::CodeMemoryTool",
        "code_bulk_index" => "Ai::Tools::CodeMemoryTool"
      }.freeze

      # Tool maps contributed by extensions at boot. Extensions call
      # .register_extension_tools from an engine `to_prepare` hook — a
      # slug-agnostic seam any extension can plug its action->class map into with
      # no core edit. The backing store is a class-level ivar; to_prepare re-runs
      # on every reload, so the registration survives development code reloading.
      #
      # WHAT THIS SEAM DOES *NOT* YET MEAN (IMP-2836d290f99a): core does NOT hold
      # zero references to extension tool classes. The static TOOLS map above
      # hardcodes 263 entries pointing at 8 classes that live in
      # extensions/system — SystemFleetTool (134), SdwanTool (86),
      # SystemPackageRepositoryTool (16), SystemIngressTool (12),
      # SystemArchitectureCatalogTool (6), SystemStorageOwnerTool (4),
      # SystemAcmeTool (4), SystemBlastRadiusTool (1). The seam has exactly one
      # consumer today — one extension's engine calls it from `to_prepare` — and
      # it is not the system extension, whose migration onto it has not happened.
      #
      # Those 263 entries are harmless in core mode only because
      # .available_tools rescues the NameError their constantize raises — a
      # missing tool CLASS drops out of the catalog by itself. A core-HOSTED tool
      # that merely DEPENDS on an extension does not, and must gate itself; see
      # Ai::Tools::DockerProvisioningTool.extension_available?.
      @extension_tools = {}

      # Merge an extension's MCP tool map (action name => handler class name
      # string) into the registry. Idempotent; later registrations win on a key
      # collision. Returns the merged extension map.
      def self.register_extension_tools(tool_map)
        return extension_tools if tool_map.blank?

        extension_tools.merge!(tool_map.transform_keys(&:to_s))
      end

      # Extension-contributed tools registered so far (empty in core mode).
      def self.extension_tools
        @extension_tools ||= {}
      end

      # Full action => class map: static core TOOLS plus any extension-registered
      # tools. All lookup/iteration paths use this so extension tools are
      # first-class once their owning engine has registered them.
      def self.all_tools
        TOOLS.merge(extension_tools)
      end

      # ADVERTISEMENT PREDICATE, per tool CLASS (IMP-5039d026da0d).
      #
      # THE ONE DEFINITION OF "the platform offers this". Before this existed,
      # `.permitted?` gated exactly ONE of four advertisement surfaces — the
      # tools/list path below — while McpPlatformToolRegistrar.sync_to_database!
      # (the mcp_tools rows behind the frontend MCP browser),
      # .register_all!/.tool_classes and
      # SemanticToolDiscoveryService#collect_all_tools each walked `all_tools`
      # raw. So after IMP-2836d290f99a the four docker-runtime actions were
      # correctly absent from tools/list in core mode and still present in the
      # browsable catalog and the semantic discovery index, which is how an
      # agent doing discovery-by-embedding got steered at an action that is not
      # offered and cannot run. The fix is that all four now ask HERE.
      #
      # `agent:` DEFAULTS TO NIL, AND NIL IS NOT A WEAKER CHECK — it is a
      # DIFFERENT one. BaseTool.permitted? short-circuits `return true unless
      # agent`, so with no agent the predicate degenerates to exactly the
      # AVAILABILITY question ("is the backing extension loaded?", the
      # `defined?(::System)` / `.extension_available?` guards) and asks nothing
      # about permissions. That is the right question for the three account-wide
      # surfaces: none of them has an agent, and each publishes ONE catalog the
      # whole account reads, so filtering it by any single agent's grants would
      # be wrong even if an agent were in hand. Verified over every override on
      # the tree at the time of writing — `command grep -rnE "^ *def self\.permitted\?"
      # <repo>/server/app <repo>/extensions` finds 14, and every one of them is
      # either a bare `true` or a `defined?(::Const)` namespace probe followed by
      # `super` — so nil-agent filtering removes only UNAVAILABLE tools today.
      def self.advertised_class?(klass, agent: nil)
        klass.permitted?(agent: agent)
      end

      # ADVERTISEMENT PREDICATE, per registry ACTION. Per-class gate first, then
      # the per-ACTION hook (IMP-8f6ade11fbdf). Most tool classes are
      # all-or-nothing extension-wise (see DockerProvisioningTool), for which
      # `.permitted?` alone is correct. Ai::Tools::DiskImageOperatorTool is a
      # mixed case — only 2 of its 3 actions depend on extensions/system — so
      # gating the whole class would incorrectly de-advertise its core-only
      # action too. `respond_to?` keeps the hook opt-in: classes that don't
      # define `.action_advertised?` are unaffected.
      def self.advertised_action?(name, klass, agent: nil)
        return false unless advertised_class?(klass, agent: agent)
        return false if klass.respond_to?(:action_advertised?) && !klass.action_advertised?(name)

        true
      end

      def self.available_tools(agent: nil)
        all_tools.each_with_object({}) do |(name, class_name), hash|
          klass = class_name.constantize
          next unless advertised_action?(name, klass, agent: agent)

          hash[name] = klass
        rescue NameError => e
          Rails.logger.warn "[PlatformApiToolRegistry] Tool class not found: #{class_name} - #{e.message}"
        end
      end

      def self.find_tool(name)
        # Check static + extension-registered tools first
        class_name = all_tools[name]
        if class_name
          return class_name.constantize
        end

        # Check dynamic tools
        dynamic_tool = dynamic_tools.find { |t| t[:name] == name }
        dynamic_tool[:handler_class]&.constantize if dynamic_tool
      rescue NameError
        nil
      end

      def self.tool_definitions(agent: nil)
        available_tools(agent: agent).map do |name, klass|
          action_defs = klass.action_definitions
          if action_defs.key?(name)
            action_defs[name].merge(name: name)
          else
            klass.definition.merge(name: name)  # fallback for unmatched tools
          end
        end
      end

      # Discover tools by natural language query (semantic search)
      def self.discover_tools(query:, account:, capabilities: nil, limit: 10)
        service = SemanticToolDiscoveryService.new(account: account)
        service.discover(query: query, capabilities: capabilities, limit: limit)
      end

      # Register a tool dynamically at runtime
      def self.register_dynamic_tool(account:, name:, description:, parameters:, handler:, metadata: {})
        SemanticToolDiscoveryService.register_dynamic_tool(
          account: account, name: name, description: description,
          parameters: parameters, handler: handler, metadata: metadata
        )
      end

      # Unregister a dynamic tool
      def self.unregister_dynamic_tool(account:, name:)
        SemanticToolDiscoveryService.unregister_dynamic_tool(account: account, name: name)
      end

      # List dynamic tools for an account
      def self.dynamic_tools(account: nil)
        return [] unless account

        Rails.cache.read("tool_discovery:#{account.id}:dynamic_tools") || []
      end
    end
  end
end
