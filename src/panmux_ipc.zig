const std = @import("std");

pub const Params = struct {
    title: ?[]const u8 = null,
    body: ?[]const u8 = null,
    state: ?[]const u8 = null,
    tab_index: ?u32 = null,
    tab_id: ?[]const u8 = null,
    surface_id: ?[]const u8 = null,
};

pub const Request = struct {
    method: []const u8,
    params: Params = .{},
};

pub const Response = struct {
    ok: bool,
    @"error": ?[]const u8 = null,
};

pub const json_opts: std.json.Stringify.Options = .{
    .whitespace = .minified,
};

pub const OwnedParams = struct {
    title: ?[:0]u8 = null,
    body: ?[:0]u8 = null,
    state: ?[:0]u8 = null,
    tab_index: ?u32 = null,
    tab_id: ?[:0]u8 = null,
    surface_id: ?[:0]u8 = null,

    pub fn clone(alloc: std.mem.Allocator, params: Params) !OwnedParams {
        var result: OwnedParams = .{
            .tab_index = params.tab_index,
        };
        errdefer result.deinit(alloc);

        if (params.title) |v| result.title = try alloc.dupeZ(u8, v);
        if (params.body) |v| result.body = try alloc.dupeZ(u8, v);
        if (params.state) |v| result.state = try alloc.dupeZ(u8, v);
        if (params.tab_id) |v| result.tab_id = try alloc.dupeZ(u8, v);
        if (params.surface_id) |v| result.surface_id = try alloc.dupeZ(u8, v);

        return result;
    }

    pub fn deinit(self: *OwnedParams, alloc: std.mem.Allocator) void {
        if (self.title) |v| alloc.free(v);
        if (self.body) |v| alloc.free(v);
        if (self.state) |v| alloc.free(v);
        if (self.tab_id) |v| alloc.free(v);
        if (self.surface_id) |v| alloc.free(v);
        self.* = undefined;
    }

    pub fn borrowed(self: *const OwnedParams) Params {
        return .{
            .title = if (self.title) |v| v else null,
            .body = if (self.body) |v| v else null,
            .state = if (self.state) |v| v else null,
            .tab_index = self.tab_index,
            .tab_id = if (self.tab_id) |v| v else null,
            .surface_id = if (self.surface_id) |v| v else null,
        };
    }
};

pub const OwnedRequest = struct {
    method: [:0]u8,
    params: OwnedParams,

    pub fn clone(alloc: std.mem.Allocator, request: Request) !OwnedRequest {
        return .{
            .method = try alloc.dupeZ(u8, request.method),
            .params = try OwnedParams.clone(alloc, request.params),
        };
    }

    pub fn deinit(self: *OwnedRequest, alloc: std.mem.Allocator) void {
        alloc.free(self.method);
        self.params.deinit(alloc);
        self.* = undefined;
    }

    pub fn borrowed(self: *const OwnedRequest) Request {
        return .{
            .method = self.method,
            .params = self.params.borrowed(),
        };
    }
};

pub fn hasExplicitTarget(params: Params) bool {
    return params.tab_index != null or params.tab_id != null or params.surface_id != null;
}

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
