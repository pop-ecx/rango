const std = @import("std");
const json = std.json;

const CommandExecutor = struct {
    allocator: std.mem.Allocator,

    fn executeShell(self: *CommandExecutor, raw_json: []const u8) ![]const u8 {
        const ShellParameters = struct { command: []const u8 };
        const parsed = try json.parseFromSlice(ShellParameters, self.allocator, raw_json, .{});
        defer parsed.deinit();

        const command = parsed.value.command;
        if (command.len == 0) return "No command provided";

        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "/bin/sh", "-c", command },
        });

        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        return if (result.stdout.len > 0)
            try self.allocator.dupe(u8, result.stdout)
        else
            try self.allocator.dupe(u8, result.stderr);
    }
};

test "shell command execution via JSON" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var executor = CommandExecutor{ .allocator = allocator };

    const cases = [_][]const u8{
        "{\"command\": \"ls\"}",
        "{\"command\": \"ls -a\"}",
        "{\"command\": \"whoami\"}",
        "{\"command\": \"pwd\"}",
        "{\"command\": \"ungabunga\"}",
    };

    inline for (cases) |raw_json| {
        const output = try executor.executeShell(raw_json);
        defer allocator.free(output);

        std.debug.print("JSON: {s}\nOutput:\n{s}\n---\n", .{ raw_json, output });

        try std.testing.expect(output.len > 0);
    }
}
