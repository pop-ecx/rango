const std = @import("std");
const json = std.json;

const CommandExecutor = struct {
    allocator: std.mem.Allocator,
    io: std.Io,

    fn executeDeleteFile(self: *CommandExecutor, raw_json: []const u8) ![]const u8 {
        const DeleteFileParameters = struct { path: []const u8 };
        const parsed = try json.parseFromSlice(DeleteFileParameters, self.allocator, raw_json, .{});
        defer parsed.deinit();

        const path = parsed.value.path;
        if (path.len == 0) return try self.allocator.dupe(u8, "No path provided");

        _ = std.Io.Dir.cwd().statFile(self.io, path, .{}) catch |err| {
            return try std.fmt.allocPrint(self.allocator, "Error deleting file: {}", .{err});
        };

        std.Io.Dir.cwd().deleteTree(self.io, path) catch |err| {
            return try std.fmt.allocPrint(self.allocator, "Error deleting file: {s}",  .{@errorName(err)});
        };
        return try self.allocator.dupe(u8, "Success");

    }
};

test "Delete file success case" {
    var gpa = std.testing.allocator;
    var threaded = std.Io.Threaded.init(gpa, .{});
    defer threaded.deinit();
    const dir = std.Io.Dir.cwd();
    const io = threaded.io();

    var executor = CommandExecutor{ .allocator = gpa, .io = threaded.io() };

    var file = try std.Io.Dir.createFile(dir, io, "./testr", .{ .permissions = .default_file } );
    defer file.close(io);
    const case = "{\"path\": \"./testr\"}";
    const output = try executor.executeDeleteFile(case);
    defer gpa.free(output);
    try std.testing.expectEqualStrings("Success", output);
}

test "Delete file non-existent file failure" {
    var gpa = std.testing.allocator;
    var threaded = std.Io.Threaded.init(gpa, .{});
    defer threaded.deinit();

    var executor = CommandExecutor{ .allocator = gpa, .io = threaded.io() };

    const output = try executor.executeDeleteFile("{\"path\": \"non_existent_file\"}");
    defer gpa.free(output);
    try std.testing.expectEqualStrings("Error deleting file: error.FileNotFound", output);
}

test "Delete file empty path failure" {
    var gpa = std.testing.allocator;
    var threaded = std.Io.Threaded.init(gpa, .{});
    defer threaded.deinit();

    var executor = CommandExecutor{ .allocator = gpa, .io = threaded.io() };

    const output = try executor.executeDeleteFile("{\"path\": \"\"}");
    defer gpa.free(output);
    try std.testing.expectEqualStrings("No path provided", output);
}
