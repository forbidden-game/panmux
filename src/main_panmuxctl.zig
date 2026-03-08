const std = @import("std");
const net = std.net;
const ipc = @import("panmux_ipc.zig");

const usage =
    "Usage:\n" ++
    "  panmuxctl notify [--socket PATH] [--title TEXT] [--body TEXT] [--state TEXT] [--tab N]\n" ++
    "\n" ++
    "Environment fallback:\n" ++
    "  PANMUX_SOCKET_PATH\n";

pub fn main() !void {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const alloc = gpa_state.allocator();

    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();

    _ = args.next();
    const cmd = args.next() orelse return printUsageAndExit(1);
    if (!std.mem.eql(u8, cmd, "notify")) return printUsageAndExit(1);

    var socket_path: ?[]const u8 = null;
    var title: ?[]const u8 = null;
    var body: ?[]const u8 = null;
    var state: ?[]const u8 = null;
    var tab_index: ?u32 = null;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--socket")) {
            socket_path = args.next() orelse return printUsageAndExit(1);
            continue;
        }
        if (std.mem.eql(u8, arg, "--title")) {
            title = args.next() orelse return printUsageAndExit(1);
            continue;
        }
        if (std.mem.eql(u8, arg, "--body")) {
            body = args.next() orelse return printUsageAndExit(1);
            continue;
        }
        if (std.mem.eql(u8, arg, "--state")) {
            state = args.next() orelse return printUsageAndExit(1);
            continue;
        }
        if (std.mem.eql(u8, arg, "--tab")) {
            const value = args.next() orelse return printUsageAndExit(1);
            tab_index = try std.fmt.parseUnsigned(u32, value, 10);
            continue;
        }
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            return printUsageAndExit(0);
        }
        std.log.err("unknown argument: {s}", .{arg});
        return printUsageAndExit(1);
    }

    const socket = socket_path orelse std.process.getEnvVarOwned(alloc, "PANMUX_SOCKET_PATH") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => {
            std.log.err("missing --socket and PANMUX_SOCKET_PATH", .{});
            return printUsageAndExit(1);
        },
        else => return err,
    };
    defer if (socket_path == null) alloc.free(socket);

    var stream = try net.connectUnixSocket(socket);
    defer stream.close();

    var writer_buf: [1024]u8 = undefined;
    var writer = stream.writer(&writer_buf);
    try ipc.writeRequest(&writer.interface, .{
        .method = "notify",
        .params = .{
            .title = title,
            .body = body,
            .state = state,
            .tab_index = tab_index,
        },
    });
    try writer.interface.flush();

    var response_buf: [1024]u8 = undefined;
    const n = try stream.read(&response_buf);
    if (n == 0) return;
    const line = std.mem.trim(u8, response_buf[0..n], " \r\n\t");
    const response = try std.json.parseFromSliceLeaky(ipc.Response, alloc, line, .{ .allocate = .alloc_if_needed, .ignore_unknown_fields = true });
    if (!response.ok) {
        std.log.err("server error: {s}", .{response.@"error" orelse "unknown error"});
        std.process.exit(1);
    }
}

fn printUsageAndExit(code: u8) !void {
    var stdout_buf: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    try stdout_writer.interface.writeAll(usage);
    try stdout_writer.interface.flush();
    std.process.exit(code);
}
