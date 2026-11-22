-- OpenRig 0.7.19 schema: every object in sqlite_master that has SQL, except SQLite's own, in creation order.
-- Extracted read-only from ~/.openrig/openrig.sqlite on 2026-11-21. Definitions only; no rows.
CREATE TABLE schema_migrations (
      name TEXT PRIMARY KEY,
      applied_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
CREATE TABLE rigs (
      id          TEXT PRIMARY KEY,
      name        TEXT NOT NULL,
      created_at  TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
    , workspace_json TEXT, archived_at TEXT, permission_policy TEXT, rig_policy_origin TEXT, rig_policy_resolved_target TEXT, rig_policy_declaring_dir TEXT, rig_policy_launch_posture TEXT, claude_managed_block_file TEXT, non_interruptive INTEGER NOT NULL DEFAULT 0 CHECK (non_interruptive IN (0, 1)), install_root TEXT, env_json TEXT, startup_layers_json TEXT);
CREATE TABLE nodes (
      id          TEXT PRIMARY KEY,
      rig_id      TEXT NOT NULL REFERENCES rigs(id) ON DELETE CASCADE,
      logical_id  TEXT NOT NULL,
      role        TEXT,
      runtime     TEXT,
      model       TEXT,
      cwd         TEXT,
      created_at  TEXT NOT NULL DEFAULT (datetime('now')), surface_hint TEXT, workspace TEXT, restore_policy TEXT, package_refs TEXT, pod_id TEXT REFERENCES pods(id) ON DELETE SET NULL, agent_ref TEXT, profile TEXT, label TEXT, resolved_spec_name TEXT, resolved_spec_version TEXT, resolved_spec_hash TEXT, occupant_lifecycle TEXT, continuity_outcome TEXT, handover_result TEXT, previous_occupant TEXT, handover_at TEXT, codex_config_profile TEXT, permission_policy TEXT, policy_origin TEXT, policy_resolved_target TEXT, policy_declaring_dir TEXT, policy_launch_posture TEXT, session_source_json TEXT, effort TEXT, effort_choice TEXT, env_json TEXT, advisor TEXT, launch_recipe_json TEXT, codex_permissions_json TEXT, claude_token_ref TEXT, claude_permissions_json TEXT, account_home TEXT, claude_mcp TEXT CHECK (claude_mcp IS NULL OR claude_mcp = 'none'), permissions_to TEXT, launch_wrapper TEXT, claude_auto_mode_json TEXT, input_route TEXT NOT NULL DEFAULT 'typed' CHECK(input_route IN ('typed','native')), process_limits TEXT,
      UNIQUE(rig_id, logical_id)
    );
CREATE TABLE bindings (
      id              TEXT PRIMARY KEY,
      node_id         TEXT NOT NULL UNIQUE REFERENCES nodes(id) ON DELETE CASCADE,
      tmux_session    TEXT,
      tmux_window     TEXT,
      tmux_pane       TEXT,
      cmux_workspace  TEXT,
      cmux_surface    TEXT,
      updated_at      TEXT NOT NULL DEFAULT (datetime('now'))
    , attachment_type TEXT NOT NULL DEFAULT 'tmux', external_session_name TEXT);
CREATE TABLE sessions (
      id              TEXT PRIMARY KEY,
      node_id         TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
      session_name    TEXT NOT NULL,
      status          TEXT NOT NULL DEFAULT 'unknown',
      last_seen_at    TEXT,
      created_at      TEXT NOT NULL DEFAULT (datetime('now'))
    , resume_type TEXT, resume_token TEXT, restore_policy TEXT NOT NULL DEFAULT 'resume_if_possible', origin TEXT NOT NULL DEFAULT 'launched', startup_status TEXT NOT NULL DEFAULT 'pending', startup_completed_at TEXT, resume_provenance TEXT, resume_last_verified TEXT, resume_last_probe_status TEXT, resume_launch_token TEXT, resume_rotated_from TEXT, resume_rotated_process TEXT, resume_launch_process TEXT, intentionally_stopped INTEGER NOT NULL DEFAULT 0
      CHECK (intentionally_stopped IN (0, 1)), agent_app TEXT, agent_runner INTEGER, launched_cwd TEXT);
CREATE TABLE events (
      seq         INTEGER PRIMARY KEY AUTOINCREMENT,
      -- INTENTIONALLY NOT AN FK to rigs(id).
      -- Events are an append-only history log. They must survive rig deletion
      -- so the full timeline is preserved for replay and audit.
      rig_id      TEXT,
      -- INTENTIONALLY NOT AN FK to nodes(id).
      -- Same rationale: events must survive node deletion.
      node_id     TEXT,
      type        TEXT NOT NULL,
      payload     TEXT NOT NULL,
      created_at  TEXT NOT NULL DEFAULT (datetime('now'))
    );
CREATE INDEX idx_events_rig_seq ON events(rig_id, seq);
CREATE TABLE snapshots (
      id          TEXT PRIMARY KEY,
      rig_id      TEXT NOT NULL,
      kind        TEXT NOT NULL,
      status      TEXT NOT NULL DEFAULT 'complete',
      data        TEXT NOT NULL,
      created_at  TEXT NOT NULL DEFAULT (datetime('now'))
    );
CREATE INDEX idx_snapshots_rig ON snapshots(rig_id, created_at);
CREATE TABLE checkpoints (
      id              TEXT PRIMARY KEY,
      node_id         TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
      summary         TEXT NOT NULL,
      current_task    TEXT,
      next_step       TEXT,
      blocked_on      TEXT,
      key_artifacts   TEXT,
      confidence      TEXT,
      created_at      TEXT NOT NULL DEFAULT (datetime('now'))
    , pod_id TEXT REFERENCES pods(id) ON DELETE SET NULL, continuity_source TEXT, continuity_artifacts_json TEXT);
CREATE INDEX idx_checkpoints_node ON checkpoints(node_id, created_at);
CREATE TABLE packages (
      id              TEXT PRIMARY KEY,
      name            TEXT NOT NULL,
      version         TEXT NOT NULL,
      source_kind     TEXT NOT NULL,
      source_ref      TEXT NOT NULL,
      manifest_hash   TEXT NOT NULL,
      summary         TEXT,
      created_at      TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE(name, version)
    );
CREATE TABLE package_installs (
      id              TEXT PRIMARY KEY,
      package_id      TEXT NOT NULL REFERENCES packages(id),
      target_root     TEXT NOT NULL,
      scope           TEXT NOT NULL,
      status          TEXT NOT NULL DEFAULT 'planned',
      risk_tier       TEXT,
      created_at      TEXT NOT NULL DEFAULT (datetime('now')),
      applied_at      TEXT,
      rolled_back_at  TEXT
    , bootstrap_id TEXT REFERENCES bootstrap_runs(id) ON DELETE SET NULL);
CREATE INDEX idx_installs_package ON package_installs(package_id);
CREATE TABLE install_journal (
      id              TEXT PRIMARY KEY,
      install_id      TEXT NOT NULL REFERENCES package_installs(id),
      seq             INTEGER NOT NULL,
      action          TEXT NOT NULL,
      export_type     TEXT NOT NULL,
      classification  TEXT NOT NULL,
      target_path     TEXT NOT NULL,
      backup_path     TEXT,
      before_hash     TEXT,
      after_hash      TEXT,
      status          TEXT NOT NULL DEFAULT 'pending',
      created_at      TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE(install_id, seq)
    );
CREATE INDEX idx_journal_install ON install_journal(install_id);
CREATE TABLE bootstrap_runs (
      id          TEXT PRIMARY KEY,
      source_kind TEXT NOT NULL,
      source_ref  TEXT NOT NULL,
      status      TEXT NOT NULL DEFAULT 'planned',
      rig_id      TEXT,
      created_at  TEXT NOT NULL DEFAULT (datetime('now')),
      applied_at  TEXT
    );
CREATE TABLE bootstrap_actions (
      id              TEXT PRIMARY KEY,
      bootstrap_id    TEXT NOT NULL REFERENCES bootstrap_runs(id),
      seq             INTEGER NOT NULL,
      action_kind     TEXT NOT NULL,
      subject_type    TEXT,
      subject_name    TEXT,
      provider        TEXT,
      command_preview  TEXT,
      status          TEXT NOT NULL DEFAULT 'planned',
      detail_json     TEXT,
      created_at      TEXT NOT NULL DEFAULT (datetime('now'))
    );
CREATE INDEX idx_bootstrap_actions ON bootstrap_actions(bootstrap_id, seq);
CREATE TABLE runtime_verifications (
      id                TEXT PRIMARY KEY,
      runtime           TEXT NOT NULL,
      version           TEXT,
      capabilities_json TEXT,
      verified_at       TEXT NOT NULL DEFAULT (datetime('now')),
      status            TEXT NOT NULL,
      error             TEXT
    );
CREATE TABLE discovered_sessions (
      id              TEXT PRIMARY KEY,
      tmux_session    TEXT NOT NULL,
      tmux_window     TEXT,
      tmux_pane       TEXT,
      pid             INTEGER,
      cwd             TEXT,
      active_command  TEXT,
      runtime_hint    TEXT NOT NULL DEFAULT 'unknown',
      confidence      TEXT NOT NULL DEFAULT 'low',
      evidence_json   TEXT,
      config_json     TEXT,
      status          TEXT NOT NULL DEFAULT 'active',
      claimed_node_id TEXT REFERENCES nodes(id) ON DELETE SET NULL,
      first_seen_at   TEXT NOT NULL DEFAULT (datetime('now')),
      last_seen_at    TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE(tmux_session, tmux_pane)
    );
CREATE INDEX idx_discovered_status ON discovered_sessions(status);
CREATE TABLE pods (
      id                      TEXT PRIMARY KEY,
      rig_id                  TEXT NOT NULL REFERENCES rigs(id) ON DELETE CASCADE,
      label                   TEXT NOT NULL,
      summary                 TEXT,
      continuity_policy_json  TEXT,
      created_at              TEXT NOT NULL DEFAULT (datetime('now'))
    , namespace TEXT NOT NULL DEFAULT '');
CREATE TABLE continuity_state (
      pod_id        TEXT NOT NULL REFERENCES pods(id) ON DELETE CASCADE,
      node_id       TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
      status        TEXT NOT NULL DEFAULT 'healthy',
      artifacts_json TEXT,
      last_sync_at  TEXT,
      updated_at    TEXT NOT NULL DEFAULT (datetime('now')),
      PRIMARY KEY (pod_id, node_id)
    );
CREATE TABLE node_startup_context (
      node_id                 TEXT PRIMARY KEY REFERENCES nodes(id) ON DELETE CASCADE,
      projection_entries_json TEXT NOT NULL,
      resolved_files_json     TEXT NOT NULL,
      startup_actions_json    TEXT NOT NULL,
      runtime                 TEXT NOT NULL,
      created_at              TEXT NOT NULL DEFAULT (datetime('now'))
    , guidance_file TEXT);
CREATE TABLE chat_messages (
      id          TEXT PRIMARY KEY,
      rig_id      TEXT NOT NULL REFERENCES rigs(id) ON DELETE CASCADE,
      sender      TEXT NOT NULL,
      kind        TEXT NOT NULL DEFAULT 'message',
      body        TEXT NOT NULL DEFAULT '',
      topic       TEXT,
      created_at  TEXT NOT NULL DEFAULT (datetime('now'))
    );
CREATE INDEX idx_chat_messages_rig_created
      ON chat_messages (rig_id, created_at);
CREATE UNIQUE INDEX idx_pods_rig_namespace ON pods(rig_id, namespace) WHERE namespace != '';
CREATE TABLE context_usage (
      node_id                 TEXT PRIMARY KEY REFERENCES nodes(id) ON DELETE CASCADE,
      session_id              TEXT,
      session_name            TEXT,
      availability            TEXT NOT NULL DEFAULT 'unknown',
      reason                  TEXT,
      source                  TEXT,
      used_percentage         REAL,
      remaining_percentage    REAL,
      context_window_size     INTEGER,
      total_input_tokens      INTEGER,
      total_output_tokens     INTEGER,
      current_usage           TEXT,
      transcript_path         TEXT,
      sampled_at              TEXT,
      updated_at              TEXT NOT NULL DEFAULT (datetime('now'))
    , occupant_generation TEXT);
CREATE TABLE rig_services (
      rig_id TEXT PRIMARY KEY REFERENCES rigs(id) ON DELETE CASCADE,
      kind TEXT NOT NULL,
      spec_json TEXT NOT NULL,
      rig_root TEXT NOT NULL,
      compose_file TEXT NOT NULL,
      project_name TEXT NOT NULL,
      latest_receipt_json TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
CREATE TABLE stream_items (
      stream_item_id TEXT PRIMARY KEY,
      ts_emitted TEXT NOT NULL,
      stream_sort_key TEXT NOT NULL,
      source_session TEXT NOT NULL,
      body TEXT NOT NULL,
      format TEXT NOT NULL DEFAULT 'text',
      hint_type TEXT,
      hint_urgency TEXT,
      hint_destination TEXT,
      hint_tags TEXT,
      interrupt INTEGER NOT NULL DEFAULT 0,
      archived_at TEXT
    , identity_provenance TEXT, body_kept_bytes INTEGER, body_original_bytes INTEGER, identity_principal TEXT);
CREATE INDEX idx_stream_items_source ON stream_items(source_session);
CREATE INDEX idx_stream_items_hint_destination ON stream_items(hint_destination);
CREATE INDEX idx_stream_items_chronological ON stream_items(ts_emitted, stream_sort_key);
CREATE INDEX idx_stream_items_archived ON stream_items(archived_at);
CREATE TABLE queue_items (
      qitem_id TEXT PRIMARY KEY,
      ts_created TEXT NOT NULL,
      ts_updated TEXT NOT NULL,
      source_session TEXT NOT NULL,
      destination_session TEXT NOT NULL,
      state TEXT NOT NULL,
      priority TEXT NOT NULL DEFAULT 'routine',
      tier TEXT,
      tags TEXT,
      blocked_on TEXT,
      handed_off_to TEXT,
      handed_off_from TEXT,
      expires_at TEXT,
      chain_of_record TEXT,
      body TEXT NOT NULL,
      closure_reason TEXT,
      closure_target TEXT,
      closure_required_at TEXT,
      claimed_at TEXT,
      last_nudge_attempt TEXT,
      last_nudge_result TEXT,
      last_heartbeat TEXT,
      resolution TEXT
    , target_repo TEXT, summary TEXT, evidence_ref TEXT, minting_generation_uuid TEXT, claimed_by_generation_uuid TEXT, human_intent TEXT CHECK (human_intent IN ('decision', 'update')), human_detail TEXT, reply_to TEXT, human_questions TEXT, human_answers TEXT, last_nudge_input_box TEXT, delegated_decision TEXT, content_erased_at TEXT, return_route TEXT, return_route_basis TEXT);
CREATE INDEX idx_queue_items_destination_state ON queue_items(destination_session, state);
CREATE INDEX idx_queue_items_source ON queue_items(source_session);
CREATE INDEX idx_queue_items_state ON queue_items(state);
CREATE INDEX idx_queue_items_handed_off_to ON queue_items(handed_off_to);
CREATE INDEX idx_queue_items_closure_overdue ON queue_items(state, closure_required_at) WHERE state = 'in-progress';
CREATE TABLE queue_transitions (
      transition_id INTEGER PRIMARY KEY AUTOINCREMENT,
      qitem_id TEXT NOT NULL,
      ts TEXT NOT NULL,
      state TEXT NOT NULL,
      transition_note TEXT,
      actor_session TEXT NOT NULL,
      closure_reason TEXT,
      closure_target TEXT
    , identity_provenance TEXT, owner_notification_kind TEXT, owner_notification_level TEXT, identity_principal TEXT);
CREATE INDEX idx_queue_transitions_qitem ON queue_transitions(qitem_id, ts);
CREATE INDEX idx_queue_transitions_actor ON queue_transitions(actor_session);
CREATE TABLE inbox_entries (
      inbox_id TEXT PRIMARY KEY,
      destination_session TEXT NOT NULL,
      sender_session TEXT NOT NULL,
      body TEXT NOT NULL,
      tags TEXT,
      urgency TEXT NOT NULL DEFAULT 'routine',
      ts_dropped TEXT NOT NULL,
      state TEXT NOT NULL DEFAULT 'pending',
      absorbed_at TEXT,
      absorbed_qitem_id TEXT,
      denied_at TEXT,
      denied_reason TEXT,
      audit_pointer TEXT
    , identity_provenance TEXT, identity_principal TEXT);
CREATE INDEX idx_inbox_entries_destination_state ON inbox_entries(destination_session, state);
CREATE INDEX idx_inbox_entries_sender ON inbox_entries(sender_session);
CREATE INDEX idx_inbox_entries_state ON inbox_entries(state);
CREATE TABLE outbox_entries (
      outbox_id TEXT PRIMARY KEY,
      sender_session TEXT NOT NULL,
      destination_session TEXT NOT NULL,
      body TEXT NOT NULL,
      tags TEXT,
      urgency TEXT NOT NULL DEFAULT 'routine',
      ts_dispatched TEXT NOT NULL,
      delivery_state TEXT NOT NULL DEFAULT 'pending',
      delivered_at TEXT,
      audit_pointer TEXT
    , identity_provenance TEXT, guard_binding TEXT, retired_at TEXT, retired_by TEXT, retirement_reason TEXT, guard_delivery TEXT, identity_principal TEXT);
CREATE INDEX idx_outbox_entries_sender ON outbox_entries(sender_session);
CREATE INDEX idx_outbox_entries_destination ON outbox_entries(destination_session);
CREATE INDEX idx_outbox_entries_delivery_state ON outbox_entries(delivery_state);
CREATE TABLE project_classifications (
      project_id TEXT PRIMARY KEY,
      stream_item_id TEXT NOT NULL UNIQUE REFERENCES stream_items(stream_item_id),
      classification_type TEXT,
      classification_urgency TEXT,
      classification_maturity TEXT,
      classification_confidence TEXT,
      classification_destination TEXT,
      action TEXT,
      classifier_session TEXT NOT NULL,
      ts_projected TEXT NOT NULL
    , area TEXT, scope_ref TEXT, duplicate_of_stream_item_id TEXT
      REFERENCES stream_items(stream_item_id), needs_human INTEGER
      CHECK (needs_human IS NULL OR needs_human IN (0, 1)), lease_id TEXT, classifier_version TEXT, taxonomy_version TEXT, candidate_set_version TEXT, identity_provenance TEXT);
CREATE INDEX idx_project_classifications_classifier_session ON project_classifications(classifier_session);
CREATE INDEX idx_project_classifications_destination ON project_classifications(classification_destination);
CREATE INDEX idx_project_classifications_ts_projected ON project_classifications(ts_projected);
CREATE TABLE classifier_leases (
      lease_id TEXT PRIMARY KEY,
      classifier_session TEXT NOT NULL,
      acquired_at TEXT NOT NULL,
      expires_at TEXT NOT NULL,
      last_heartbeat TEXT NOT NULL,
      state TEXT NOT NULL DEFAULT 'active',
      reclaimed_by_session TEXT,
      reclaim_reason TEXT
    );
CREATE UNIQUE INDEX idx_classifier_leases_active_singleton
      ON classifier_leases(state) WHERE state = 'active';
CREATE INDEX idx_classifier_leases_classifier_session
      ON classifier_leases(classifier_session);
CREATE INDEX idx_classifier_leases_expires_at
      ON classifier_leases(expires_at) WHERE state = 'active';
CREATE TABLE views_custom (
      view_id TEXT PRIMARY KEY,
      view_name TEXT NOT NULL UNIQUE,
      definition TEXT NOT NULL,
      registered_by_session TEXT NOT NULL,
      registered_at TEXT NOT NULL,
      last_evaluated_at TEXT
    );
CREATE INDEX idx_views_custom_registered_by ON views_custom(registered_by_session);
CREATE TABLE watchdog_jobs (
      job_id TEXT PRIMARY KEY,
      policy TEXT NOT NULL,
      spec_yaml TEXT NOT NULL,
      target_session TEXT NOT NULL,
      interval_seconds INTEGER NOT NULL,
      active_wake_interval_seconds INTEGER,
      scan_interval_seconds INTEGER,
      last_evaluation_at TEXT,
      last_fire_at TEXT,
      actionable INTEGER NOT NULL DEFAULT 0,
      last_actionable_at TEXT,
      state TEXT NOT NULL DEFAULT 'active',
      registered_by_session TEXT NOT NULL,
      registered_at TEXT NOT NULL,
      terminal_reason TEXT
    , registered_by_generation_uuid TEXT, target_generation_uuid TEXT, watched_file_path TEXT, threshold_bytes INTEGER, requires_job_id TEXT, last_fired_generation_uuid TEXT, watched_file_generation_uuid TEXT, last_fired_condition TEXT, threshold_tokens INTEGER, threshold_percent REAL);
CREATE INDEX idx_watchdog_jobs_state ON watchdog_jobs(state);
CREATE INDEX idx_watchdog_jobs_policy ON watchdog_jobs(policy);
CREATE INDEX idx_watchdog_jobs_target_session ON watchdog_jobs(target_session);
CREATE INDEX idx_watchdog_jobs_active_next_eval
      ON watchdog_jobs(last_evaluation_at) WHERE state = 'active';
CREATE TABLE watchdog_history (
      history_id TEXT PRIMARY KEY,
      job_id TEXT NOT NULL REFERENCES watchdog_jobs(job_id),
      evaluated_at TEXT NOT NULL,
      outcome TEXT NOT NULL,
      skip_reason TEXT,
      delivery_target_session TEXT,
      delivery_status TEXT,
      delivery_message TEXT,
      evaluation_notes TEXT
    );
CREATE INDEX idx_watchdog_history_job_recent
      ON watchdog_history(job_id, evaluated_at DESC);
CREATE INDEX idx_watchdog_history_outcome_recent
      ON watchdog_history(outcome, evaluated_at DESC);
CREATE TABLE workflow_specs (
      spec_id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      version TEXT NOT NULL,
      purpose TEXT,
      target_rig TEXT,
      roles_json TEXT NOT NULL,
      steps_json TEXT NOT NULL,
      coordination_terminal_turn_rule TEXT NOT NULL DEFAULT 'hot_potato',
      source_path TEXT NOT NULL,
      source_hash TEXT NOT NULL,
      cached_at TEXT NOT NULL
    , status TEXT NOT NULL DEFAULT 'valid', error_message TEXT, spec_json TEXT);
CREATE UNIQUE INDEX idx_workflow_specs_name_version
      ON workflow_specs(name, version);
CREATE INDEX idx_workflow_specs_target_rig
      ON workflow_specs(target_rig);
CREATE TABLE workflow_instances (
      instance_id TEXT PRIMARY KEY,
      workflow_name TEXT NOT NULL,
      workflow_version TEXT NOT NULL,
      created_by_session TEXT NOT NULL,
      created_at TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'active',
      current_frontier_json TEXT NOT NULL DEFAULT '[]',
      current_step_id TEXT,
      hop_count INTEGER NOT NULL DEFAULT 0,
      fallback_synthesis TEXT,
      last_continuation_decision_json TEXT,
      completed_at TEXT
    , version INTEGER NOT NULL DEFAULT 0, resume_count INTEGER NOT NULL DEFAULT 0, hops_baseline INTEGER NOT NULL DEFAULT 0, bound_rig TEXT, lifecycle_operation_key TEXT, compiled_input_digest TEXT, lifecycle_binding_json TEXT, scope_json TEXT, spec_source_path TEXT, spec_json TEXT, root_objective TEXT);
CREATE INDEX idx_workflow_instances_status_name
      ON workflow_instances(status, workflow_name);
CREATE INDEX idx_workflow_instances_creator_status
      ON workflow_instances(created_by_session, status);
CREATE TABLE workflow_step_trails (
      trail_id TEXT PRIMARY KEY,
      instance_id TEXT NOT NULL REFERENCES workflow_instances(instance_id),
      step_id TEXT NOT NULL,
      step_role TEXT NOT NULL,
      closed_at TEXT NOT NULL,
      closure_reason TEXT NOT NULL,
      closure_evidence_json TEXT,
      actor_session TEXT NOT NULL,
      next_qitem_id TEXT REFERENCES queue_items(qitem_id),
      prior_qitem_id TEXT REFERENCES queue_items(qitem_id)
    );
CREATE INDEX idx_workflow_step_trails_instance_recent
      ON workflow_step_trails(instance_id, closed_at DESC);
CREATE INDEX idx_workflow_step_trails_recent
      ON workflow_step_trails(closed_at DESC);
CREATE TABLE mission_control_actions (
      action_id TEXT PRIMARY KEY,
      action_verb TEXT NOT NULL,
      qitem_id TEXT REFERENCES queue_items(qitem_id),
      actor_session TEXT NOT NULL,
      acted_at TEXT NOT NULL,
      before_state_json TEXT,
      after_state_json TEXT,
      reason TEXT,
      annotation TEXT,
      notify_attempted INTEGER NOT NULL DEFAULT 0,
      notify_result TEXT,
      audit_notes_json TEXT
    , identity_provenance TEXT);
CREATE INDEX idx_mc_actions_recent
      ON mission_control_actions(acted_at DESC, action_verb);
CREATE INDEX idx_mc_actions_qitem
      ON mission_control_actions(qitem_id, acted_at DESC);
CREATE INDEX idx_mc_actions_actor
      ON mission_control_actions(actor_session, acted_at DESC);
CREATE INDEX idx_queue_items_target_repo ON queue_items(target_repo);
CREATE INDEX idx_rigs_archived ON rigs(archived_at);
CREATE TABLE seat_identity_verdicts (
      node_id TEXT PRIMARY KEY,
      verdict TEXT NOT NULL,
      evidence_source TEXT,
      reason TEXT,
      registered_pane TEXT,
      observed_pid INTEGER,
      observed_command TEXT,
      matched_layer INTEGER,
      session_name TEXT,
      observed_at TEXT NOT NULL
    , observed_pane_pid INTEGER, evidence_pid INTEGER, evidence_pane_pid INTEGER, evidence_at TEXT);
CREATE INDEX idx_events_node_type_seq ON events(node_id, type, seq);
CREATE INDEX idx_sessions_node_created_id
      ON sessions(node_id, created_at DESC, id DESC);
CREATE TABLE queue_transitions_archive (
      transition_id INTEGER PRIMARY KEY,
      qitem_id TEXT NOT NULL,
      ts TEXT NOT NULL,
      state TEXT NOT NULL,
      transition_note TEXT,
      actor_session TEXT NOT NULL,
      closure_reason TEXT,
      closure_target TEXT,
      archived_at TEXT NOT NULL
    , owner_notification_kind TEXT, owner_notification_level TEXT, identity_provenance TEXT, identity_principal TEXT);
CREATE INDEX idx_queue_transitions_archive_qitem ON queue_transitions_archive(qitem_id, ts);
CREATE TABLE self_host_identity (
      singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
      host_id TEXT NOT NULL,
      minted_at TEXT NOT NULL,
      reconciled_at TEXT NOT NULL
    );
CREATE TABLE occupant_tenures (
      id                        TEXT PRIMARY KEY,
      node_id                   TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
      generation_ordinal        INTEGER NOT NULL,
      generation_uuid           TEXT NOT NULL UNIQUE,
      kind                      TEXT NOT NULL,
      native_session_id_at_boot TEXT,
      boot_at                   TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE(node_id, generation_ordinal)
    );
CREATE INDEX idx_occupant_tenures_node ON occupant_tenures(node_id);
CREATE TABLE daemon_lifecycle (
      singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
      boot_epoch TEXT NOT NULL,
      started_at TEXT NOT NULL,
      last_heartbeat_at TEXT,
      stopped_at TEXT
    );
CREATE TABLE usage_samples (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      lane TEXT NOT NULL CHECK (lane IN ('context', 'provider_window')),
      seat_session TEXT NOT NULL,
      node_id TEXT,
      source TEXT,
      sampled_at TEXT,
      captured_at TEXT NOT NULL,
      total_input_tokens INTEGER,
      total_output_tokens INTEGER,
      used_percentage REAL,
      window TEXT CHECK (window IN ('five_hour', 'weekly') OR window IS NULL),
      window_used_percent REAL,
      resets_at TEXT
    , native_session_id TEXT, client_cost_estimate_usd REAL);
CREATE INDEX idx_usage_samples_seat_time
      ON usage_samples(seat_session, lane, captured_at);
CREATE INDEX idx_usage_samples_node_time
      ON usage_samples(node_id, captured_at);
CREATE TABLE projection_manifest (
      target_path TEXT PRIMARY KEY,
      last_hash   TEXT NOT NULL,
      written_at  TEXT NOT NULL,
      source_spec TEXT,
      category    TEXT
    );
CREATE TABLE applied_launch_observations (
      generation_uuid TEXT PRIMARY KEY REFERENCES occupant_tenures(generation_uuid) ON DELETE CASCADE,
      runtime         TEXT NOT NULL,
      axis            TEXT NOT NULL,
      observation_state TEXT NOT NULL CHECK (observation_state IN ('observed', 'unknown')),
      value           TEXT,
      reason          TEXT,
      observed_at     TEXT NOT NULL DEFAULT (datetime('now'))
    , approval_policy TEXT, daemon_opt_out INTEGER, claude_auto_mode_json TEXT);
CREATE TABLE applied_launch_observation_invalidations (
      generation_uuid TEXT PRIMARY KEY REFERENCES occupant_tenures(generation_uuid) ON DELETE CASCADE,
      invalidated_at  TEXT NOT NULL DEFAULT (datetime('now'))
    );
CREATE TABLE queue_transition_wakes (
      transition_id  INTEGER PRIMARY KEY,
      qitem_id       TEXT NOT NULL,
      phase          TEXT NOT NULL CHECK (phase IN ('armed', 'fired')),
      wake_kind      TEXT NOT NULL CHECK (wake_kind IN ('watchdog', 'timer', 'blocker')),
      wake_ref       TEXT NOT NULL,
      delivery_status TEXT
    );
CREATE INDEX idx_queue_transition_wakes_qitem
      ON queue_transition_wakes (qitem_id, transition_id);
CREATE INDEX idx_queue_transition_wakes_ref
      ON queue_transition_wakes (wake_ref, phase);
CREATE UNIQUE INDEX idx_workflow_instances_lifecycle_operation
      ON workflow_instances(lifecycle_operation_key)
      WHERE lifecycle_operation_key IS NOT NULL;
CREATE TABLE workflow_frontier_bindings (
      instance_id TEXT NOT NULL REFERENCES workflow_instances(instance_id),
      packet_id TEXT NOT NULL REFERENCES queue_items(qitem_id),
      step_id TEXT NOT NULL,
      branch_drive INTEGER NOT NULL DEFAULT 0,
      hop_count INTEGER NOT NULL DEFAULT 0,
      hops_baseline INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      PRIMARY KEY (instance_id, packet_id),
      UNIQUE (packet_id)
    );
CREATE INDEX idx_workflow_frontier_bindings_instance
      ON workflow_frontier_bindings(instance_id, created_at, packet_id);
CREATE TABLE workflow_failure_occurrences (
      occurrence_id TEXT PRIMARY KEY,
      instance_id TEXT NOT NULL REFERENCES workflow_instances(instance_id),
      failed_packet_id TEXT NOT NULL REFERENCES queue_items(qitem_id),
      step_id TEXT NOT NULL,
      branch_drive INTEGER NOT NULL DEFAULT 0,
      hop_count INTEGER NOT NULL DEFAULT 0,
      hops_baseline INTEGER NOT NULL DEFAULT 0,
      failure_reason TEXT,
      status TEXT NOT NULL DEFAULT 'unresolved',
      redrive_packet_id TEXT REFERENCES queue_items(qitem_id),
      resume_decision TEXT,
      failed_at TEXT NOT NULL,
      resolved_at TEXT
    );
CREATE INDEX idx_workflow_failure_occurrences_instance_status
      ON workflow_failure_occurrences(instance_id, status, failed_at, occurrence_id);
CREATE TABLE "operator_context_mode_bindings" (
      id TEXT PRIMARY KEY,
      scope TEXT NOT NULL CHECK (scope IN ('global_host', 'rig', 'project', 'mission', 'workstream', 'qitem')),
      qualifier TEXT,
      mode TEXT NOT NULL CHECK (mode IN ('sleep', 'desk', 'mobile', 'away', 'focus', 'debug', 'human-led', 'delegated')),
      record_json TEXT NOT NULL,
      set_at TEXT NOT NULL,
      set_by TEXT NOT NULL CHECK (set_by = 'operator')
    );
CREATE INDEX idx_queue_human_intent_updated ON queue_items(human_intent, ts_updated DESC);
CREATE INDEX idx_queue_transitions_handoff_ts
      ON queue_transitions(ts DESC)
      WHERE closure_reason = 'handed_off_to';
CREATE INDEX idx_queue_items_ts_updated
      ON queue_items(ts_updated);
CREATE INDEX idx_events_restore_seq ON events(seq DESC)
      WHERE type IN ('restore.completed', 'restore.subset_completed', 'restore.outcome_reconciled');
CREATE INDEX idx_events_restore_rig_seq ON events(rig_id, seq DESC)
      WHERE type IN ('restore.completed', 'restore.subset_completed', 'restore.outcome_reconciled');
CREATE INDEX idx_events_startup_node_seq ON events(node_id, seq DESC)
      WHERE type IN ('node.startup_challenged','node.startup_proof_skipped','node.startup_proof_verified','node.startup_proof_rejected');
CREATE INDEX idx_project_classifications_area
      ON project_classifications(area);
CREATE INDEX idx_project_classifications_scope_ref
      ON project_classifications(scope_ref);
CREATE TABLE classification_attempts (
      attempt_id TEXT PRIMARY KEY,
      stream_item_id TEXT NOT NULL REFERENCES stream_items(stream_item_id),
      classifier_version TEXT NOT NULL,
      taxonomy_version TEXT NOT NULL,
      evidence_epoch TEXT NOT NULL,
      status TEXT NOT NULL
        CHECK (status IN ('in_flight', 'abstained', 'written', 'error', 'exhausted')),
      attempt_count INTEGER NOT NULL CHECK (attempt_count >= 1),
      execution_id TEXT NOT NULL,
      lease_id TEXT NOT NULL,
      classifier_session TEXT NOT NULL,
      retry_after TEXT,
      reason TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE (stream_item_id, classifier_version, taxonomy_version, evidence_epoch)
    );
CREATE INDEX idx_classification_attempts_status_retry
      ON classification_attempts(status, retry_after);
CREATE TABLE seat_delivery_guards (
      node_id TEXT PRIMARY KEY REFERENCES nodes(id) ON DELETE CASCADE,
      desired INTEGER NOT NULL CHECK (desired IN (0,1)),
      effective INTEGER NOT NULL CHECK (effective IN (0,1)),
      actor TEXT NOT NULL,
      reason TEXT NOT NULL,
      changed_at TEXT NOT NULL
    , desired_config TEXT, effective_config TEXT);
CREATE TABLE seat_delivery_guard_changes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      node_id TEXT NOT NULL,
      desired INTEGER NOT NULL,
      previous_desired INTEGER NOT NULL,
      previous_effective INTEGER NOT NULL,
      actor TEXT NOT NULL,
      reason TEXT NOT NULL,
      requested_at TEXT NOT NULL,
      effective_at TEXT
    , desired_config TEXT);
CREATE INDEX idx_outbox_guard_active ON outbox_entries(destination_session, delivery_state)
      WHERE delivery_state = 'retained';
CREATE TABLE node_permission_selections (
      node_id TEXT PRIMARY KEY REFERENCES nodes(id) ON DELETE CASCADE,
      runtime TEXT NOT NULL CHECK (runtime IN ('codex', 'claude-code')),
      mode TEXT NOT NULL,
      actor TEXT NOT NULL,
      reason TEXT NOT NULL,
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
CREATE INDEX idx_usage_samples_context_latest
      ON usage_samples(seat_session, id) WHERE lane = 'context';
CREATE INDEX idx_usage_samples_window_latest
      ON usage_samples(seat_session, window, id) WHERE lane = 'provider_window';
CREATE TABLE thread_part_map (
      message_ts      TEXT NOT NULL,
      channel         TEXT NOT NULL,
      thread_ts       TEXT NOT NULL,
      seat            TEXT NOT NULL,
      conversation_id TEXT NOT NULL,
      PRIMARY KEY (channel, message_ts)
    );
CREATE INDEX idx_queue_transitions_qitem_id_order
      ON queue_transitions(qitem_id, transition_id);
CREATE INDEX idx_queue_items_recovery_tags
      ON queue_items(qitem_id)
      WHERE (tags LIKE '%"recovery-for:%' OR tags LIKE '%\%') OR tags LIKE '%"stuck-sweep:%';
CREATE TABLE pi_usage_entries (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      pi_session_id TEXT NOT NULL,
      entry_id TEXT NOT NULL,
      parent_entry_id TEXT,
      entry_timestamp TEXT NOT NULL,
      kind TEXT NOT NULL CHECK (kind IN ('assistant', 'usage', 'tool_result', 'compaction', 'branch_summary')),
      usage_category TEXT,
      provider TEXT,
      model TEXT,
      input_tokens INTEGER NOT NULL,
      output_tokens INTEGER NOT NULL,
      cache_read_tokens INTEGER NOT NULL,
      cache_write_tokens INTEGER NOT NULL,
      cost_total REAL,
      stop_reason TEXT,
      origin TEXT NOT NULL CHECK (origin IN ('own', 'inherited', 'unknown')),
      seat_session TEXT NOT NULL,
      node_id TEXT,
      occupant_generation TEXT,
      recorded_at TEXT NOT NULL, api TEXT, response_id TEXT,
      UNIQUE (pi_session_id, entry_id)
    );
CREATE INDEX idx_pi_usage_entries_seat
      ON pi_usage_entries(seat_session, pi_session_id, entry_timestamp);
CREATE TABLE pi_usage_charges (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      pi_session_id TEXT NOT NULL,
      entry_id TEXT NOT NULL,
      generation_id TEXT NOT NULL,
      status TEXT NOT NULL CHECK (status IN ('charged', 'unavailable')),
      total_cost_usd REAL,
      upstream_inference_cost_usd REAL,
      cache_discount_usd REAL,
      is_byok INTEGER,
      provider_name TEXT,
      model TEXT,
      api_type TEXT,
      workspace_id TEXT,
      generation_created_at TEXT,
      credential_source TEXT NOT NULL,
      reason TEXT,
      seat_session TEXT NOT NULL,
      recorded_at TEXT NOT NULL,
      UNIQUE (pi_session_id, entry_id),
      CHECK (status <> 'charged' OR total_cost_usd IS NOT NULL)
    );
CREATE UNIQUE INDEX idx_operator_context_mode_bindings_scope_qualifier_category
      ON operator_context_mode_bindings(scope, qualifier, (mode IN ('human-led', 'delegated')));
CREATE INDEX idx_queue_transitions_ts_qitem
      ON queue_transitions(ts, transition_id, qitem_id);
CREATE INDEX idx_queue_transitions_archive_ts_qitem
      ON queue_transitions_archive(ts, transition_id, qitem_id);
CREATE TABLE "thread_seat_map" (
      thread_ts       TEXT NOT NULL,
      channel         TEXT NOT NULL,
      human           TEXT NOT NULL,
      seat            TEXT NOT NULL,
      conversation_id TEXT NOT NULL,
      state           TEXT NOT NULL DEFAULT 'open' CHECK (state IN ('open', 'closed')),
      opened_at       TEXT NOT NULL,
      closed_at       TEXT,
      origin          TEXT NOT NULL DEFAULT 'posted' CHECK (origin IN ('posted', 'person')),
      PRIMARY KEY (channel, thread_ts)
    );
CREATE INDEX idx_thread_seat_map_pair ON thread_seat_map (human, seat, state);
CREATE TABLE human_quiet_windows (
      entity_id        TEXT PRIMARY KEY,
      window_id        TEXT NOT NULL UNIQUE,
      revision         INTEGER NOT NULL,
      kind             TEXT NOT NULL CHECK (kind IN ('daily', 'until')),
      timezone         TEXT NOT NULL,
      daily_start      TEXT,
      daily_end        TEXT,
      until_at         TEXT,
      source           TEXT NOT NULL,
      set_by           TEXT NOT NULL,
      set_at           TEXT NOT NULL,
      ended_occurrence TEXT,
      ended_by         TEXT,
      ended_at         TEXT,
      cleared_by       TEXT,
      cleared_at       TEXT,
      CHECK ((kind = 'daily' AND daily_start IS NOT NULL AND daily_end IS NOT NULL AND until_at IS NULL)
          OR (kind = 'until' AND until_at IS NOT NULL AND daily_start IS NULL AND daily_end IS NULL))
    );
CREATE TABLE human_saved_modes (
      entity_id            TEXT NOT NULL,
      name                 TEXT NOT NULL,
      availability         TEXT CHECK (availability IS NULL OR availability IN ('available', 'focus', 'away', 'off')),
      expected_back        TEXT,
      decision_room_words  TEXT,
      decision_room_exclusions TEXT NOT NULL DEFAULT '[]',
      quiet_rule           TEXT,
      account_destination  TEXT,
      set_by               TEXT NOT NULL,
      set_at               TEXT NOT NULL,
      PRIMARY KEY (entity_id, name)
    );
CREATE TABLE human_mode_applications (
      application_id TEXT PRIMARY KEY,
      entity_id      TEXT NOT NULL,
      mode_name      TEXT NOT NULL,
      settings       TEXT NOT NULL,
      started_by     TEXT NOT NULL,
      started_at     TEXT NOT NULL,
      scheduled_end  TEXT,
      ended_at       TEXT,
      ended_by       TEXT,
      end_reason     TEXT CHECK (end_reason IS NULL OR end_reason IN ('back', 'scheduled', 'switched'))
    );
CREATE UNIQUE INDEX human_mode_applications_one_active ON human_mode_applications (entity_id) WHERE ended_at IS NULL;
CREATE TABLE human_mode_effects (
      application_id  TEXT NOT NULL REFERENCES human_mode_applications (application_id),
      consumer        TEXT NOT NULL CHECK (consumer IN ('availability', 'quiet', 'decision-room')),
      prior           TEXT,
      change_identity TEXT,
      state           TEXT NOT NULL CHECK (state IN ('active', 'pending', 'failed', 'ended', 'kept', 'handed-off')),
      detail          TEXT,
      updated_at      TEXT NOT NULL,
      PRIMARY KEY (application_id, consumer)
    );
CREATE TABLE "edges" (
      id TEXT PRIMARY KEY,
      rig_id TEXT NOT NULL REFERENCES rigs(id) ON DELETE CASCADE,
      source_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
      target_id TEXT REFERENCES nodes(id) ON DELETE CASCADE,
      target_ref TEXT,
      kind TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      CHECK ((target_id IS NOT NULL AND target_ref IS NULL) OR
             (target_id IS NULL AND target_ref IS NOT NULL AND kind = 'escalates_to'))
    );
CREATE TRIGGER edge_same_rig_insert BEFORE INSERT ON edges BEGIN
      SELECT RAISE(ABORT, 'edge source and target must belong to the same rig')
        WHERE NEW.target_id IS NOT NULL AND
          (SELECT rig_id FROM nodes WHERE id = NEW.source_id) !=
          (SELECT rig_id FROM nodes WHERE id = NEW.target_id);
      SELECT RAISE(ABORT, 'edge rig_id must match source node rig_id')
        WHERE NEW.rig_id != (SELECT rig_id FROM nodes WHERE id = NEW.source_id);
    END;
CREATE TABLE operation_correlations (
    operation_id TEXT PRIMARY KEY,
    request_hash TEXT NOT NULL,
    rig_id TEXT,
    node_ids_json TEXT NOT NULL DEFAULT '[]'
  );
CREATE TABLE rig_terminal_policy_defaults (
      rig_id TEXT PRIMARY KEY REFERENCES rigs(id) ON DELETE CASCADE,
      config_json TEXT NOT NULL,
      actor TEXT,
      instruction TEXT NOT NULL,
      changed_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
CREATE TABLE seat_terminal_policies (
      node_id TEXT PRIMARY KEY REFERENCES nodes(id) ON DELETE CASCADE,
      config_json TEXT NOT NULL,
      source TEXT NOT NULL,
      actor TEXT,
      instruction TEXT NOT NULL,
      changed_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
CREATE TRIGGER node_terminal_policy AFTER INSERT ON nodes BEGIN
      INSERT INTO seat_terminal_policies(node_id,config_json,source,actor,instruction)
      VALUES (NEW.id,
        COALESCE((SELECT config_json FROM rig_terminal_policy_defaults WHERE rig_id=NEW.rig_id),
          '{"preset":"full-control","helpers":[],"exceptions":{}}'),
        CASE WHEN EXISTS(SELECT 1 FROM rig_terminal_policy_defaults WHERE rig_id=NEW.rig_id)
          THEN 'rig_default' ELSE 'current_behaviour' END,
        (SELECT actor FROM rig_terminal_policy_defaults WHERE rig_id=NEW.rig_id),
        COALESCE((SELECT instruction FROM rig_terminal_policy_defaults WHERE rig_id=NEW.rig_id),
          'Current behaviour; no terminal policy was selected.'));
    END;
CREATE TABLE stream_dispositions (
      stream_item_id TEXT PRIMARY KEY REFERENCES stream_items(stream_item_id),
      project_id TEXT UNIQUE REFERENCES project_classifications(project_id),
      disposition TEXT NOT NULL CHECK (disposition IN ('create', 'join', 'duplicate', 'no_action', 'deferred')),
      accepted_by TEXT NOT NULL,
      owner_session TEXT,
      work_qitem_id TEXT,
      effect_operation TEXT NOT NULL CHECK (effect_operation IN ('create', 'note', 'none')),
      effect_qitem_id TEXT,
      effect_destination TEXT,
      template_digest TEXT NOT NULL,
      template_text TEXT NOT NULL,
      request_json TEXT NOT NULL,
      provenance_json TEXT NOT NULL,
      reason TEXT,
      result_json TEXT,
      accepted_at TEXT NOT NULL,
      applied_at TEXT,
      applied_json TEXT,
      CHECK ((disposition = 'deferred') = (project_id IS NULL))
    );
CREATE INDEX idx_stream_dispositions_unapplied ON stream_dispositions(accepted_at) WHERE applied_at IS NULL;
CREATE TABLE stream_subscriptions (
      reader_session TEXT PRIMARY KEY,
      hint_tags TEXT,
      hint_type TEXT,
      read_through_ts TEXT NOT NULL,
      read_through_key TEXT NOT NULL,
      created_by TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
CREATE TABLE stream_retention_marks (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      pruned_through_ts TEXT NOT NULL,
      pruned_through_key TEXT NOT NULL,
      pruned_items INTEGER NOT NULL,
      pruned_at TEXT NOT NULL
    );
CREATE TABLE stream_retention_floor (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      floor_ts TEXT NOT NULL,
      floor_key TEXT NOT NULL,
      recorded_at TEXT NOT NULL
    );
CREATE TABLE stream_reader_actions (
      action_id TEXT PRIMARY KEY,
      stream_item_id TEXT NOT NULL REFERENCES stream_items(stream_item_id),
      reader_session TEXT NOT NULL,
      action TEXT NOT NULL CHECK (action IN ('act', 'decline', 'duplicate')),
      work_qitem_id TEXT,
      duplicate_of TEXT,
      reason TEXT,
      acted_at TEXT NOT NULL,
      CHECK ((action = 'act') = (work_qitem_id IS NOT NULL)),
      CHECK ((action = 'duplicate') = (duplicate_of IS NOT NULL)),
      CHECK (action <> 'decline' OR reason IS NOT NULL)
    );
CREATE INDEX idx_stream_reader_actions_item ON stream_reader_actions(stream_item_id, acted_at);
CREATE TABLE "provider_account_readings" (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      provider TEXT NOT NULL CHECK (provider IN ('codex', 'claude')),
      identity_key TEXT NOT NULL, account_id TEXT, workspace_id TEXT, limit_id TEXT NOT NULL,
      email TEXT, plan_type TEXT, identity_source TEXT NOT NULL, observed_at TEXT NOT NULL,
      limit_evidence TEXT, windows_json TEXT NOT NULL, metadata_json TEXT
    );
CREATE INDEX idx_provider_account_readings_key_time ON provider_account_readings (identity_key, observed_at);
CREATE TABLE activity_grants (
      grant_id      TEXT PRIMARY KEY,
      node_id       TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
      generation    TEXT NOT NULL,
      token_sha256  TEXT NOT NULL UNIQUE,
      issued_by     TEXT NOT NULL,
      issued_at     TEXT NOT NULL,
      revoked_at    TEXT,
      revoke_reason TEXT
    , run_id TEXT, session_id TEXT, activated_at TEXT, binding_json TEXT);
CREATE INDEX idx_activity_grants_active ON activity_grants(node_id) WHERE revoked_at IS NULL;
CREATE TABLE environment_bindings (
      binding_id TEXT PRIMARY KEY,
      version INTEGER NOT NULL CHECK(version = 1),
      node_id TEXT REFERENCES nodes(id),
      seat TEXT NOT NULL,
      ownership TEXT NOT NULL CHECK(ownership IN ('owned', 'attached')),
      config_json TEXT NOT NULL,
      resource_json TEXT,
      projection_json TEXT,
      generation TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
CREATE UNIQUE INDEX environment_binding_node ON environment_bindings(node_id) WHERE node_id IS NOT NULL;
CREATE UNIQUE INDEX environment_binding_seat ON environment_bindings(seat);
CREATE TABLE environment_operations (
      operation_id TEXT PRIMARY KEY,
      binding_id TEXT NOT NULL REFERENCES environment_bindings(binding_id),
      kind TEXT NOT NULL,
      request_json TEXT NOT NULL,
      effect_id TEXT,
      state TEXT NOT NULL CHECK(state IN ('intent', 'requested', 'confirmed', 'refused')),
      receipt_json TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
CREATE TABLE managed_block_writes (
      path_key    TEXT NOT NULL,
      block_id    TEXT NOT NULL,
      body_sha256 TEXT NOT NULL,
      written_at  TEXT NOT NULL,
      PRIMARY KEY (path_key, block_id)
    );
CREATE INDEX idx_outbox_entries_ts_dispatched ON outbox_entries(ts_dispatched, sender_session, destination_session);
CREATE TABLE stream_intake_cursor (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      last_sort_key TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
CREATE INDEX idx_stream_items_archived_sort_key ON stream_items(archived_at, stream_sort_key);
CREATE INDEX idx_stream_items_sort_key ON stream_items(stream_sort_key);
CREATE TABLE "seat_runtime_switches" (
      id TEXT PRIMARY KEY,
      node_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
      canonical_session TEXT NOT NULL,
      staging_session TEXT NOT NULL UNIQUE,
      predecessor_pane TEXT NOT NULL,
      successor_pane TEXT,
      predecessor_generation TEXT NOT NULL,
      successor_generation TEXT NOT NULL UNIQUE,
      from_runtime TEXT NOT NULL CHECK (from_runtime IN ('codex', 'claude-code', 'pi')),
      to_runtime TEXT NOT NULL CHECK (to_runtime IN ('codex', 'claude-code', 'pi')),
      phase TEXT NOT NULL DEFAULT 'preparing'
        CHECK (phase IN ('preparing', 'confirmed', 'committed', 'finished', 'abandoned')),
      reason TEXT NOT NULL,
      requested_by TEXT,
      plan_json TEXT NOT NULL,
      confirmation_note TEXT,
      confirmed_at TEXT,
      successor_resume_type TEXT,
      successor_resume_token TEXT,
      committed_at TEXT,
      -- When the switch should have finished (its successor's start plus the confirmation timeout); a waiting send says so.
      deadline_at TEXT NOT NULL,
      outcome TEXT,
      attention TEXT,
      created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
      updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
      CHECK ((phase IN ('committed', 'finished')) = (committed_at IS NOT NULL))
    );
CREATE UNIQUE INDEX idx_seat_runtime_switches_open ON seat_runtime_switches(node_id)
      WHERE phase IN ('preparing', 'confirmed', 'committed');
CREATE INDEX idx_seat_runtime_switches_predecessor ON seat_runtime_switches(node_id, predecessor_generation)
      WHERE committed_at IS NOT NULL;
CREATE TABLE events_retention_marks (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      low_water_seq INTEGER NOT NULL,
      resume_seq INTEGER,
      prunable_types TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
CREATE TABLE queue_erased_ids (
      qitem_id TEXT PRIMARY KEY,
      erased_at TEXT NOT NULL,
      reason TEXT NOT NULL
    );
CREATE TABLE queue_erased_rigs (
      rig_id TEXT PRIMARY KEY,
      rig_name TEXT NOT NULL,
      members_digest TEXT NOT NULL,
      verified_at TEXT NOT NULL,
      completed_at TEXT
    );
CREATE INDEX idx_outbox_entries_audit_pointer ON outbox_entries(audit_pointer);
CREATE INDEX idx_inbox_entries_absorbed_qitem ON inbox_entries(absorbed_qitem_id);
CREATE INDEX idx_inbox_entries_audit_pointer ON inbox_entries(audit_pointer);
CREATE INDEX idx_stream_dispositions_work_qitem ON stream_dispositions(work_qitem_id);
CREATE INDEX idx_stream_dispositions_effect_qitem ON stream_dispositions(effect_qitem_id);
CREATE INDEX idx_stream_reader_actions_work_qitem ON stream_reader_actions(work_qitem_id);
CREATE INDEX idx_stream_reader_actions_duplicate_of ON stream_reader_actions(duplicate_of);
CREATE TABLE queue_erasure_batches (
      batch_id TEXT PRIMARY KEY,
      committed_at TEXT NOT NULL,
      line_at TEXT
    );
CREATE INDEX idx_queue_erasure_batches_line_pending ON queue_erasure_batches(batch_id) WHERE line_at IS NULL;
CREATE TABLE queue_inbox_checkins (
      session TEXT PRIMARY KEY,
      checked_at TEXT NOT NULL
    );
CREATE INDEX idx_queue_items_handed_off_from ON queue_items(handed_off_from) WHERE handed_off_from IS NOT NULL;
CREATE TABLE network_bindings (
      id TEXT PRIMARY KEY,
      node_id TEXT NOT NULL,
      local_session TEXT NOT NULL,
      hub_url TEXT NOT NULL,
      hub_seat TEXT NOT NULL,
      allow_http INTEGER NOT NULL DEFAULT 0 CHECK (allow_http IN (0, 1)),
      state TEXT NOT NULL CHECK (state IN ('active', 'revoked', 'disconnected')),
      state_reason TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      last_contact_at TEXT,
      last_error TEXT
    , installation_id TEXT, participant_name TEXT, account_removed_at TEXT, account_installation_id TEXT);
CREATE UNIQUE INDEX idx_network_bindings_active_node ON network_bindings(node_id) WHERE state = 'active';
CREATE UNIQUE INDEX idx_network_bindings_active_participant ON network_bindings(hub_url, hub_seat) WHERE state = 'active';
CREATE TABLE network_receipts (
      local_qitem_id TEXT PRIMARY KEY,
      binding_id TEXT NOT NULL,
      hub_qitem_id TEXT NOT NULL,
      created_at TEXT NOT NULL,
      queued_sent_at TEXT,
      pickup_sent_at TEXT,
      settled_at TEXT,
      checked_at TEXT,
      outcome TEXT,
      last_error TEXT
    );
CREATE UNIQUE INDEX idx_network_receipts_hub ON network_receipts(binding_id, hub_qitem_id);
CREATE INDEX idx_network_receipts_open ON network_receipts(binding_id) WHERE settled_at IS NULL;
CREATE INDEX idx_bindings_tmux_session ON bindings(tmux_session)
      WHERE tmux_session IS NOT NULL;
CREATE INDEX idx_sessions_node_latest_id ON sessions(node_id, id DESC);
CREATE INDEX idx_sessions_name_latest_id ON sessions(session_name, id DESC);
CREATE TABLE network_installations (
      id TEXT PRIMARY KEY,
      site TEXT NOT NULL,
      installation_id TEXT NOT NULL,
      name TEXT,
      allow_http INTEGER NOT NULL DEFAULT 0 CHECK (allow_http IN (0, 1)),
      created_at TEXT NOT NULL
    );
CREATE UNIQUE INDEX idx_network_installations_site ON network_installations(site);
CREATE INDEX idx_queue_items_reply_to ON queue_items(reply_to) WHERE reply_to IS NOT NULL;
CREATE INDEX idx_activity_grants_run ON activity_grants(node_id, run_id);
CREATE UNIQUE INDEX idx_activity_grants_active_run ON activity_grants(node_id)
      WHERE run_id IS NOT NULL AND activated_at IS NOT NULL AND revoked_at IS NULL;
CREATE INDEX idx_queue_items_created
      ON queue_items(ts_created DESC);
CREATE INDEX idx_queue_items_active_created
      ON queue_items(CASE WHEN state IN ('pending', 'in-progress', 'blocked') THEN 0 ELSE 1 END, ts_created DESC);
CREATE INDEX idx_queue_items_active_updated
      ON queue_items(CASE WHEN state IN ('pending', 'in-progress', 'blocked') THEN 0 ELSE 1 END, ts_updated DESC);
CREATE INDEX idx_queue_transitions_owner_notification_qitem
      ON queue_transitions(qitem_id, transition_id DESC) WHERE owner_notification_level IS NOT NULL;
CREATE INDEX idx_queue_transitions_archive_owner_notification_qitem
      ON queue_transitions_archive(qitem_id, transition_id DESC) WHERE owner_notification_level IS NOT NULL;
CREATE TABLE seat_handover_attempts (
      id TEXT PRIMARY KEY,
      node_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
      canonical_session TEXT NOT NULL,
      pane TEXT NOT NULL,
      runtime TEXT,
      successor_generation TEXT NOT NULL UNIQUE,
      predecessor_generation TEXT,
      predecessor_session_id TEXT NOT NULL,
      source_raw TEXT NOT NULL,
      reason TEXT NOT NULL,
      operator TEXT,
      resume_type TEXT,
      resume_token TEXT,
      -- What became of the context packet: delivered, sent but unconfirmed (it may still land), or not sent.
      context_delivery TEXT NOT NULL CHECK (context_delivery IN ('delivered', 'unconfirmed', 'not_sent')),
      -- What the launch named, carried to the commit that adopts it: launch-addition notes, the required startup files
      -- the successor started without (#2456), and the exact applied launch observation (W3). JSON, or NULL.
      launch_notes_json TEXT,
      started_without_required_json TEXT,
      applied_launch_json TEXT,
      -- The source's execution outcome the failed handover produced (a rebuild's primed set, gaps and empty-chain reason),
      -- reported as is by the recovery that adopts it. JSON, or NULL.
      source_outcome_json TEXT,
      -- The launch's frozen executable (#2341: the realpath it ran) and whether it is a #! script, as the Claude adapter's
      -- readiness proves a wrapper launch with them; NULL and 0 for a classic launch.
      executable TEXT,
      executable_is_script INTEGER NOT NULL DEFAULT 0 CHECK (executable_is_script IN (0, 1)),
      departing_process TEXT NOT NULL CHECK (departing_process IN ('ended-graceful', 'ended-forced')),
      failed_step TEXT NOT NULL,
      failure_code TEXT NOT NULL,
      phase TEXT NOT NULL DEFAULT 'failed' CHECK (phase IN ('failed', 'adopted', 'abandoned')),
      outcome TEXT,
      created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
      updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
    );
CREATE UNIQUE INDEX idx_seat_handover_attempts_open ON seat_handover_attempts(node_id) WHERE phase = 'failed';
CREATE TABLE seat_runtime_home_records (
      operation_id TEXT PRIMARY KEY,
      node_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
      runtime TEXT NOT NULL,
      revision INTEGER NOT NULL,
      home TEXT NOT NULL,
      slot TEXT NOT NULL CHECK (slot IN ('account_home', 'member_env')),
      previous_home TEXT,
      previous_source TEXT NOT NULL,
      original TEXT,
      occupant_generation TEXT,
      request_hash TEXT NOT NULL,
      reason TEXT NOT NULL,
      operator TEXT,
      created_at TEXT NOT NULL,
      UNIQUE (node_id, revision)
    );
CREATE TABLE rig_delivery_drains (
      id INTEGER PRIMARY KEY,
      rig_id TEXT NOT NULL REFERENCES rigs(id) ON DELETE CASCADE,
      drain_id TEXT NOT NULL,
      owner TEXT NOT NULL,
      started_at TEXT NOT NULL,
      review_at TEXT NOT NULL,
      review_job_id TEXT NOT NULL,
      ended_at TEXT,
      UNIQUE(rig_id, drain_id)
    );
CREATE UNIQUE INDEX idx_rig_delivery_drains_active
      ON rig_delivery_drains(rig_id) WHERE ended_at IS NULL;
CREATE INDEX idx_rig_delivery_drains_review
      ON rig_delivery_drains(review_job_id) WHERE ended_at IS NULL;
CREATE TABLE seat_hook_bridge (
      node_id TEXT PRIMARY KEY REFERENCES nodes(id) ON DELETE CASCADE,
      desired INTEGER NOT NULL CHECK (desired IN (0, 1)),
      actor TEXT NOT NULL,
      reason TEXT NOT NULL,
      changed_at TEXT NOT NULL,
      armed_generation TEXT,
      armed_at TEXT
    );
CREATE TABLE seat_hook_bridge_changes (
      change_id INTEGER PRIMARY KEY AUTOINCREMENT,
      node_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
      desired INTEGER NOT NULL CHECK (desired IN (0, 1)),
      actor TEXT NOT NULL,
      reason TEXT NOT NULL,
      changed_at TEXT NOT NULL
    );
CREATE INDEX idx_queue_items_blocked_routed ON queue_items(blocked_on) WHERE state = 'blocked' AND return_route IS NOT NULL;
CREATE INDEX idx_queue_items_open_routed ON queue_items(state) WHERE return_route IS NOT NULL;
CREATE TABLE core_app_credentials (
      credential_id TEXT PRIMARY KEY,
      app_id TEXT NOT NULL,
      token_hash TEXT NOT NULL UNIQUE,
      actors_json TEXT NOT NULL,
      created_at TEXT NOT NULL,
      revoked_at TEXT
    );
CREATE TABLE core_app_submissions (
      app_id TEXT NOT NULL,
      answer_id TEXT NOT NULL,
      request_id TEXT NOT NULL,
      binding_hash TEXT NOT NULL,
      binding_json TEXT,
      checkpoint_json TEXT,
      receipt_json TEXT,
      erased_at TEXT,
      PRIMARY KEY (app_id, answer_id)
    );
CREATE INDEX core_app_submissions_request ON core_app_submissions(request_id);
