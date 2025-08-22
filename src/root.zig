pub const Mesh = @import("Mesh.zig");
pub const Face = @import("Face.zig");
pub const Color = @import("Color.zig");

const std = @import("std");

pub const F32x3 = @Vector(3, f32);
pub const F32x2 = @Vector(2, f32);

const ResultType = enum {
    vertex,
    color,
    normal,
    face,
    texture,
    object,
    group,
};

const LineParseResult = union(ResultType) {
    vertex: F32x3,
    color: Color,
    normal: F32x3,
    face: Face,
    texture: F32x2,
    object: []const u8,
    group: []const u8,
};

const VectorError = error{
    UnexpectedVectorPosition,
};

pub fn load(allocator: std.mem.Allocator, file_contents: []const u8) !Contents {
    return try Contents.init(allocator, file_contents);
}

const Contents = struct {
    allocator: std.mem.Allocator,
    meshes: std.ArrayList(Mesh),

    pub fn init(allocator: std.mem.Allocator, file_contents: []const u8) !Contents {
        var meshes = std.ArrayList(Mesh).empty;

        var mesh = try Mesh.init(allocator);

        var lines = fileIntoLines(file_contents);

        while (lines.next()) |line| {
            const result: LineParseResult = parseLine(line) catch continue;

            try switch (result) {
                ResultType.vertex => try mesh.positions.append(mesh.allocator, result.vertex),
                ResultType.color => try mesh.colors.append(mesh.allocator, result.color),
                ResultType.normal => try mesh.normals.append(mesh.allocator, result.normal),
                ResultType.face => try mesh.faces.append(mesh.allocator, result.face),
                ResultType.texture => try mesh.uvs.append(mesh.allocator, result.texture),
                else => error.ResultTypeNotSupported,
            };
        }
        try meshes.append(allocator, mesh);

        const self = Contents{
            .allocator = allocator,
            .meshes = meshes,
        };
        return self;
    }

    pub fn deinit(self: *Contents) void {
        for (self.meshes.items) |*mesh| {
            mesh.deinit();
        }
        self.meshes.deinit(self.allocator);
    }
};

fn parseLine(lineIn: []const u8) !LineParseResult {
    var line: []const u8 = lineIn;

    if (line.len <= 0)
        return error.LineLengthEqualToZero;
    while (line[0] == ' ') {
        line = line[1..line.len];
    }

    var token_iterator = std.mem.tokenizeAny(u8, line, " ");
    const first = token_iterator.next() orelse unreachable;

    if (line[0] == '#') {
        return error.LineLengthEqualToZero;
    }

    if (std.mem.eql(u8, "vt", first)) {
        return LineParseResult{ .texture = try iterateIntoF32x2(&token_iterator) };
    }

    if (std.mem.eql(u8, "vn", first)) {
        return LineParseResult{ .normal = try iterateIntoF32x3(&token_iterator) };
    }

    if (std.mem.eql(u8, "v", first)) {
        return LineParseResult{ .vertex = try iterateIntoF32x3(&token_iterator) };
    }
    if (std.mem.eql(u8, "f", first)) {
        return LineParseResult{ .face = try iterateIntoFace(&token_iterator) };
    }

    return error.NotImplemented;
}

pub fn fileIntoLines(file_contents: []const u8) std.mem.SplitIterator(u8, .any) {
    // find a \n and see if it has \r\n
    var index: u32 = 0;
    while (index < file_contents.len) : (index += 1) {
        if (file_contents[index] == '\n' and index > 0) {
            if (file_contents[index - 1] == '\r') {
                return std.mem.splitAny(u8, file_contents, "\r\n");
            } else {
                return std.mem.splitAny(u8, file_contents, "\n");
            }
        }
    }
    return std.mem.splitAny(u8, file_contents, "\n");
}

fn iterateIntoF32x2(iterator: *std.mem.TokenIterator(u8, .any)) !F32x2 {
    var vec: F32x2 = undefined;
    var next: u32 = 0;
    while (iterator.next()) |token| : (next += 1) {
        vec[next] = try std.fmt.parseFloat(f32, token);
    }

    return vec;
}

fn iterateIntoF32x3(iterator: *std.mem.TokenIterator(u8, .any)) !F32x3 {
    var vec: F32x3 = undefined;
    var next: u32 = 0;
    while (iterator.next()) |token| : (next += 1) {
        vec[next] = try std.fmt.parseFloat(f32, token);
    }

    return vec;
}

pub fn iterateIntoFace(iterator: *std.mem.TokenIterator(u8, .any)) Face.Error!Face {
    var face = Face.init();
    var count: u32 = 0;
    while (iterator.next()) |token| : (count += 1) {
        if (token.len == 0) {
            continue;
        }
        var face_iterator = std.mem.tokenizeAny(u8, token, "/");
        var inner_count: u32 = 0;
        if (count >= 4) {
            continue;
        }
        while (face_iterator.next()) |prop| : (inner_count += 1) {
            switch (inner_count) {
                0 => {
                    face.vertex[count] = std.fmt.parseInt(u32, prop, 10) catch return Face.Error.InvalidIndex;
                },
                1 => {
                    face.texture[count] = std.fmt.parseInt(u32, prop, 10) catch return Face.Error.InvalidIndex;
                },
                2 => {
                    face.normal[count] = std.fmt.parseInt(u32, prop, 10) catch return Face.Error.InvalidIndex;
                },
                else => return Face.Error.TooManyFaceProperties,
            }
        }
    }

    face.vertex_count = count;

    if (count > 4) {
        std.log.debug("We have a face larger than 4 polys? polyCount = {d}\n", .{face.vertex_count});
    }

    return face;
}

// test "parse_vector" {
//     {
//         const result = try parseLine("v 0.437500 0.765625 -0.164063", std.testing.allocator);
//         std.debug.print("\n", .{});
//         std.debug.print("{any}\n", .{result});
//         try std.testing.expect(result == .vertex);
//     }

//     {
//         const result = try parseLine("vn 0.437500 0.765625 -0.164063", std.testing.allocator);
//         std.debug.print("\n", .{});
//         std.debug.print("{any}\n", .{result});
//         try std.testing.expect(result == .normal);
//     }

//     {
//         const result = try parseLine("f 47//1 1//1 3//1 45//1", std.testing.allocator);
//         std.debug.print("\n", .{});
//         std.debug.print("{any}\n", .{result});
//         try std.testing.expect(result == .face);
//     }

//     {
//         const result = try parseLine("f 47//1 1//1 3//1 ", std.testing.allocator);
//         std.debug.print("\n", .{});
//         std.debug.print("{any}\n", .{result});
//         try std.testing.expect(result == .face);
//     }

//     {
//         const result = try parseLine("o Suzanne", std.testing.allocator);
//         std.debug.print("\n", .{});
//         std.debug.print("{any}\n", .{result});
//         try std.testing.expect(result == .object);
//     }

//     {
//         const result = try parseLine("g Suzanne", std.testing.allocator);
//         std.debug.print("\n", .{});
//         std.debug.print("{any}\n", .{result});
//         try std.testing.expect(result == .group);
//     }

//     {
//         const result = try parseLine("  # this is a comment ", std.testing.allocator);
//         std.debug.print("\n", .{});
//         try std.testing.expect(result == .comment);
//         std.debug.print("{s}\n", .{result.comment});
//     }
// }

// test "load_monkey_full" {
//     const monkey_obj_path = "src/Assets/Cube.obj";
//     var obj_contents = try Contents.load(std.testing.allocator, monkey_obj_path);
//     defer obj_contents.deinit();
//     try std.testing.expect(obj_contents.meshes.items.len == 1);
//     obj_contents.meshes.items[0].print_stats();
// }

// test "cube" {
//     var obj = try Contents.load(std.testing.allocator, "delete.obj");
//     defer obj.deinit();

//     obj.meshes.items[0].print_stats();
// }

// test "parse_monkey" {
//     const monkey_obj_path = "src/Assets/Cube.obj";

//     const file_contents = @embedFile("src/Assets/Cube.obj");
//     defer std.testing.allocator.free(file_contents);
//     var lines = fileIntoLines(file_contents);
//     var count: u32 = 0;
//     var vertex_count: u32 = 0;
//     var normal_count: u32 = 0;
//     var faces_count: u32 = 0;
//     var texture_count: u32 = 0;

//     while (lines.next()) |line| {
//         const result = parseLine(line, std.testing.allocator) catch {
//             continue;
//         };
//         if (result == .vertex)
//             vertex_count += 1;

//         if (result == .normal)
//             normal_count += 1;

//         if (result == .face)
//             faces_count += 1;

//         if (result == .texture)
//             texture_count += 1;

//         count += 1;
//     }

//     std.debug.print("{s} loaded, Vertices count = {d} Normals count = {d}, faces = {d}\n", .{
//         monkey_obj_path,
//         vertex_count,
//         normal_count,
//         faces_count,
//     });
// }
