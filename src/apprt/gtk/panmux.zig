const std = @import("std");
const net = std.net;
const ipc = @import("../../panmux_ipc.zig");

pub const Server = struct {
    alloc: std.mem.Allocator,
    cookie: ?*anyopaque,
    request_fn: *const fn (?*anyopaque, ipc.OwnedRequest) ipc.OwnedResponse,
    socket_path: [:0]u8,
    instance_id: [:0]u8,
    running: std.atomic.Value(bool) = .init(false),
    listener: net.Server = undefined,
    thread: ?std.Thread = null,

    pub fn init(
        self: *Server,
        alloc: std.mem.Allocator,
        cookie: ?*anyopaque,
        request_fn: *const fn (?*anyopaque, ipc.OwnedRequest) ipc.OwnedResponse,
    ) !void {
        const runtime_dir = std.posix.getenv("XDG_RUNTIME_DIR") orelse return error.MissingXdgRuntimeDir;

        const socket_dir = try std.fmt.allocPrint(alloc, "{s}/panmux", .{runtime_dir});
        defer alloc.free(socket_dir);
        std.fs.makeDirAbsolute(socket_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        const instance_id_str = try std.fmt.allocPrint(alloc, "{d}-{d}", .{ std.c.getpid(), std.time.milliTimestamp() });
        defer alloc.free(instance_id_str);
        const instance_id = try alloc.dupeZ(u8, instance_id_str);
        errdefer alloc.free(instance_id);

        const socket_path_str = try std.fmt.allocPrint(alloc, "{s}/{s}.sock", .{ socket_dir, instance_id_str });
        defer alloc.free(socket_path_str);
        const socket_path = try alloc.dupeZ(u8, socket_path_str);
        errdefer alloc.free(socket_path);

        std.fs.deleteFileAbsolute(socket_path) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };

        const address = try net.Address.initUnix(socket_path);
        var listener = try address.listen(.{});
        errdefer listener.deinit();

        self.* = .{
            .alloc = alloc,
            .cookie = cookie,
            .request_fn = request_fn,
            .socket_path = socket_path,
            .instance_id = instance_id,
            .running = .init(true),
            .listener = listener,
            .thread = null,
        };

        self.thread = try std.Thread.spawn(.{}, threadMain, .{self});
    }

    pub fn deinit(self: *Server) void {
        self.running.store(false, .seq_cst);
        self.listener.deinit();
        if (self.thread) |thread| thread.join();
        std.fs.deleteFileAbsolute(self.socket_path) catch {};
        self.alloc.free(self.socket_path);
        self.alloc.free(self.instance_id);
        self.* = undefined;
    }

    fn threadMain(self: *Server) void {
        while (self.running.load(.seq_cst)) {
            const conn = self.listener.accept() catch |err| switch (err) {
                error.SocketNotListening,
                error.FileDescriptorNotASocket,
                => break,
                else => continue,
            };
            self.handleConnection(conn);
        }
    }

    fn handleConnection(self: *Server, conn: net.Server.Connection) void {
        defer conn.stream.close();

        const line = readLineAlloc(self.alloc, conn.stream, 8192) catch {
            writeOwnedResponse(conn.stream, ipc.OwnedResponse.failure(self.alloc, "read_failed") catch ipc.OwnedResponse{ .ok = false }) catch {};
            return;
        };
        defer self.alloc.free(line);

        const request = ipc.parseRequestLeaky(self.alloc, line) catch {
            writeOwnedResponse(conn.stream, ipc.OwnedResponse.failure(self.alloc, "invalid_json") catch ipc.OwnedResponse{ .ok = false }) catch {};
            return;
        };

        if (!isSupportedMethod(request.method)) {
            writeOwnedResponse(conn.stream, ipc.OwnedResponse.failure(self.alloc, "unsupported_method") catch ipc.OwnedResponse{ .ok = false }) catch {};
            return;
        }

        const owned = ipc.OwnedRequest.clone(self.alloc, request) catch {
            writeOwnedResponse(conn.stream, ipc.OwnedResponse.failure(self.alloc, "oom") catch ipc.OwnedResponse{ .ok = false }) catch {};
            return;
        };

        var response = self.request_fn(self.cookie, owned);
        defer response.deinit(self.alloc);
        writeOwnedResponse(conn.stream, response) catch {};
    }
};

fn isSupportedMethod(method: []const u8) bool {
    return std.mem.eql(u8, method, "notify") or
        std.mem.eql(u8, method, "set-status") or
        std.mem.eql(u8, method, "clear-status") or
        std.mem.eql(u8, method, "focus-tab") or
        std.mem.eql(u8, method, "list-tabs");
}

fn readLineAlloc(alloc: std.mem.Allocator, stream: net.Stream, limit: usize) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(alloc);

    var buf: [1024]u8 = undefined;
    while (list.items.len < limit) {
        const amt = try stream.read(&buf);
        if (amt == 0) break;

        if (std.mem.indexOfScalar(u8, buf[0..amt], '\n')) |idx| {
            try list.appendSlice(alloc, buf[0..idx]);
            return try list.toOwnedSlice(alloc);
        }

        try list.appendSlice(alloc, buf[0..amt]);
    }

    return try list.toOwnedSlice(alloc);
}

fn writeOwnedResponse(stream: net.Stream, response: ipc.OwnedResponse) !void {
    var writer_buf: [2048]u8 = undefined;
    var writer = stream.writer(&writer_buf);
    try ipc.writeOwnedResponse(&writer.interface, response);
    try writer.interface.flush();
}
