const std = @import("std");

pub fn isCodexCommandText(text: []const u8) bool {
    var idx: usize = 0;
    var token_buf: [256]u8 = undefined;
    var allow_wrapper_options = false;

    while (nextCommandWord(text, &idx, &token_buf)) |word| {
        if (word.len == 0) continue;
        if (isShellEnvAssignment(word)) continue;

        if (std.mem.eql(u8, word, "command") or
            std.mem.eql(u8, word, "env") or
            std.mem.eql(u8, word, "exec"))
        {
            allow_wrapper_options = true;
            continue;
        }

        if (allow_wrapper_options and word[0] == '-') continue;

        const basename = std.fs.path.basename(word);
        return std.mem.eql(u8, basename, "codex");
    }

    return false;
}

fn nextCommandWord(
    text: []const u8,
    idx: *usize,
    buf: *[256]u8,
) ?[]const u8 {
    var i = idx.*;
    while (i < text.len and std.ascii.isWhitespace(text[i])) : (i += 1) {}
    if (i >= text.len) {
        idx.* = i;
        return null;
    }

    var out: usize = 0;
    var quote: ?u8 = null;
    while (i < text.len) : (i += 1) {
        const c = text[i];
        if (quote == null and std.ascii.isWhitespace(c)) break;

        if (quote) |q| {
            if (c == q) {
                quote = null;
                continue;
            }

            if (q == '"' and c == '\\' and i + 1 < text.len) {
                i += 1;
                if (out < buf.len) buf[out] = text[i];
                out += 1;
                continue;
            }
        } else switch (c) {
            '\'', '"' => {
                quote = c;
                continue;
            },
            '\\' => {
                if (i + 1 >= text.len) break;
                i += 1;
                if (out < buf.len) buf[out] = text[i];
                out += 1;
                continue;
            },
            else => {},
        }

        if (out < buf.len) buf[out] = c;
        out += 1;
    }

    idx.* = i;
    return buf[0..@min(out, buf.len)];
}

fn isShellEnvAssignment(word: []const u8) bool {
    const eq_idx = std.mem.indexOfScalar(u8, word, '=') orelse return false;
    if (eq_idx == 0) return false;

    const head = word[0..eq_idx];
    if (!(std.ascii.isAlphabetic(head[0]) or head[0] == '_')) return false;

    for (head[1..]) |c| {
        if (!(std.ascii.isAlphanumeric(c) or c == '_')) return false;
    }

    return true;
}

test "isCodexCommandText" {
    try std.testing.expect(isCodexCommandText("codex"));
    try std.testing.expect(isCodexCommandText("env FOO=1 codex --help"));
    try std.testing.expect(isCodexCommandText("command -- codex"));
    try std.testing.expect(isCodexCommandText("/usr/local/bin/codex chat"));
    try std.testing.expect(!isCodexCommandText("code"));
    try std.testing.expect(!isCodexCommandText("env FOO=1 /usr/bin/python"));
}
