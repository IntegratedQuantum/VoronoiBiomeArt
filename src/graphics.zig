const std = @import("std");

const main = @import("main.zig");

const Allocator = std.mem.Allocator;

pub const stb_image = @cImport ({
	@cInclude("stb/stb_image.h");
	@cInclude("stb/stb_image_write.h");
});

pub const Color = extern struct {
	r: u8,
	g: u8,
	b: u8,
	a: u8,

	pub fn toARBG(self: Color) u32 {
		return @as(u32, self.a)<<24 | @as(u32, self.r)<<16 | @as(u32, self.g)<<8 | @as(u32, self.b);
	}
};

pub const Image = struct {
	var defaultImageData = [4]Color {
		Color{.r=0, .g=0, .b=0, .a=255},
		Color{.r=255, .g=0, .b=255, .a=255},
		Color{.r=255, .g=0, .b=255, .a=255},
		Color{.r=0, .g=0, .b=0, .a=255},
	};
	pub const defaultImage = Image {
		.width = 2,
		.height = 2,
		.imageData = &defaultImageData,
	};
	width: u31,
	height: u31,
	imageData: []Color,
	pub fn init(allocator: Allocator, width: u31, height: u31) !Image {
		return Image{
			.width = width,
			.height = height,
			.imageData = try allocator.alloc(Color, width*height),
		};
	}
	pub fn deinit(self: Image, allocator: Allocator) void {
		if(self.imageData.ptr == &defaultImageData) return;
		allocator.free(self.imageData);
	}
	pub fn readFromFile(allocator: Allocator, path: []const u8) !Image {
		var result: Image = undefined;
		var channel: c_int = undefined;
		const nullTerminatedPath = try std.fmt.allocPrintZ(main.threadAllocator, "{s}", .{path}); // TODO: Find a more zig-friendly image loading library.
		defer main.threadAllocator.free(nullTerminatedPath);
		stb_image.stbi_set_flip_vertically_on_load(1);
		const data = stb_image.stbi_load(nullTerminatedPath.ptr, @ptrCast([*c]c_int, &result.width), @ptrCast([*c]c_int, &result.height), &channel, 4) orelse {
			return error.FileNotFound;
		};
		result.imageData = try allocator.dupe(Color, @ptrCast([*]Color, data)[0..result.width*result.height]);
		stb_image.stbi_image_free(data);
		return result;
	}
	pub fn exportToFile(self: Image, path: []const u8) !void {
		const nullTerminated = try main.threadAllocator.dupeZ(u8, path);
		defer main.threadAllocator.free(nullTerminated);
		_ = stb_image.stbi_write_png(nullTerminated.ptr, self.width, self.height, 4, self.imageData.ptr, self.width*4);
	}
	pub fn getRGB(self: Image, x: usize, y: usize) Color {
		std.debug.assert(x < self.width);
		std.debug.assert(y < self.height);
		const index = x + y*self.width;
		return self.imageData[index];
	}
	pub fn setRGB(self: Image, x: usize, y: usize, rgb: Color) void {
		std.debug.assert(x < self.width);
		std.debug.assert(y < self.height);
		const index = x + y*self.width;
		self.imageData[index] = rgb;
	}
};
