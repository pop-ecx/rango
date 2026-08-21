const std = @import("std");
const json = std.json;

const CommandExecutor = struct {
    allocator: std.mem.Allocator,
    io: std.Io,

    fn executeLs(self: *CommandExecutor, raw_json: []const u8) ![]const u8 {
       const ExecuteLsParameters =  struct { path: []const u8 };
        const parsed = try json.parseFromSlice(ExecuteLsParameters, self.allocator, raw_json, .{});
        defer parsed.deinit();

        const path = parsed.value.path;
        if (path.len == 0) return try self.allocator.dupe(u8, "No path provided");
        
        var dir = std.Io.Dir.cwd().openDir(self.io, path, .{ .iterate = true }) catch |err| {
            return try std.fmt.allocPrint(self.allocator, "Error listing files: {s} ", .{ @errorName(err) });
        };
        defer dir.close(self.io);
        var output = std.ArrayList(u8).empty;
        defer output.deinit(self.allocator);

        var iterator = dir.iterate();
        while (try iterator.next(self.io)) |entry| {
            try output.appendSlice(self.allocator, entry.name);
            try output.append(self.allocator, '\n');
        }
        return try output.toOwnedSlice(self.allocator);
    }
};

test "ls current directory success" {
    const gpa = std.testing.allocator;
    var threaded = std.Io.Threaded.init(gpa, .{}); 
    defer threaded.deinit();

    var executor = CommandExecutor{ .allocator = gpa, .io = threaded.io() };
    const case = "{\"path\": \".\"}";
    const output = try executor.executeLs(case);
    defer gpa.free(output);
    try std.testing.expect(output.len > 0);
}

test "Empty directory path test failure" {
    const gpa = std.testing.allocator;
    var threaded = std.Io.Threaded.init(gpa, .{}); 
    defer threaded.deinit();

    var executor = CommandExecutor{ .allocator = gpa, .io = threaded.io() };
    const case = "{\"path\": \"\"}";
    const output = try executor.executeLs(case);
    defer gpa.free(output);
    try std.testing.expectEqualStrings("No path provided", output);
}
