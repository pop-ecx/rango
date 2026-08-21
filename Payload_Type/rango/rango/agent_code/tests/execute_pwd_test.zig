const std = @import("std");
const json = std.json;

const CommandExecutor = struct {
    allocator: std.mem.Allocator,
    io: std.Io,

    fn executePwd(self: *CommandExecutor) ![]const u8 {
        const cwd_z = std.process.currentPathAlloc(self.io, self.allocator) catch |err| {
            return try std.fmt.allocPrint(self.allocator, "Error doing pwd: {}", .{err});
        };
        defer self.allocator.free(cwd_z);
        const cwd = try self.allocator.dupe(u8, cwd_z[0..cwd_z.len]);
        defer self.allocator.free(cwd);
        std.debug.print("pwd: {s}", .{cwd});
        return try self.allocator.dupe(u8, "success");
    }
};

//pwd is a bit restricted since it does not take params from the user
test "pwd success" {
    var gpa = std.testing.allocator;
    var threaded = std.Io.Threaded.init(gpa, .{});
    defer threaded.deinit();

    var executor = CommandExecutor{ .allocator = gpa, .io = threaded.io() };
    const output = try executor.executePwd();
    defer gpa.free(output);
    try std.testing.expectEqualStrings("success", output);
}

test "pwd out of memory" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();

    var failing_alloc = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var executor = CommandExecutor{ .allocator = failing_alloc.allocator(), .io = threaded.io() };

    try std.testing.expectError(error.OutOfMemory, executor.executePwd());
}
