const std = @import("std");
const json = std.json;

const CommandExecutor = struct {
    allocator: std.mem.Allocator,
    io: std.Io,

    fn executeCat(self: *CommandExecutor, raw_json: []const u8) ![]const u8 {
        const ExecuteCatParameters = struct { path: []const u8 };
        const parsed = try json.parseFromSlice(ExecuteCatParameters, self.allocator, raw_json, .{});
        defer parsed.deinit();

        const path = parsed.value.path;
        if (path.len == 0) return try self.allocator.dupe(u8, "No path provided");

        _ = std.Io.Dir.cwd().statFile(self.io, path, .{}) catch |err| {
            return try std.fmt.allocPrint(self.allocator, "Error reading file: {}", .{err});
        };

        const content = std.Io.Dir.cwd().readFileAlloc(self.io, path, self.allocator, .limited(1024 * 1024)) catch |err| {
            return try std.fmt.allocPrint(self.allocator, "Error reading file: {s}", .{@errorName(err)});
        };
        defer self.allocator.free(content);
        return try self.allocator.dupe(u8, "Success");
    }
};

test "Read existing file successfully" {
    var gpa = std.testing.allocator;
    var threaded = std.Io.Threaded.init(gpa, .{});
    defer threaded.deinit();
    const io = threaded.io();
    const dir = std.Io.Dir.cwd();

    var executor = CommandExecutor{ .allocator = gpa, .io = io };
    try std.Io.Dir.writeFile(dir, io, .{ .sub_path = "./tests/testr", .data = "AAAAAAAAAAAAAAA", .flags = .{ .permissions = .default_file } });
    const case = "{\"path\": \"./tests/testr\"}";
    const output = try executor.executeCat(case);
    defer gpa.free(output);
    try std.testing.expectEqualStrings("Success", output);
}

test "Reading non existing file failure" {
    var gpa = std.testing.allocator;
    var threaded = std.Io.Threaded.init(gpa, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var executor = CommandExecutor{ .allocator = gpa, .io = io };
    const case = "{\"path\": \"./non_existent_file\"}";
    const output = try executor.executeCat(case);
    defer gpa.free(output);
    try std.testing.expectEqualStrings("Error reading file: error.FileNotFound", output);
}

test "Reading a blank file path failure" {
    var gpa = std.testing.allocator;
    var threaded = std.Io.Threaded.init(gpa, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var executor = CommandExecutor{ .allocator = gpa, .io = io };
    const case = "{\"path\": \"\"}";
    const output = try executor.executeCat(case);
    defer gpa.free(output);
    try std.testing.expectEqualStrings("No path provided", output);
}
