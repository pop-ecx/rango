const std = @import("std");
const Allocator = std.mem.Allocator;

pub const SystemInfo = struct {
    pub fn getCurrentUser(self: *const SystemInfo, allocator: Allocator) ![]const u8 {
        _ = self; // Explicitly mark self as unused to avoid warning
        return std.process.getEnvVarOwned(allocator, "USER") catch "unknown";
    }

    pub fn getHostname(self: *const SystemInfo) ![]const u8 {
        _ = self; // Explicitly mark self as unused
        var buf: [64]u8 = undefined;
        return std.posix.gethostname(&buf);
    }

    pub fn getPid(self: *const SystemInfo) !u32 {
        _ = self; // Explicitly mark self as unused
        return @intCast(std.os.linux.getpid());
    }

    pub fn getOS(self: *const SystemInfo) []const u8 {
        _ = self; // Explicitly mark self as unused
        return "Linux";
    }

    pub fn getArchitecture(self: *const SystemInfo) []const u8 {
        _ = self; // Explicitly mark self as unused
        return "x64";
    }
};
