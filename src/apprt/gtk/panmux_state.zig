const std = @import("std");

pub const AgentType = enum {
    codex,
    pi,
    other,
};

pub const SessionPhase = enum {
    starting,
    running,
    waiting_user,
    completed,
    failed,
    exited,
};

pub const Severity = enum {
    none,
    info,
    warning,
    @"error",
};

pub const ReplyAttention = enum {
    none,
    unseen,
    seen,
};

pub const AttentionKind = enum {
    turn_complete,
    needs_review,
    system_notification,
    session_failed,
    legacy_notify,
};

pub const BadgeKind = enum {
    empty,
    running,
    unseen,
    seen,
    info,
    warning,
    @"error",
    other,
};

pub const OverlayKind = enum {
    none,
    info,
    warning,
    @"error",
    other,
};

pub const WorkspaceState = struct {
    workspace_id: []u8,
    tab_id: []u8,
    selected_surface_id: ?[]u8 = null,
    stable_title: []u8,
    display_cwd: ?[]u8 = null,
    selected: bool = false,
    last_event_at_ms: i64 = 0,

    fn deinit(self: *WorkspaceState, alloc: std.mem.Allocator) void {
        alloc.free(self.workspace_id);
        alloc.free(self.tab_id);
        alloc.free(self.stable_title);
        if (self.selected_surface_id) |value| alloc.free(value);
        if (self.display_cwd) |value| alloc.free(value);
        self.* = undefined;
    }
};

pub const AgentSessionState = struct {
    session_id: []u8,
    workspace_id: []u8,
    tab_id: []u8,
    surface_id: ?[]u8 = null,
    agent_type: AgentType,
    agent_label: []u8,
    phase: SessionPhase,
    severity: Severity,
    reply_attention: ReplyAttention = .none,
    draft_started: bool = false,
    status_text: ?[]u8 = null,
    turn_id: ?[]u8 = null,
    last_summary: ?[]u8 = null,
    last_attention_id: ?[]u8 = null,
    started_at_ms: i64,
    updated_at_ms: i64,

    fn deinit(self: *AgentSessionState, alloc: std.mem.Allocator) void {
        alloc.free(self.session_id);
        alloc.free(self.workspace_id);
        alloc.free(self.tab_id);
        alloc.free(self.agent_label);
        if (self.surface_id) |value| alloc.free(value);
        if (self.status_text) |value| alloc.free(value);
        if (self.turn_id) |value| alloc.free(value);
        if (self.last_summary) |value| alloc.free(value);
        if (self.last_attention_id) |value| alloc.free(value);
        self.* = undefined;
    }
};

pub const AttentionItem = struct {
    attention_id: []u8,
    logical_key: ?[]u8 = null,
    workspace_id: []u8,
    session_id: ?[]u8 = null,
    kind: AttentionKind,
    severity: Severity,
    title: []u8,
    body: ?[]u8 = null,
    ack_required: bool,
    acked_at_ms: ?i64 = null,
    created_at_ms: i64,

    fn deinit(self: *AttentionItem, alloc: std.mem.Allocator) void {
        alloc.free(self.attention_id);
        if (self.logical_key) |value| alloc.free(value);
        alloc.free(self.workspace_id);
        alloc.free(self.title);
        if (self.session_id) |value| alloc.free(value);
        if (self.body) |value| alloc.free(value);
        self.* = undefined;
    }
};

pub const WorkspaceSnapshot = struct {
    workspace_id: []const u8,
    running_count: u32 = 0,
    unread_count: u32 = 0,
    unseen_count: u32 = 0,
    seen_count: u32 = 0,
    badge_kind: BadgeKind = .empty,
    badge_label: ?[]const u8 = null,
    overlay_kind: OverlayKind = .none,
    tooltip: ?[]const u8 = null,
};

pub const SessionUpdate = struct {
    workspace_id: []const u8,
    tab_id: []const u8,
    surface_id: ?[]const u8 = null,
    session_id: []const u8,
    agent_type: AgentType = .other,
    agent_label: []const u8,
    phase: SessionPhase,
    severity: Severity = .none,
    reply_attention: ?ReplyAttention = null,
    draft_started: ?bool = null,
    status_text: ?[]const u8 = null,
    turn_id: ?[]const u8 = null,
    summary: ?[]const u8 = null,
};

pub const AttentionUpdate = struct {
    workspace_id: []const u8,
    session_id: ?[]const u8 = null,
    kind: AttentionKind = .legacy_notify,
    severity: Severity = .info,
    title: []const u8,
    body: ?[]const u8 = null,
    ack_required: bool = true,
    logical_key: ?[]const u8 = null,
};

pub const Store = struct {
    alloc: std.mem.Allocator,
    workspace_items: std.ArrayListUnmanaged(WorkspaceState) = .empty,
    session_items: std.ArrayListUnmanaged(AgentSessionState) = .empty,
    attention_items: std.ArrayListUnmanaged(AttentionItem) = .empty,
    next_attention_id: u64 = 1,

    pub fn init(alloc: std.mem.Allocator) Store {
        return .{ .alloc = alloc };
    }

    pub fn deinit(self: *Store) void {
        for (self.workspace_items.items) |*workspace| workspace.deinit(self.alloc);
        self.workspace_items.deinit(self.alloc);

        for (self.session_items.items) |*session| session.deinit(self.alloc);
        self.session_items.deinit(self.alloc);

        for (self.attention_items.items) |*attention| attention.deinit(self.alloc);
        self.attention_items.deinit(self.alloc);
    }

    pub fn workspaces(self: *const Store) []const WorkspaceState {
        return self.workspace_items.items;
    }

    pub fn sessions(self: *const Store) []const AgentSessionState {
        return self.session_items.items;
    }

    pub fn attentions(self: *const Store) []const AttentionItem {
        return self.attention_items.items;
    }

    pub fn latestUnreadAttentionForSession(self: *const Store, session_id: []const u8) ?*const AttentionItem {
        var latest: ?*const AttentionItem = null;
        for (self.attention_items.items) |*attention| {
            if (!attention.ack_required or attention.acked_at_ms != null) continue;
            const attention_session_id = attention.session_id orelse continue;
            if (!std.mem.eql(u8, attention_session_id, session_id)) continue;
            if (latest == null or attention.created_at_ms > latest.?.created_at_ms) {
                latest = attention;
            }
        }

        return latest;
    }

    pub fn latestAttentionForSession(self: *const Store, session_id: []const u8) ?*const AttentionItem {
        var latest: ?*const AttentionItem = null;
        for (self.attention_items.items) |*attention| {
            const attention_session_id = attention.session_id orelse continue;
            if (!std.mem.eql(u8, attention_session_id, session_id)) continue;
            if (latest == null or attention.created_at_ms > latest.?.created_at_ms) {
                latest = attention;
            }
        }

        return latest;
    }

    pub fn sessionNeedsInput(self: *const Store, session_id: []const u8) bool {
        const idx = self.findSessionIndex(session_id) orelse return false;
        return self.session_items.items[idx].reply_attention == .unseen;
    }

    pub fn sessionHasReplyAttention(self: *const Store, session_id: []const u8) bool {
        const idx = self.findSessionIndex(session_id) orelse return false;
        return self.session_items.items[idx].reply_attention != .none;
    }

    pub fn ackSessionAttention(self: *Store, session_id: []const u8) u32 {
        var count: u32 = 0;
        for (self.attention_items.items) |*attention| {
            if (!attention.ack_required or attention.acked_at_ms != null) continue;
            const attention_session_id = attention.session_id orelse continue;
            if (!std.mem.eql(u8, attention_session_id, session_id)) continue;
            attention.acked_at_ms = nowMs();
            count += 1;
        }

        return count;
    }

    pub fn ensureWorkspace(self: *Store, workspace_id: []const u8, tab_id: []const u8) !void {
        _ = try self.ensureWorkspaceRecord(workspace_id, tab_id);
    }

    pub fn forgetWorkspace(self: *Store, workspace_id: []const u8) void {
        var i: usize = 0;
        while (i < self.workspace_items.items.len) {
            if (std.mem.eql(u8, self.workspace_items.items[i].workspace_id, workspace_id)) {
                var removed = self.workspace_items.swapRemove(i);
                removed.deinit(self.alloc);
                break;
            }
            i += 1;
        }

        i = 0;
        while (i < self.session_items.items.len) {
            if (std.mem.eql(u8, self.session_items.items[i].workspace_id, workspace_id)) {
                var removed = self.session_items.swapRemove(i);
                removed.deinit(self.alloc);
                continue;
            }
            i += 1;
        }

        i = 0;
        while (i < self.attention_items.items.len) {
            if (std.mem.eql(u8, self.attention_items.items[i].workspace_id, workspace_id)) {
                var removed = self.attention_items.swapRemove(i);
                removed.deinit(self.alloc);
                continue;
            }
            i += 1;
        }
    }

    pub fn setSelectedSurface(self: *Store, workspace_id: []const u8, tab_id: []const u8, surface_id: ?[]const u8) !void {
        const workspace = try self.ensureWorkspaceRecord(workspace_id, tab_id);
        try replaceOptionalOwned(self.alloc, &workspace.selected_surface_id, surface_id);
        workspace.last_event_at_ms = nowMs();
    }

    pub fn updateSession(self: *Store, update: SessionUpdate) !void {
        const workspace = try self.ensureWorkspaceRecord(update.workspace_id, update.tab_id);
        workspace.last_event_at_ms = nowMs();

        const idx = try self.resolveSessionIndex(update);
        const session = &self.session_items.items[idx];

        try replaceOwned(self.alloc, &session.workspace_id, update.workspace_id);
        try replaceOwned(self.alloc, &session.tab_id, update.tab_id);
        if (update.surface_id != null) {
            try replaceOptionalOwned(self.alloc, &session.surface_id, update.surface_id);
        }
        try replaceOwned(self.alloc, &session.agent_label, update.agent_label);
        try replaceOptionalOwned(self.alloc, &session.status_text, update.status_text);
        try replaceOptionalOwned(self.alloc, &session.turn_id, update.turn_id);
        try replaceOptionalOwned(self.alloc, &session.last_summary, update.summary);
        session.agent_type = update.agent_type;
        session.phase = update.phase;
        session.severity = update.severity;
        if (update.reply_attention) |value| {
            session.reply_attention = value;
        } else if (update.agent_type == .codex and isProcessRunning(update.phase)) {
            session.reply_attention = .none;
        }
        if (update.draft_started) |value| {
            session.draft_started = value;
        } else if (update.agent_type == .codex and isProcessRunning(update.phase)) {
            session.draft_started = false;
        }
        if (session.started_at_ms == 0) session.started_at_ms = nowMs();
        session.updated_at_ms = nowMs();
    }

    pub fn touchSession(self: *Store, update: SessionUpdate) !void {
        const idx = self.findSessionIndex(update.session_id) orelse return;
        const session = &self.session_items.items[idx];
        if (update.surface_id != null) {
            try replaceOptionalOwned(self.alloc, &session.surface_id, update.surface_id);
        }
        try replaceOptionalOwned(self.alloc, &session.turn_id, update.turn_id);
        try replaceOptionalOwned(self.alloc, &session.last_summary, update.summary);
        try replaceOptionalOwned(self.alloc, &session.status_text, update.status_text);
        if (update.severity != .none) session.severity = update.severity;
        if (update.reply_attention) |value| session.reply_attention = value;
        if (update.draft_started) |value| session.draft_started = value;
        session.updated_at_ms = nowMs();
    }

    pub fn recordReplyCompletion(
        self: *Store,
        update: SessionUpdate,
        attention: AttentionUpdate,
    ) ![]const u8 {
        std.debug.assert(update.agent_type == .codex);
        std.debug.assert(update.reply_attention != null);

        try self.updateSession(update);
        const attention_id = try self.raiseAttention(attention);

        const idx = self.findSessionIndex(update.session_id) orelse return attention_id;
        const session = &self.session_items.items[idx];
        try replaceOptionalOwned(self.alloc, &session.last_attention_id, attention_id);
        return attention_id;
    }

    pub fn markSessionViewed(
        self: *Store,
        workspace_id: []const u8,
        session_id: ?[]const u8,
        surface_id: ?[]const u8,
    ) bool {
        const idx = self.resolveBoundSessionIndex(workspace_id, session_id, surface_id) orelse return false;
        const session = &self.session_items.items[idx];
        if (session.agent_type != .codex) return false;
        if (session.reply_attention != .unseen) return false;
        session.reply_attention = .seen;
        session.updated_at_ms = nowMs();
        return true;
    }

    pub fn markReplyDraftStarted(
        self: *Store,
        workspace_id: []const u8,
        session_id: ?[]const u8,
        surface_id: ?[]const u8,
    ) bool {
        const idx = self.resolveBoundSessionIndex(workspace_id, session_id, surface_id) orelse return false;
        const session = &self.session_items.items[idx];
        if (session.agent_type != .codex) return false;
        if (session.reply_attention == .none) return false;
        if (surface_id) |value| {
            const bound_surface_id = session.surface_id orelse return false;
            if (!std.mem.eql(u8, bound_surface_id, value)) return false;
        }
        if (session.draft_started) return false;
        session.draft_started = true;
        session.updated_at_ms = nowMs();
        return true;
    }

    pub fn submitReply(
        self: *Store,
        workspace_id: []const u8,
        session_id: ?[]const u8,
        surface_id: ?[]const u8,
    ) bool {
        const idx = self.resolveBoundSessionIndex(workspace_id, session_id, surface_id) orelse return false;
        const session = &self.session_items.items[idx];
        if (session.agent_type != .codex) return false;
        if (session.reply_attention == .none or !session.draft_started) return false;
        if (surface_id) |value| {
            const bound_surface_id = session.surface_id orelse return false;
            if (!std.mem.eql(u8, bound_surface_id, value)) return false;
        }
        session.phase = .running;
        session.reply_attention = .none;
        session.draft_started = false;
        session.updated_at_ms = nowMs();
        _ = self.ackSessionAttention(session.session_id);
        return true;
    }

    pub fn clearStatus(self: *Store, workspace_id: []const u8, session_id: ?[]const u8, surface_id: ?[]const u8) void {
        var i: usize = 0;
        while (i < self.session_items.items.len) {
            const session = &self.session_items.items[i];
            if (!std.mem.eql(u8, session.workspace_id, workspace_id)) {
                i += 1;
                continue;
            }
            if (session_id) |value| {
                if (!std.mem.eql(u8, session.session_id, value)) {
                    i += 1;
                    continue;
                }
            } else if (surface_id) |value| {
                const session_surface_id = session.surface_id orelse {
                    i += 1;
                    continue;
                };
                if (!std.mem.eql(u8, session_surface_id, value)) {
                    i += 1;
                    continue;
                }
            }

            _ = self.ackSessionAttention(session.session_id);
            var removed = self.session_items.swapRemove(i);
            removed.deinit(self.alloc);
        }
    }

    pub fn finishLegacySurfaceSession(self: *Store, workspace_id: []const u8, surface_id: []const u8) void {
        var i: usize = 0;
        while (i < self.session_items.items.len) : (i += 1) {
            const session = &self.session_items.items[i];
            const session_surface_id = session.surface_id orelse continue;
            if (!std.mem.eql(u8, session.workspace_id, workspace_id)) continue;
            if (!std.mem.eql(u8, session_surface_id, surface_id)) continue;
            if (!std.mem.startsWith(u8, session.session_id, "legacy:")) continue;

            _ = self.ackSessionAttention(session.session_id);
            if (session.last_summary == null and session.status_text == null) {
                var removed = self.session_items.swapRemove(i);
                removed.deinit(self.alloc);
                return;
            }

            session.phase = .exited;
            session.updated_at_ms = nowMs();
            return;
        }
    }

    pub fn raiseAttention(self: *Store, update: AttentionUpdate) ![]const u8 {
        if (update.logical_key) |logical_key| {
            if (self.findAttentionIndexByLogicalKey(update.workspace_id, logical_key)) |idx| {
                const attention = &self.attention_items.items[idx];
                try replaceOwned(self.alloc, &attention.workspace_id, update.workspace_id);
                try replaceOptionalOwned(self.alloc, &attention.session_id, update.session_id);
                try replaceOwned(self.alloc, &attention.title, update.title);
                try replaceOptionalOwned(self.alloc, &attention.body, update.body);
                attention.kind = update.kind;
                attention.severity = update.severity;
                attention.ack_required = update.ack_required;
                attention.acked_at_ms = null;
                attention.created_at_ms = nowMs();

                if (update.session_id) |session_id| {
                    if (self.findSessionIndex(session_id)) |session_idx| {
                        const session = &self.session_items.items[session_idx];
                        if (update.body) |body| try replaceOptionalOwned(self.alloc, &session.last_summary, body);
                        if (update.severity != .none) session.severity = update.severity;
                        try replaceOptionalOwned(self.alloc, &session.last_attention_id, attention.attention_id);
                        session.updated_at_ms = nowMs();
                    }
                }

                return attention.attention_id;
            }
        }

        const attention_id = try std.fmt.allocPrint(self.alloc, "attention-{d}", .{self.next_attention_id});
        errdefer self.alloc.free(attention_id);
        self.next_attention_id += 1;

        try self.ensureWorkspace(update.workspace_id, update.workspace_id);
        try self.attention_items.append(self.alloc, .{
            .attention_id = attention_id,
            .logical_key = if (update.logical_key) |value| try self.alloc.dupe(u8, value) else null,
            .workspace_id = try self.alloc.dupe(u8, update.workspace_id),
            .session_id = if (update.session_id) |value| try self.alloc.dupe(u8, value) else null,
            .kind = update.kind,
            .severity = update.severity,
            .title = try self.alloc.dupe(u8, update.title),
            .body = if (update.body) |value| try self.alloc.dupe(u8, value) else null,
            .ack_required = update.ack_required,
            .acked_at_ms = null,
            .created_at_ms = nowMs(),
        });

        if (update.session_id) |session_id| {
            if (self.findSessionIndex(session_id)) |idx| {
                const session = &self.session_items.items[idx];
                if (update.body) |body| try replaceOptionalOwned(self.alloc, &session.last_summary, body);
                if (update.severity != .none) session.severity = update.severity;
                try replaceOptionalOwned(self.alloc, &session.last_attention_id, attention_id);
                session.updated_at_ms = nowMs();
            }
        }

        return self.attention_items.items[self.attention_items.items.len - 1].attention_id;
    }

    pub fn ackAttention(self: *Store, attention_id: []const u8) bool {
        for (self.attention_items.items) |*attention| {
            if (!std.mem.eql(u8, attention.attention_id, attention_id)) continue;
            attention.acked_at_ms = nowMs();
            return true;
        }

        return false;
    }

    pub fn ackWorkspaceAttention(self: *Store, workspace_id: []const u8) u32 {
        var count: u32 = 0;
        for (self.attention_items.items) |*attention| {
            if (!std.mem.eql(u8, attention.workspace_id, workspace_id)) continue;
            if (!attention.ack_required or attention.acked_at_ms != null) continue;
            attention.acked_at_ms = nowMs();
            count += 1;
        }

        return count;
    }

    pub fn snapshotWorkspace(self: *const Store, workspace_id: []const u8) ?WorkspaceSnapshot {
        const stable_workspace_id = self.stableWorkspaceId(workspace_id) orelse return null;
        if (self.snapshotActiveCodexWorkspace(stable_workspace_id)) |snapshot| return snapshot;
        return self.snapshotLegacyWorkspace(stable_workspace_id);
    }

    fn ensureWorkspaceRecord(self: *Store, workspace_id: []const u8, tab_id: []const u8) !*WorkspaceState {
        if (self.findWorkspaceIndex(workspace_id)) |idx| {
            const workspace = &self.workspace_items.items[idx];
            try replaceOwned(self.alloc, &workspace.tab_id, tab_id);
            if (workspace.stable_title.len == 0) {
                try replaceOwned(self.alloc, &workspace.stable_title, workspace_id);
            }
            return workspace;
        }

        try self.workspace_items.append(self.alloc, .{
            .workspace_id = try self.alloc.dupe(u8, workspace_id),
            .tab_id = try self.alloc.dupe(u8, tab_id),
            .selected_surface_id = null,
            .stable_title = try self.alloc.dupe(u8, workspace_id),
            .display_cwd = null,
            .selected = false,
            .last_event_at_ms = nowMs(),
        });
        return &self.workspace_items.items[self.workspace_items.items.len - 1];
    }

    fn resolveSessionIndex(self: *Store, update: SessionUpdate) !usize {
        if (self.findSessionIndex(update.session_id)) |idx| return idx;

        if (update.surface_id) |surface_id| {
            if (self.findActiveSurfaceSessionIndex(update.workspace_id, surface_id, update.agent_type)) |idx| {
                const session = &self.session_items.items[idx];
                if (!std.mem.eql(u8, session.session_id, update.session_id)) {
                    try replaceOwned(self.alloc, &session.session_id, update.session_id);
                }
                return idx;
            }
        }

        try self.session_items.append(self.alloc, .{
            .session_id = try self.alloc.dupe(u8, update.session_id),
            .workspace_id = try self.alloc.dupe(u8, update.workspace_id),
            .tab_id = try self.alloc.dupe(u8, update.tab_id),
            .surface_id = if (update.surface_id) |value| try self.alloc.dupe(u8, value) else null,
            .agent_type = update.agent_type,
            .agent_label = try self.alloc.dupe(u8, update.agent_label),
            .phase = update.phase,
            .severity = update.severity,
            .reply_attention = update.reply_attention orelse .none,
            .draft_started = update.draft_started orelse false,
            .status_text = if (update.status_text) |value| try self.alloc.dupe(u8, value) else null,
            .turn_id = if (update.turn_id) |value| try self.alloc.dupe(u8, value) else null,
            .last_summary = if (update.summary) |value| try self.alloc.dupe(u8, value) else null,
            .last_attention_id = null,
            .started_at_ms = nowMs(),
            .updated_at_ms = nowMs(),
        });
        return self.session_items.items.len - 1;
    }

    fn findWorkspaceIndex(self: *const Store, workspace_id: []const u8) ?usize {
        for (self.workspace_items.items, 0..) |workspace, idx| {
            if (std.mem.eql(u8, workspace.workspace_id, workspace_id)) return idx;
        }

        return null;
    }

    fn findSessionIndex(self: *const Store, session_id: []const u8) ?usize {
        for (self.session_items.items, 0..) |session, idx| {
            if (std.mem.eql(u8, session.session_id, session_id)) return idx;
        }

        return null;
    }

    fn findActiveSurfaceSessionIndex(
        self: *const Store,
        workspace_id: []const u8,
        surface_id: []const u8,
        agent_type: AgentType,
    ) ?usize {
        for (self.session_items.items, 0..) |session, idx| {
            if (!std.mem.eql(u8, session.workspace_id, workspace_id)) continue;
            const existing_surface_id = session.surface_id orelse continue;
            if (!std.mem.eql(u8, existing_surface_id, surface_id)) continue;
            if (session.agent_type != agent_type) continue;
            if (!isReplyRelevant(&session)) continue;
            return idx;
        }

        return null;
    }

    fn findBoundSessionIndex(self: *const Store, workspace_id: []const u8, surface_id: []const u8) ?usize {
        var best_idx: ?usize = null;
        var best_updated_at: i64 = std.math.minInt(i64);

        for (self.session_items.items, 0..) |session, idx| {
            if (!std.mem.eql(u8, session.workspace_id, workspace_id)) continue;
            const existing_surface_id = session.surface_id orelse continue;
            if (!std.mem.eql(u8, existing_surface_id, surface_id)) continue;
            if (session.agent_type != .codex) continue;
            if (!isReplyRelevant(&session)) continue;
            if (best_idx == null or session.updated_at_ms > best_updated_at) {
                best_idx = idx;
                best_updated_at = session.updated_at_ms;
            }
        }

        return best_idx;
    }

    fn resolveBoundSessionIndex(
        self: *const Store,
        workspace_id: []const u8,
        session_id: ?[]const u8,
        surface_id: ?[]const u8,
    ) ?usize {
        if (session_id) |value| {
            const idx = self.findSessionIndex(value) orelse return null;
            if (!std.mem.eql(u8, self.session_items.items[idx].workspace_id, workspace_id)) return null;
            return idx;
        }

        if (surface_id) |value| return self.findBoundSessionIndex(workspace_id, value);

        const workspace_idx = self.findWorkspaceIndex(workspace_id) orelse return null;
        const selected_surface_id = self.workspace_items.items[workspace_idx].selected_surface_id orelse return null;
        return self.findBoundSessionIndex(workspace_id, selected_surface_id);
    }

    fn stableWorkspaceId(self: *const Store, workspace_id: []const u8) ?[]const u8 {
        if (self.findWorkspaceIndex(workspace_id)) |idx| return self.workspace_items.items[idx].workspace_id;

        for (self.session_items.items) |session| {
            if (std.mem.eql(u8, session.workspace_id, workspace_id)) return session.workspace_id;
        }

        for (self.attention_items.items) |attention| {
            if (std.mem.eql(u8, attention.workspace_id, workspace_id)) return attention.workspace_id;
        }

        return null;
    }

    fn findAttentionIndexByLogicalKey(self: *const Store, workspace_id: []const u8, logical_key: []const u8) ?usize {
        for (self.attention_items.items, 0..) |attention, idx| {
            if (!std.mem.eql(u8, attention.workspace_id, workspace_id)) continue;
            const existing_key = attention.logical_key orelse continue;
            if (std.mem.eql(u8, existing_key, logical_key)) return idx;
        }

        return null;
    }

    fn snapshotActiveCodexWorkspace(self: *const Store, workspace_id: []const u8) ?WorkspaceSnapshot {
        var snapshot: WorkspaceSnapshot = .{
            .workspace_id = workspace_id,
        };
        var has_active_codex = false;
        var latest_running_session: ?*const AgentSessionState = null;
        var latest_unseen_attention: ?*const AttentionItem = null;
        var latest_seen_attention: ?*const AttentionItem = null;

        for (self.session_items.items) |*session| {
            if (!std.mem.eql(u8, session.workspace_id, workspace_id)) continue;
            if (session.agent_type != .codex) continue;
            if (!isReplyRelevant(session)) continue;

            has_active_codex = true;
            switch (session.reply_attention) {
                .unseen => {
                    snapshot.unread_count += 1;
                    snapshot.unseen_count += 1;
                    if (self.latestAttentionForSession(session.session_id)) |attention| {
                        if (latest_unseen_attention == null or attention.created_at_ms > latest_unseen_attention.?.created_at_ms) {
                            latest_unseen_attention = attention;
                        }
                    }
                },
                .seen => {
                    snapshot.seen_count += 1;
                    if (self.latestAttentionForSession(session.session_id)) |attention| {
                        if (latest_seen_attention == null or attention.created_at_ms > latest_seen_attention.?.created_at_ms) {
                            latest_seen_attention = attention;
                        }
                    }
                },
                .none => {},
            }

            if (isProcessRunning(session.phase)) {
                snapshot.running_count += 1;
                if (latest_running_session == null or session.updated_at_ms > latest_running_session.?.updated_at_ms) {
                    latest_running_session = session;
                }
            }
        }

        if (!has_active_codex) return null;

        if (snapshot.unseen_count > 0) {
            snapshot.badge_kind = .unseen;
            if (latest_unseen_attention) |attention| {
                snapshot.tooltip = attention.body orelse attention.title;
            }
            return snapshot;
        }

        if (snapshot.seen_count > 0) {
            snapshot.badge_kind = .seen;
            if (latest_seen_attention) |attention| {
                snapshot.tooltip = attention.body orelse attention.title;
            }
            return snapshot;
        }

        if (snapshot.running_count > 0) {
            snapshot.badge_kind = .running;
            if (latest_running_session) |session| {
                snapshot.tooltip = session.last_summary orelse session.status_text;
            }
        }
        return snapshot;
    }

    fn snapshotLegacyWorkspace(self: *const Store, workspace_id: []const u8) ?WorkspaceSnapshot {
        var snapshot: WorkspaceSnapshot = .{
            .workspace_id = workspace_id,
        };
        var latest_session: ?*const AgentSessionState = null;
        var strongest_attention: ?*const AttentionItem = null;

        for (self.session_items.items) |*session| {
            if (!std.mem.eql(u8, session.workspace_id, workspace_id)) continue;
            if (session.agent_type == .codex) continue;
            if (session.phase == .running) snapshot.running_count += 1;

            if (latest_session == null or session.updated_at_ms > latest_session.?.updated_at_ms) {
                latest_session = session;
            }
        }

        for (self.attention_items.items) |*attention| {
            if (!std.mem.eql(u8, attention.workspace_id, workspace_id)) continue;
            if (!attention.ack_required or attention.acked_at_ms != null) continue;
            if (self.attentionBelongsToCodexSession(attention)) continue;
            snapshot.unread_count += 1;

            if (strongest_attention == null) {
                strongest_attention = attention;
                continue;
            }

            const current_severity = strongest_attention.?.severity;
            if (severityPriority(attention.severity) > severityPriority(current_severity) or
                (severityPriority(attention.severity) == severityPriority(current_severity) and
                    attention.created_at_ms > strongest_attention.?.created_at_ms))
            {
                strongest_attention = attention;
            }
        }

        if (snapshot.running_count > 0) {
            snapshot.badge_kind = .running;
            if (latest_session) |session| {
                snapshot.tooltip = session.last_summary orelse session.status_text;
            }
        } else if (latest_session) |session| {
            snapshot.badge_kind = badgeKindForSession(session);
            snapshot.badge_label = badgeLabelForSession(session);
            snapshot.tooltip = session.last_summary orelse session.status_text;
        }

        if (strongest_attention) |attention| {
            snapshot.overlay_kind = overlayKindForSeverity(attention.severity);
            snapshot.tooltip = attention.body orelse attention.title;
        }

        if (latest_session == null and strongest_attention == null) return null;
        return snapshot;
    }

    fn attentionBelongsToCodexSession(self: *const Store, attention: *const AttentionItem) bool {
        const session_id = attention.session_id orelse return false;
        const idx = self.findSessionIndex(session_id) orelse return false;
        return self.session_items.items[idx].agent_type == .codex;
    }
};

pub fn agentTypeFromText(value: ?[]const u8) AgentType {
    const text = value orelse return .other;
    if (std.mem.eql(u8, text, "codex")) return .codex;
    if (std.mem.eql(u8, text, "pi")) return .pi;
    return .other;
}

pub fn agentTypeText(value: AgentType) []const u8 {
    return @tagName(value);
}

pub fn phaseText(value: SessionPhase) []const u8 {
    return @tagName(value);
}

pub fn severityText(value: Severity) []const u8 {
    return @tagName(value);
}

pub fn replyAttentionText(value: ReplyAttention) []const u8 {
    return @tagName(value);
}

pub fn severityFromState(state: []const u8) Severity {
    if (std.mem.eql(u8, state, "info")) return .info;
    if (std.mem.eql(u8, state, "warn") or std.mem.eql(u8, state, "warning")) return .warning;
    if (std.mem.eql(u8, state, "error")) return .@"error";
    return .none;
}

pub fn phaseFromState(state: []const u8) SessionPhase {
    if (std.mem.eql(u8, state, "running")) return .running;
    if (std.mem.eql(u8, state, "error")) return .failed;
    if (state.len == 0) return .exited;
    return .completed;
}

pub fn isStandardState(state: []const u8) bool {
    return std.mem.eql(u8, state, "running") or
        std.mem.eql(u8, state, "info") or
        std.mem.eql(u8, state, "warn") or
        std.mem.eql(u8, state, "warning") or
        std.mem.eql(u8, state, "error");
}

fn badgeKindForSession(session: *const AgentSessionState) BadgeKind {
    if (session.phase == .running) return .running;
    if (session.status_text) |status_text| {
        if (std.mem.eql(u8, status_text, "info")) return .info;
        if (std.mem.eql(u8, status_text, "warn") or std.mem.eql(u8, status_text, "warning")) return .warning;
        if (std.mem.eql(u8, status_text, "error")) return .@"error";
        return .other;
    }

    return switch (session.severity) {
        .none => .empty,
        .info => .info,
        .warning => .warning,
        .@"error" => .@"error",
    };
}

fn badgeLabelForSession(session: *const AgentSessionState) ?[]const u8 {
    const status_text = session.status_text orelse return switch (badgeKindForSession(session)) {
        .other,
        .empty,
        .running,
        .unseen,
        .seen,
        .info,
        .warning,
        .@"error",
        => null,
    };
    if (isStandardState(status_text)) return null;
    return status_text;
}

fn overlayKindForSeverity(severity: Severity) OverlayKind {
    return switch (severity) {
        .none => .none,
        .info => .info,
        .warning => .warning,
        .@"error" => .@"error",
    };
}

fn severityPriority(severity: Severity) u8 {
    return switch (severity) {
        .none => 0,
        .info => 1,
        .warning => 2,
        .@"error" => 3,
    };
}

pub fn isProcessRunning(phase: SessionPhase) bool {
    return switch (phase) {
        .starting, .running => true,
        .waiting_user, .completed, .failed, .exited => false,
    };
}

pub fn isReplyRelevant(session: *const AgentSessionState) bool {
    if (session.reply_attention != .none) return true;
    return switch (session.phase) {
        .starting, .running, .waiting_user, .failed => true,
        .completed, .exited => false,
    };
}

fn nowMs() i64 {
    return std.time.milliTimestamp();
}

fn replaceOwned(alloc: std.mem.Allocator, field: *[]u8, value: []const u8) !void {
    if (std.mem.eql(u8, field.*, value)) return;
    alloc.free(field.*);
    field.* = try alloc.dupe(u8, value);
}

fn replaceOptionalOwned(alloc: std.mem.Allocator, field: *?[]u8, value: ?[]const u8) !void {
    if (field.*) |current| {
        if (value) |next| {
            if (std.mem.eql(u8, current, next)) return;
        }
        alloc.free(current);
        field.* = null;
    }
    if (value) |next| field.* = try alloc.dupe(u8, next);
}

test "store tracks sessions and persistent attention separately" {
    var store = Store.init(std.testing.allocator);
    defer store.deinit();

    try store.ensureWorkspace("tab-a", "tab-a");
    try store.updateSession(.{
        .workspace_id = "tab-a",
        .tab_id = "tab-a",
        .surface_id = "surface-a",
        .session_id = "session-a",
        .agent_type = .codex,
        .agent_label = "Codex",
        .phase = .running,
        .severity = .none,
    });

    {
        const snapshot = store.snapshotWorkspace("tab-a").?;
        try std.testing.expectEqual(@as(u32, 1), snapshot.running_count);
        try std.testing.expectEqual(BadgeKind.running, snapshot.badge_kind);
        try std.testing.expectEqual(OverlayKind.none, snapshot.overlay_kind);
    }

    _ = try store.recordReplyCompletion(.{
        .workspace_id = "tab-a",
        .tab_id = "tab-a",
        .surface_id = "surface-a",
        .session_id = "session-a",
        .agent_type = .codex,
        .agent_label = "Codex",
        .phase = .waiting_user,
        .severity = .info,
        .reply_attention = .unseen,
        .draft_started = false,
        .turn_id = "turn-a",
        .summary = "turn complete",
    }, .{
        .workspace_id = "tab-a",
        .session_id = "session-a",
        .kind = .turn_complete,
        .severity = .info,
        .title = "Codex",
        .body = "turn complete",
        .ack_required = true,
        .logical_key = "session-a:turn-a",
    });

    {
        const snapshot = store.snapshotWorkspace("tab-a").?;
        try std.testing.expectEqual(@as(u32, 0), snapshot.running_count);
        try std.testing.expectEqual(@as(u32, 1), snapshot.unread_count);
        try std.testing.expectEqual(@as(u32, 1), snapshot.unseen_count);
        try std.testing.expectEqual(BadgeKind.unseen, snapshot.badge_kind);
        try std.testing.expectEqual(OverlayKind.none, snapshot.overlay_kind);
    }

    try std.testing.expect(store.markSessionViewed("tab-a", "session-a", null));
    {
        const snapshot = store.snapshotWorkspace("tab-a").?;
        try std.testing.expectEqual(@as(u32, 0), snapshot.unseen_count);
        try std.testing.expectEqual(@as(u32, 1), snapshot.seen_count);
        try std.testing.expectEqual(BadgeKind.seen, snapshot.badge_kind);
    }

    try std.testing.expect(store.markReplyDraftStarted("tab-a", "session-a", null));
    try std.testing.expect(store.submitReply("tab-a", "session-a", "surface-a"));
    {
        const snapshot = store.snapshotWorkspace("tab-a").?;
        try std.testing.expectEqual(@as(u32, 1), snapshot.running_count);
        try std.testing.expectEqual(@as(u32, 0), snapshot.unread_count);
        try std.testing.expectEqual(BadgeKind.running, snapshot.badge_kind);
    }
}

test "explicit session start adopts active legacy session on same surface" {
    var store = Store.init(std.testing.allocator);
    defer store.deinit();

    try store.updateSession(.{
        .workspace_id = "tab-a",
        .tab_id = "tab-a",
        .surface_id = "surface-a",
        .session_id = "legacy:surface-a",
        .agent_type = .codex,
        .agent_label = "Codex",
        .phase = .running,
        .severity = .none,
    });

    try store.updateSession(.{
        .workspace_id = "tab-a",
        .tab_id = "tab-a",
        .surface_id = "surface-a",
        .session_id = "session-a",
        .agent_type = .codex,
        .agent_label = "Codex",
        .phase = .running,
        .severity = .none,
    });

    try std.testing.expectEqual(@as(usize, 1), store.sessions().len);
    try std.testing.expectEqualStrings("session-a", store.sessions()[0].session_id);
}

test "clear status with session id ignores mismatched surface id" {
    var store = Store.init(std.testing.allocator);
    defer store.deinit();

    try store.updateSession(.{
        .workspace_id = "tab-a",
        .tab_id = "tab-a",
        .surface_id = "surface-a",
        .session_id = "session-a",
        .agent_type = .codex,
        .agent_label = "Codex",
        .phase = .running,
        .severity = .none,
    });

    store.clearStatus("tab-a", "session-a", "surface-other");
    try std.testing.expectEqual(@as(usize, 0), store.sessions().len);
}

test "completed codex sessions do not keep a visible workspace badge" {
    var store = Store.init(std.testing.allocator);
    defer store.deinit();

    try store.updateSession(.{
        .workspace_id = "tab-a",
        .tab_id = "tab-a",
        .surface_id = "surface-a",
        .session_id = "session-a",
        .agent_type = .codex,
        .agent_label = "Codex",
        .phase = .completed,
        .severity = .info,
        .status_text = "info",
        .summary = "turn complete",
    });

    try std.testing.expectEqual(@as(?WorkspaceSnapshot, null), store.snapshotWorkspace("tab-a"));
}

test "partial session updates preserve existing surface binding" {
    var store = Store.init(std.testing.allocator);
    defer store.deinit();

    try store.updateSession(.{
        .workspace_id = "tab-a",
        .tab_id = "tab-a",
        .surface_id = "surface-a",
        .session_id = "session-a",
        .agent_type = .codex,
        .agent_label = "Codex",
        .phase = .running,
        .severity = .none,
        .summary = "session running",
    });

    try store.updateSession(.{
        .workspace_id = "tab-a",
        .tab_id = "tab-a",
        .surface_id = null,
        .session_id = "session-a",
        .agent_type = .codex,
        .agent_label = "Codex",
        .phase = .running,
        .severity = .none,
        .summary = "still running",
    });

    try std.testing.expectEqualStrings("surface-a", store.sessions()[0].surface_id.?);
}

test "failed codex replies remain visible through seen state" {
    var store = Store.init(std.testing.allocator);
    defer store.deinit();

    try store.updateSession(.{
        .workspace_id = "tab-a",
        .tab_id = "tab-a",
        .surface_id = "surface-a",
        .session_id = "session-a",
        .agent_type = .codex,
        .agent_label = "Codex",
        .phase = .running,
        .severity = .none,
    });

    _ = try store.recordReplyCompletion(.{
        .workspace_id = "tab-a",
        .tab_id = "tab-a",
        .surface_id = "surface-a",
        .session_id = "session-a",
        .agent_type = .codex,
        .agent_label = "Codex",
        .phase = .failed,
        .severity = .@"error",
        .reply_attention = .unseen,
        .draft_started = false,
        .summary = "request failed",
    }, .{
        .workspace_id = "tab-a",
        .session_id = "session-a",
        .kind = .session_failed,
        .severity = .@"error",
        .title = "Codex",
        .body = "request failed",
        .ack_required = true,
        .logical_key = "session-a",
    });

    {
        const snapshot = store.snapshotWorkspace("tab-a").?;
        try std.testing.expectEqual(BadgeKind.unseen, snapshot.badge_kind);
        try std.testing.expectEqual(@as(u32, 1), snapshot.unseen_count);
    }

    try std.testing.expect(store.markSessionViewed("tab-a", null, "surface-a"));
    {
        const snapshot = store.snapshotWorkspace("tab-a").?;
        try std.testing.expectEqual(BadgeKind.seen, snapshot.badge_kind);
        try std.testing.expectEqual(@as(u32, 1), snapshot.seen_count);
    }
}

test "logical reply refresh updates one attention item per session and turn" {
    var store = Store.init(std.testing.allocator);
    defer store.deinit();

    try store.updateSession(.{
        .workspace_id = "tab-a",
        .tab_id = "tab-a",
        .surface_id = "surface-a",
        .session_id = "session-a",
        .agent_type = .codex,
        .agent_label = "Codex",
        .phase = .running,
        .severity = .none,
    });

    const first_attention_id = try store.recordReplyCompletion(.{
        .workspace_id = "tab-a",
        .tab_id = "tab-a",
        .surface_id = "surface-a",
        .session_id = "session-a",
        .agent_type = .codex,
        .agent_label = "Codex",
        .phase = .waiting_user,
        .severity = .info,
        .reply_attention = .unseen,
        .draft_started = false,
        .turn_id = "turn-a",
        .summary = "first body",
    }, .{
        .workspace_id = "tab-a",
        .session_id = "session-a",
        .kind = .turn_complete,
        .severity = .info,
        .title = "Codex",
        .body = "first body",
        .ack_required = true,
        .logical_key = "session-a:turn-a",
    });

    const second_attention_id = try store.recordReplyCompletion(.{
        .workspace_id = "tab-a",
        .tab_id = "tab-a",
        .surface_id = "surface-a",
        .session_id = "session-a",
        .agent_type = .codex,
        .agent_label = "Codex",
        .phase = .waiting_user,
        .severity = .info,
        .reply_attention = .unseen,
        .draft_started = false,
        .turn_id = "turn-a",
        .summary = "refreshed body",
    }, .{
        .workspace_id = "tab-a",
        .session_id = "session-a",
        .kind = .turn_complete,
        .severity = .info,
        .title = "Codex",
        .body = "refreshed body",
        .ack_required = true,
        .logical_key = "session-a:turn-a",
    });

    try std.testing.expectEqual(@as(usize, 1), store.attentions().len);
    try std.testing.expectEqualStrings(first_attention_id, second_attention_id);
    try std.testing.expectEqualStrings("refreshed body", store.attentions()[0].body.?);
}
