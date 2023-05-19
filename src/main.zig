const std = @import("std");

pub const graphics = @import("graphics.zig");
pub const random = @import("random.zig");
pub const vec = @import("vec.zig");

pub threadlocal var threadAllocator: std.mem.Allocator = undefined;
pub threadlocal var seed: u64 = undefined;
pub var globalAllocator: std.mem.Allocator = undefined;

var logFile: std.fs.File = undefined;
// overwrite the log function:
pub const std_options = struct {
	pub const log_level = .debug;
	pub fn logFn(
		comptime level: std.log.Level,
		comptime _: @Type(.EnumLiteral),
		comptime format: []const u8,
		args: anytype,
	) void {
		const color = comptime switch (level) {
			std.log.Level.err => "\x1b[31m",
			std.log.Level.info => "",
			std.log.Level.warn => "\x1b[33m",
			std.log.Level.debug => "\x1b[37;44m",
		};

		std.debug.getStderrMutex().lock();
		defer std.debug.getStderrMutex().unlock();

		logFile.writer().print("[" ++ level.asText() ++ "]" ++ ": " ++ format ++ "\n", args) catch {};

		nosuspend std.io.getStdErr().writer().print(color ++ format ++ "\x1b[0m\n", args) catch {};
	}
};

pub fn main() !void {
	seed = @bitCast(u64, std.time.milliTimestamp());
	var gpa = std.heap.GeneralPurposeAllocator(.{.thread_safe=false}){};
	threadAllocator = gpa.allocator();
	defer if(gpa.deinit() == .leak) {
		std.log.err("Memory leak", .{});
	};
	var global_gpa = std.heap.GeneralPurposeAllocator(.{.thread_safe=true}){};
	globalAllocator = global_gpa.allocator();
	defer if(global_gpa.deinit() == .leak) {
		std.log.err("Memory leak", .{});
	};

	// init logging.
	try std.fs.cwd().makePath("logs");
	logFile = std.fs.cwd().createFile("logs/latest.log", .{}) catch unreachable;
	defer logFile.close();
	
	const img = try @import("RecursiveAttempt.zig").generateMap(threadAllocator);
	defer img.deinit(threadAllocator);
	try img.exportToFile("test.png");
}