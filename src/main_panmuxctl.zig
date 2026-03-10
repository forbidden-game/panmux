const std = @import("std");
const net = std.net;
const ipc = @import("panmux_ipc.zig");

const usage =
    "Usage:\n" ++
    "  panmuxctl notify [--socket PATH] [--title TEXT] [--body TEXT] [--state TEXT] [--session-id ID] [--agent-type TYPE] [--agent-label TEXT] [--turn-id ID] [--ack-required] [--tab N] [--tab-id ID] [--surface-id ID]\n" ++
    "  panmuxctl set-status [--socket PATH] --state TEXT [--title TEXT] [--body TEXT] [--session-id ID] [--agent-type TYPE] [--agent-label TEXT] [--turn-id ID] [--tab N] [--tab-id ID] [--surface-id ID]\n" ++
    "  panmuxctl clear-status [--socket PATH] [--session-id ID] [--tab N] [--tab-id ID] [--surface-id ID]\n" ++
    "  panmuxctl focus-tab [--socket PATH] [--tab N] [--tab-id ID] [--surface-id ID]\n" ++
    "  panmuxctl list-tabs [--socket PATH] [--tab N] [--tab-id ID] [--surface-id ID]\n" ++
    "  panmuxctl list-sessions [--socket PATH] [--tab N] [--tab-id ID] [--surface-id ID]\n" ++
    "  panmuxctl list-attention [--socket PATH] [--tab N] [--tab-id ID] [--surface-id ID]\n" ++
    "  panmuxctl ack-attention [--socket PATH] --attention-id ID [--tab N] [--tab-id ID] [--surface-id ID]\n" ++
    "\n" ++
    "Environment fallback:\n" ++
    "  PANMUX_SOCKET_PATH\n" ++
    "  PANMUX_TAB_ID\n" ++
    "  PANMUX_SURFACE_ID\n" ++
    "  PANMUX_SESSION_ID\n";

pub fn main() !void {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const alloc = gpa_state.allocator();

    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();

    _ = args.next();
    const cmd = args.next() orelse return printUsageAndExit(1);
    if (!isSupportedCommand(cmd)) return printUsageAndExit(1);

    var socket_path: ?[]const u8 = null;
    var params: ipc.Params = .{};

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--socket")) {
            socket_path = args.next() orelse return printUsageAndExit(1);
            continue;
        }
        if (std.mem.eql(u8, arg, "--title")) {
            params.title = args.next() orelse return printUsageAndExit(1);
            continue;
        }
        if (std.mem.eql(u8, arg, "--body")) {
            params.body = args.next() orelse return printUsageAndExit(1);
            continue;
        }
        if (std.mem.eql(u8, arg, "--state")) {
            params.state = args.next() orelse return printUsageAndExit(1);
            continue;
        }
        if (std.mem.eql(u8, arg, "--tab")) {
            const value = args.next() orelse return printUsageAndExit(1);
            params.tab_index = try std.fmt.parseUnsigned(u32, value, 10);
            continue;
        }
        if (std.mem.eql(u8, arg, "--tab-id")) {
            params.tab_id = args.next() orelse return printUsageAndExit(1);
            continue;
        }
        if (std.mem.eql(u8, arg, "--surface-id")) {
            params.surface_id = args.next() orelse return printUsageAndExit(1);
            continue;
        }
        if (std.mem.eql(u8, arg, "--session-id")) {
            params.session_id = args.next() orelse return printUsageAndExit(1);
            continue;
        }
        if (std.mem.eql(u8, arg, "--agent-type")) {
            params.agent_type = args.next() orelse return printUsageAndExit(1);
            continue;
        }
        if (std.mem.eql(u8, arg, "--agent-label")) {
            params.agent_label = args.next() orelse return printUsageAndExit(1);
            continue;
        }
        if (std.mem.eql(u8, arg, "--turn-id")) {
            params.turn_id = args.next() orelse return printUsageAndExit(1);
            continue;
        }
        if (std.mem.eql(u8, arg, "--attention-id")) {
            params.attention_id = args.next() orelse return printUsageAndExit(1);
            continue;
        }
        if (std.mem.eql(u8, arg, "--ack-required")) {
            params.ack_required = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            return printUsageAndExit(0);
        }

        std.log.err("unknown argument: {s}", .{arg});
        return printUsageAndExit(1);
    }

    if (std.mem.eql(u8, cmd, "set-status") and params.state == null) {
        std.log.err("set-status requires --state", .{});
        return printUsageAndExit(1);
    }
    if (std.mem.eql(u8, cmd, "ack-attention") and params.attention_id == null) {
        std.log.err("ack-attention requires --attention-id", .{});
        return printUsageAndExit(1);
    }

    var owned_tab_id: ?[]const u8 = null;
    if (params.tab_id == null) {
        owned_tab_id = std.process.getEnvVarOwned(alloc, "PANMUX_TAB_ID") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => null,
            else => return err,
        };
        params.tab_id = owned_tab_id;
    }
    defer if (owned_tab_id) |value| alloc.free(value);

    var owned_surface_id: ?[]const u8 = null;
    if (params.surface_id == null) {
        owned_surface_id = std.process.getEnvVarOwned(alloc, "PANMUX_SURFACE_ID") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => null,
            else => return err,
        };
        params.surface_id = owned_surface_id;
    }
    defer if (owned_surface_id) |value| alloc.free(value);

    var owned_session_id: ?[]const u8 = null;
    if (params.session_id == null) {
        owned_session_id = std.process.getEnvVarOwned(alloc, "PANMUX_SESSION_ID") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => null,
            else => return err,
        };
        params.session_id = owned_session_id;
    }
    defer if (owned_session_id) |value| alloc.free(value);

    const socket = socket_path orelse socket: {
        const value = std.process.getEnvVarOwned(alloc, "PANMUX_SOCKET_PATH") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => {
                std.log.err("missing --socket and PANMUX_SOCKET_PATH", .{});
                return printUsageAndExit(1);
            },
            else => return err,
        };
        break :socket value;
    };
    defer if (socket_path == null) alloc.free(socket);

    var stream = try net.connectUnixSocket(socket);
    defer stream.close();

    var writer_buf: [1024]u8 = undefined;
    var writer = stream.writer(&writer_buf);
    try ipc.writeRequest(&writer.interface, .{ .method = cmd, .params = params });
    try writer.interface.flush();

    var response_buf: [32 * 1024]u8 = undefined;
    const n = try stream.read(&response_buf);
    if (n == 0) return;

    const line = std.mem.trim(u8, response_buf[0..n], " \r\n\t");
    var parsed = try std.json.parseFromSlice(
        ipc.Response,
        alloc,
        line,
        .{ .allocate = .alloc_if_needed, .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    const response = parsed.value;

    if (!response.ok) {
        std.log.err("server error: {s}", .{response.@"error" orelse "unknown error"});
        std.process.exit(1);
    }

    if (std.mem.eql(u8, cmd, "list-tabs")) {
        const stdout = std.fs.File.stdout();
        var stdout_buf: [32 * 1024]u8 = undefined;
        var stdout_writer = stdout.writer(&stdout_buf);
        const tabs = response.tabs orelse &.{};
        try stdout_writer.interface.print("{f}\n", .{std.json.fmt(tabs, ipc.json_opts)});
        try stdout_writer.interface.flush();
        return;
    }

    if (std.mem.eql(u8, cmd, "list-sessions")) {
        const stdout = std.fs.File.stdout();
        var stdout_buf: [32 * 1024]u8 = undefined;
        var stdout_writer = stdout.writer(&stdout_buf);
        const sessions = response.sessions orelse &.{};
        try stdout_writer.interface.print("{f}\n", .{std.json.fmt(sessions, ipc.json_opts)});
        try stdout_writer.interface.flush();
        return;
    }

    if (std.mem.eql(u8, cmd, "list-attention")) {
        const stdout = std.fs.File.stdout();
        var stdout_buf: [32 * 1024]u8 = undefined;
        var stdout_writer = stdout.writer(&stdout_buf);
        const attentions = response.attentions orelse &.{};
        try stdout_writer.interface.print("{f}\n", .{std.json.fmt(attentions, ipc.json_opts)});
        try stdout_writer.interface.flush();
    }
}

fn isSupportedCommand(cmd: []const u8) bool {
    return std.mem.eql(u8, cmd, "notify") or
        std.mem.eql(u8, cmd, "set-status") or
        std.mem.eql(u8, cmd, "clear-status") or
        std.mem.eql(u8, cmd, "focus-tab") or
        std.mem.eql(u8, cmd, "list-tabs") or
        std.mem.eql(u8, cmd, "list-sessions") or
        std.mem.eql(u8, cmd, "list-attention") or
        std.mem.eql(u8, cmd, "ack-attention");
}

fn printUsageAndExit(code: u8) !void {
    var stdout_buf: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    try stdout_writer.interface.writeAll(usage);
    try stdout_writer.interface.flush();
    std.process.exit(code);
}
