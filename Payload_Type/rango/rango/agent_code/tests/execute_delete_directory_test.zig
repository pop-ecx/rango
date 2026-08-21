const std = @import("std");
const json = std.json;

const CommandExecutor = struct {
    allocator: std.mem.Allocator,
    io: std.Io,

    fn executeDeleteDirectory(self: *CommandExecutor, raw_json: []const u8) ![]const u8 {
        const DeleteDirectoryParameters = struct { path: []const u8 };
        const parsed = try json.parseFromSlice(DeleteDirectoryParameters, self.allocator, raw_json, .{});
        defer parsed.deinit();

        const path = parsed.value.path;
        if (path.len == 0) return try self.allocator.dupe(u8, "No path provided");

        _ = std.Io.Dir.cwd().statFile(self.io, path, .{}) catch |err| {
            return try std.fmt.allocPrint(self.allocator, "Error deleting directory: {}", .{err});
        };

        std.Io.Dir.cwd().deleteTree(self.io, path) catch |err| {
            return try std.fmt.allocPrint(self.allocator, "Error deleting directory: {s}", .{@errorName(err)});
        };
        return try self.allocator.dupe(u8, "Success");
    }
};

test "Delete directory success case" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const dir = std.Io.Dir.cwd();
    const io = threaded.io();

    var executor = CommandExecutor{ .allocator = allocator, .io = threaded.io() };

    try std.Io.Dir.createDir(dir, io, "test_dir", .default_dir);

    const case = "{\"path\": \"test_dir\"}";
    const output = try executor.executeDeleteDirectory(case);
    defer allocator.free(output);
    try std.testing.expectEqualStrings("Success", output);
}

test "Delete directory non-existent dir failure" {
    const gpa = std.testing.allocator;
    var threaded = std.Io.Threaded.init(gpa, .{});
    defer threaded.deinit();

    var executor = CommandExecutor{ .allocator = gpa, .io = threaded.io() };

    const output = try executor.executeDeleteDirectory("{\"path\": \"non_existent_dir\"}");
    defer gpa.free(output);
    try std.testing.expectEqualStrings("Error deleting directory: error.FileNotFound", output);
}

test "Delete directory empty path failure" {
    var gpa = std.testing.allocator;
    var threaded = std.Io.Threaded.init(gpa, .{});
    defer threaded.deinit();

    var executor = CommandExecutor{ .allocator = gpa, .io = threaded.io() };

    const output = try executor.executeDeleteDirectory("{\"path\": \"\"}");
    defer gpa.free(output);
    try std.testing.expectEqualStrings("No path provided", output);
}
