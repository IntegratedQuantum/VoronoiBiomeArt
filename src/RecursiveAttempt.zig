const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const random = main.random;
const vec = main.vec;
const Vec2f = vec.Vec2f;

const FakeBiome = struct {
	color: main.graphics.Color,
	area: i32 = 0,
	radius: f32,
	typ: Type,
	const Type = packed struct(u6) {
		// pairs of opposite properties. In-between values are allowed.
		hot: bool = false,
		cold: bool = false,

		// TODO: In-between values are forbidden!
		land: bool = true,
		ocean: bool = false,

		wet: bool = false,
		dry: bool = false,
		
		fn diff(self: Type, other: Type) f32 {
			const selfInt = @bitCast(u6, self);
			var otherInt = @bitCast(u6, other);
			// Abusing the fact the the pairs are next to each other in the bit field. This allows comparing all pairs at once by flipping the fields in one number.
			const maskUpper: u6 = @truncate(u6, 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa);
			const maskLower: u6 = maskUpper >> 1;
			otherInt = (otherInt & maskUpper)>>1 | (otherInt & maskLower)<<1;
			const count = @popCount(selfInt & otherInt);
			return @intToFloat(f32, count);
		}

		fn color(self: Type) main.graphics.Color {
			var _color = main.graphics.Color {.r = 0, .g = 0, .b = 0, .a = 255};
			if(self.hot) {
				_color.r = 255;
			} else if(self.cold) {
				_color.r = 0;
			} else {
				_color.r = 127;
			}
			if(self.land) {
				_color.g = 255;
			} else if(self.ocean) {
				_color.g = 0;
			} else {
				_color.g = 127;
			}
			if(self.wet) {
				_color.b = 255;
			} else if(self.dry) {
				_color.b = 0;
			} else {
				_color.b = 127;
			}
			return _color;
		}
	};
};

const BiomePoint = struct {
	biome: *const FakeBiome,
	pos: Vec2f = .{0, 0},
	deltaPos: Vec2f = .{0, 0},
	weight: f32 = 1,
	area: i32 = 0,

	fn voronoiDistanceFunction(self: @This(), pos: Vec2f) f32 {
		return vec.lengthSquare(self.pos - pos)*self.weight;
	}

	fn xCoordinateLessThan(_: void, lhs: @This(), rhs: @This()) bool {
		return lhs.x < rhs.x;
	}
};

const size = 1024;
const maxBiomeRadius = 1024/32;
const maxBiomeDiameter = 2*maxBiomeRadius;
const border = maxBiomeDiameter;
const area = size*size;

const GenerationStructure = struct {
	const chunkSize = maxBiomeRadius;
	const numberOfChunksPerDimension = size/chunkSize;
	selectedBiomes: []BiomePoint,

	chunks: [numberOfChunksPerDimension][numberOfChunksPerDimension][]BiomePoint = undefined, // Implemented as slices into the original array!
	
	pub fn init(allocator: Allocator, biomeList: []const FakeBiome, seed: *u64) !GenerationStructure {
		// Select biomes that fill the entire area:
		var selectedBiomes: std.ArrayList(BiomePoint) = std.ArrayList(BiomePoint).init(allocator);
		defer selectedBiomes.deinit();
		var remainingArea: i32 = area;
		while(remainingArea > 0) {
			const drawnBiome = &biomeList[random.nextIntBounded(u32, seed, @intCast(u32, biomeList.len))];
			try selectedBiomes.append(.{.biome = drawnBiome});
			remainingArea -= drawnBiome.area;
		}

		var self = GenerationStructure {
			.selectedBiomes = try selectedBiomes.toOwnedSlice(),
		};

		{ // Give each of the points a unique position, starting with a simple grid distribution, to avoid clumping and empty areas.
			const pointsPerAxis = std.math.sqrt(self.selectedBiomes.len);
			var i: usize = 0;
			for(0..pointsPerAxis) |x| {
				for(0..pointsPerAxis) |z| {
					self.selectedBiomes[i].pos = Vec2f{
						@intToFloat(f32, x),
						@intToFloat(f32, z)
					}*@splat(2, size/@intToFloat(f32, pointsPerAxis));
				}
			}
			// All the others shall have a random position:
			while(i < self.selectedBiomes.len) : (i += 1) {
				self.selectedBiomes[i].pos = .{
					random.nextFloat(seed)*size,
					random.nextFloat(seed)*size
				};
			}
			for(self.selectedBiomes) |*biomePoint| {
				biomePoint.weight = 1.0/@intToFloat(f32, biomePoint.biome.area);
			}
		}
		self.updateChunks();
		return self;
	}

	pub fn deinit(self: *GenerationStructure, allocator: Allocator) void {
		allocator.free(self.selectedBiomes);
	}

	fn updateChunks(self: *GenerationStructure) void {
		const t1 = std.time.nanoTimestamp();
		// Reset all slices:
		for(&self.chunks) |*row| {
			for(&row.*) |*slice| {
				slice.len = 0;
			}
		}
		// Count the number of entries in each thing:
		for(self.selectedBiomes) |biome| {
			const pos = vec.floatToInt(u32, biome.pos/@splat(2, @as(f32, chunkSize)));
			(&(&self.chunks)[pos[0]])[pos[1]].len += 1;
		}
		// Init the slices:
		var offset: usize = 0;
		for(&self.chunks) |*row| {
			for(&row.*) |*slice| {
				const len = slice.len;
				slice.* = self.selectedBiomes[offset..][0..len];
				offset += len;
			}
		}
		// Sort the biomes into the slices:
		var filledAmount: [numberOfChunksPerDimension][numberOfChunksPerDimension]u32 = [_][numberOfChunksPerDimension]u32{[_]u32{0} ** numberOfChunksPerDimension} ** numberOfChunksPerDimension;
		var i: usize = 0;
		var count: usize = 0;
		while(i < self.selectedBiomes.len) {
			count += 1;
			const oldSpot = &self.selectedBiomes[i];
			const pos = vec.floatToInt(u32, oldSpot.pos/@splat(2, @as(f32, chunkSize)));
			const newSpot = &(&(&self.chunks)[pos[0]])[pos[1]][filledAmount[pos[0]][pos[1]]];
			if(@ptrToInt(oldSpot) < @ptrToInt(newSpot)) {
				i += 1;
				continue;
			}
			filledAmount[pos[0]][pos[1]] += 1;
			if(oldSpot == newSpot) {
				i += 1;
				continue;
			} else {
				const swap = newSpot.*;
				newSpot.* = oldSpot.*;
				oldSpot.* = swap;
			}
		}
		const t2 = std.time.nanoTimestamp();
		std.log.info("Sort {}", .{t2 - t1});
	}

	fn findClosestBiomeTo(self: *GenerationStructure, x: usize, z: usize) *const FakeBiome {
		const xf = @intToFloat(f32, x);
		const zf = @intToFloat(f32, z);
		var closestDist = std.math.floatMax(f32);
		var closestBiome: *const FakeBiome = undefined;
		const cellX: i32 = @intCast(i32, x/chunkSize);
		const cellZ: i32 = @intCast(i32, z/chunkSize);
		// Note that at a small loss of details we can assume that all BiomePoints are withing ±2 chunks of the current one.
		const offset = 2;
		var dx: i32 = -offset;
		while(dx <= offset) : (dx += 1) {
			const totalX = cellX + dx;
			if(totalX < 0 or totalX >= numberOfChunksPerDimension) continue;
			var dz: i32 = -offset;
			while(dz <= offset) : (dz += 1) {
				const totalZ = cellZ + dz;
				if(totalZ < 0 or totalZ >= numberOfChunksPerDimension) continue;
				const list = (&(&self.chunks)[@intCast(usize, totalX)])[@intCast(usize, totalZ)];
				for(list) |biomePoint| {
					const dist = biomePoint.voronoiDistanceFunction(.{xf, zf});
					if(dist < closestDist) {
						closestDist = dist;
						closestBiome = biomePoint.biome;
					}
				}
			}
		}
		return closestBiome;
	}

	pub fn toImage(self: *GenerationStructure, allocator: Allocator) !main.graphics.Image {
		const t1 = std.time.nanoTimestamp();
		const image = try main.graphics.Image.init(allocator, size, size);
		for(0.. size) |x| {
			for(0..size) |z| {
				var closestBiome: *const FakeBiome = self.findClosestBiomeTo(x, z);
				image.setRGB(x, z, closestBiome.typ.color());//.{.r = closestBiome.color.r, .g = closestBiome.color.r, .b = closestBiome.color.r, .a = closestBiome.color.a});
			}
		}
		for(0.. size - 2*border) |i| {
			image.setRGB(i + border, border, .{.r = 255, .g = 0, .b = 0, .a = 0});
			image.setRGB(i + border, size - border, .{.r = 255, .g = 0, .b = 0, .a = 0});
			image.setRGB(border, i + border, .{.r = 255, .g = 0, .b = 0, .a = 0});
			image.setRGB(size - border, i + border, .{.r = 255, .g = 0, .b = 0, .a = 0});
		}
		const t2 = std.time.nanoTimestamp();
		std.log.info("Img: {}", .{t2 - t1});
		return image;
	}
	pub fn physicsIteration1(self: *GenerationStructure) void {
		const offset = border/chunkSize;
		for(self.chunks[offset..numberOfChunksPerDimension-offset], offset..numberOfChunksPerDimension-offset) |*row, x| {
			for(row.*[offset..numberOfChunksPerDimension-offset], offset..numberOfChunksPerDimension-offset) |*chunk, z| {
				for(chunk.*) |*bp1| {
					var dx: i32 = -2*offset;
					while(dx <= 2*offset) : (dx += 1) {
						const totalX = @intCast(i32, x) + dx;
						if(totalX < 0 or totalX >= numberOfChunksPerDimension) continue;
						var dz: i32 = -2*offset;
						while(dz <= 2*offset) : (dz += 1) {
							const totalZ = @intCast(i32, z) + dz;
							if(totalZ < 0 or totalZ >= numberOfChunksPerDimension) continue;
							const list = (&(&self.chunks)[@intCast(usize, totalX)])[@intCast(usize, totalZ)];
							for(list) |*bp2| {
								if(bp1 == bp2) continue;
								const distanceSqr = vec.lengthSquare(bp1.pos - bp2.pos);
								{ // The distance between two biomes should be at least equal to the sum of their radii:
									const minimalDistance = bp1.biome.radius + bp2.biome.radius;
									if(distanceSqr < minimalDistance*minimalDistance) {
										const distance = @sqrt(distanceSqr);
										const totalFactor = 0.5*(minimalDistance - distance)/distance;
										bp1.deltaPos += @splat(2, totalFactor)*(bp1.pos - bp2.pos);
									}
								}
							}
						}
					}
				}
			}
		}
		// Finally update the positions:
		for(self.selectedBiomes) |*bp1| {
			const dist = vec.length(bp1.deltaPos);
			if(dist > bp1.biome.radius) {
				bp1.deltaPos *= @splat(2, bp1.biome.radius/dist);
			}
			bp1.pos += bp1.deltaPos;
			bp1.deltaPos = .{0, 0};
		}
		self.updateChunks();
	}
	pub fn physicsIteration2(self: *GenerationStructure) void {
		const offset = border/chunkSize;
		for(self.chunks[offset..numberOfChunksPerDimension-offset], offset..numberOfChunksPerDimension-offset) |*row, x| {
			for(row.*[offset..numberOfChunksPerDimension-offset], offset..numberOfChunksPerDimension-offset) |*chunk, z| {
				for(chunk.*) |*bp1| {
					var dx: i32 = -2*offset;
					while(dx <= 2*offset) : (dx += 1) {
						const totalX = @intCast(i32, x) + dx;
						if(totalX < 0 or totalX >= numberOfChunksPerDimension) continue;
						var dz: i32 = -2*offset;
						while(dz <= 2*offset) : (dz += 1) {
							const totalZ = @intCast(i32, z) + dz;
							if(totalZ < 0 or totalZ >= numberOfChunksPerDimension) continue;
							const list = (&(&self.chunks)[@intCast(usize, totalX)])[@intCast(usize, totalZ)];
							for(list) |*bp2| {
								if(bp1 == bp2) continue;
								const distanceSqr = vec.lengthSquare(bp1.pos - bp2.pos);
								{ // biomes of opposing type should be far away from each other:
									const minimalDistance = 2*(bp1.biome.radius + bp2.biome.radius);
									if(distanceSqr < minimalDistance*minimalDistance) {
										const t1 = bp1.biome.typ;
										const t2 = bp2.biome.typ;
										var diff = t1.diff(t2);
										const totalFactor = 0.05*bp1.biome.radius*diff*minimalDistance/distanceSqr;
										bp1.deltaPos += @splat(2, totalFactor)*(bp1.pos - bp2.pos);
									}
								}
							}
						}
					}
				}
			}
		}
		// Finally update the positions:
		for(self.selectedBiomes) |*bp1| {
			const dist = vec.length(bp1.deltaPos);
			if(dist > bp1.biome.radius) {
				bp1.deltaPos *= @splat(2, bp1.biome.radius/dist);
			}
			bp1.pos += bp1.deltaPos;
			bp1.deltaPos = .{0, 0};
		}
		self.updateChunks();
	}

	pub fn physicsIteration(self: *GenerationStructure) void {
		const ti1 = std.time.nanoTimestamp();
		self.physicsIteration1();
		self.physicsIteration2();
		const t2 = std.time.nanoTimestamp();
		std.log.info("It: {}", .{t2 - ti1});
	}
};

pub fn generateMap(allocator: Allocator) !main.graphics.Image {
	var seed: u64 = 5842948;
	var biomeList: [128]FakeBiome = undefined;
	for(&biomeList) |*biome| {
		biome.* = FakeBiome{
			.color = .{
				.r = random.nextInt(u8, &seed),
				.g = random.nextInt(u8, &seed),
				.b = random.nextInt(u8, &seed),
				.a = 255,
			},
			.radius = random.nextFloat(&seed)*16,
			.typ = .{},
		};
		const temp = random.nextIntBounded(u2, &seed, 3);
		if(temp == 0) {
			biome.typ.cold = true;
		} else if(temp == 2) {
			biome.typ.hot = true;
		}
		//const humid = random.nextIntBounded(u2, &seed, 3);
		//if(humid == 0) {
		//	biome.typ.dry = true;
		//} else if(humid == 2) {
		//	biome.typ.wet = true;
		//}
		if(random.nextInt(u1, &seed) != 0) {
			biome.typ.ocean = true;
			biome.typ.land = false;
		} else {
			biome.typ.land = true;
		}
		if(biome.color.r < 255/3) biome.color.r = 0
		else if(biome.color.r < 2*255/3) biome.color.r = 255/2
		else biome.color.r = 255;
		biome.area = @floatToInt(i32, std.math.pi*biome.radius*biome.radius);
	}

	var generator = try GenerationStructure.init(main.threadAllocator, &biomeList, &seed);
	defer generator.deinit(main.threadAllocator);

	{ // Output an image before doing any changes:
		const image = try generator.toImage(main.threadAllocator);
		defer image.deinit(main.threadAllocator);
		try image.exportToFile("testBefore.png");
	}

	for(0.. 2000) |_i| {
		generator.physicsIteration();
		const image = try generator.toImage(main.threadAllocator);
		defer image.deinit(main.threadAllocator);
		var buf: [128]u8 = undefined;
		const path = try std.fmt.bufPrint(&buf, "testBefore{}.png", .{_i});
		try image.exportToFile(path);
	}

	// Calculate the final image:
	return try generator.toImage(allocator);
}