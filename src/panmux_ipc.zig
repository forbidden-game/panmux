const std = @import("std");

pub const NotifyParams = struct {
    title: ?[]const u8 = null,
    body: ?[]const u8 = null,
    state: ?[]const u8 = null,
    tab_index: ?u32 = null,
};

pub const Request = struct {
    method: []const u8,
    params: NotifyParams = .{},
};

pub const Response = struct {
    ok: bool,
    @"error": ?[]const u8 = null,
};

pub const json_opts: std.json.Stringify.Options = .{
    .whitespace = .minified,
};

pub const OwnedNotify = struct {
    title: ?[:0]u8 = null,
    body: ?[:0]u8 = null,
    state: ?[:0]u8 = null,
    tab_index: ?u32 = null,

    pub fn clone(alloc: std.mem.Allocator, params: NotifyParams) !OwnedNotify {
        var result: OwnedNotify = .{
            .tab_index = params.tab_index,
        };
        errdefer result.deinit(alloc);

        if (params.title) |v| result.title = try alloc.dupeZ(u8, v);
        if (params.body) |v| result.body = try alloc.dupeZ(u8, v);
        if (params.state) |v| result.state = try alloc.dupeZ(u8, v);

        return result;
    }

    pub fn deinit(self: *OwnedNotify, alloc: std.mem.Allocator) void {
        if (self.title) |v| alloc.free(v);
        if (self.body) |v| alloc.free(v);
        if (self.state) |v| alloc.free(v);
        self.* = undefined;
    }

    pub fn borrowed(self: *const OwnedNotify) NotifyParams {
        return .{
            .title = if (self.title) |v| v else null,
            .body = if (self.body) |v| v else null,
            .state = if (self.state) |v| v else null,
            .tab_index = self.tab_index,
        };
    }
};

pub fn parseRequestLeaky(alloc: std.mem.Allocator, line: []const u8) !Request {
    return try std.json.parseFromSliceLeaky(
        Request,
        alloc,
        line,
        .{ .allocate = .alloc_if_needed, .ignore_unknown_fields = true },
    );
}

pub fn writeRequest(writer: *std.Io.Writer, request: Request) !void {
    try writer.print("{f}\n", .{std.json.fmt(request, json_opts)});
}

pub fn writeResponse(writer: *std.Io.Writer, response: Response) !void {
    try writer.print("{f}\n", .{std.json.fmt(response, json_opts)});
}
