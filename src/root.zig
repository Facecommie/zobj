const std = @import("std");

const ArrayListUnmanaged = std.ArrayListUnmanaged;

pub fn loadObj(allocator: std.mem.Allocator, filename: []const u8) !ObjContents {
    return try ObjContents.load(allocator, filename);
}

// Higher level file functions.
pub fn loadFileAlloc(
    allocator: std.mem.Allocator,
    filename: []const u8,
    comptime alignment: std.mem.Alignment,
) ![]const u8 {
    const file = try std.fs.cwd().openFile(filename, .{ .mode = .read_only });
    defer file.close();
    const stat = try file.stat();
    const filesize = stat.size;

    const buffer = try allocator.alignedAlloc(u8, alignment, filesize);
    errdefer allocator.free(buffer);

    const bytesRead = try file.readAll(buffer);
    if (bytesRead != filesize)
        return error.UnexpectedEndOfFile;

    return buffer;
}

pub const Vec3 = @Vector(3, f32);

pub const Vec2 = @Vector(2, f32);

pub const Color = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

pub const Face = struct {
    vertex: [4]u32,
    texture: [4]u32,
    normal: [4]u32,
    count: u32,

    pub fn init() Face {
        return .{
            .vertex = .{ 0, 0, 0, 0 },
            .texture = .{ 0, 0, 0, 0 },
            .normal = .{ 0, 0, 0, 0 },
            .count = 0,
        };
    }
};

pub const ObjMesh = struct {
    object_name: []u8,
    v_positions: ArrayListUnmanaged(Vec3) = .{},
    v_colors: ArrayListUnmanaged(Color) = .{},
    v_normals: ArrayListUnmanaged(Vec3) = .{},
    v_uvs: ArrayListUnmanaged(Vec2) = .{},
    v_faces: ArrayListUnmanaged(Face) = .{},
    allocator: std.mem.Allocator,

    pub fn validate_mesh(self: ObjMesh) !void {
        for (self.v_faces.items) |face| {
            var i: u32 = 0;
            while (i < face.count) {
                if (face.vertex[i] > self.v_positions.items.len)
                    return error.FaceReferencesInvalidVertex;
                if (face.normal[i] > self.v_normals.items.len)
                    return error.FaceReferencesInvalidNormal;
                if (face.texture[i] > self.v_uvs.items.len)
                    return error.FaceReferencesInvalidTexture;
                i += 1;
            }
        }
    }

    pub fn print_stats(self: ObjMesh) void {
        std.debug.print("obj: {s}, Vertices count = {d} Normals count = {d}, faces = {d} texures = {d}\n", .{
            self.object_name,
            self.v_positions.items.len,
            self.v_normals.items.len,
            self.v_faces.items.len,
            self.v_uvs.items.len,
        });
    }

    pub fn init(_object_name: []const u8, allocator: std.mem.Allocator) !ObjMesh {
        const object_name = try allocator.alloc(u8, _object_name.len);

        @memmove(object_name, _object_name);

        const self = ObjMesh{
            .object_name = object_name,
            .allocator = allocator,
        };

        return self;
    }

    pub fn setName(self: *ObjMesh, name: []const u8) !void {
        self.allocator.free(self.object_name);
        self.object_name = try self.allocator.alloc(u8, name.len);
        @memmove(self.object_name, name);
    }

    pub fn deinit(self: *ObjMesh) void {
        self.v_positions.deinit(self.allocator);
        self.v_colors.deinit(self.allocator);
        self.v_normals.deinit(self.allocator);
        self.v_uvs.deinit(self.allocator);
        self.v_faces.deinit(self.allocator);
        self.allocator.free(self.object_name);
    }
};

const ResultType = enum {
    vertex,
    color,
    normal,
    face,
    object,
    group,
    comment,
    texture,
};

const LineParseResult = union(ResultType) {
    vertex: Vec3,
    color: Color,
    normal: Vec3,
    face: Face,
    object: []const u8,
    group: []const u8,
    comment: []const u8,
    texture: Vec2,
};

fn iterIntoVec2(iter: anytype) !Vec2 {
    var vec: Vec2 = undefined;
    var next: u32 = 0;
    while (iter.next()) |tok| {
        switch (next) {
            0 => {
                vec[0] = try std.fmt.parseFloat(f32, tok);
            },
            1 => {
                vec[1] = try std.fmt.parseFloat(f32, tok);
            },
            else => {
                return error.UnexpectedVectorPosition;
            },
        }
        next += 1;
    }

    return vec;
}

fn iterIntoVec3(iter: anytype) !Vec3 {
    var vec: Vec3 = undefined;
    var next: u32 = 0;
    while (iter.next()) |tok| {
        switch (next) {
            0 => {
                vec[0] = try std.fmt.parseFloat(f32, tok);
            },
            1 => {
                vec[1] = try std.fmt.parseFloat(f32, tok);
            },
            2 => {
                vec[2] = try std.fmt.parseFloat(f32, tok);
            },
            else => {
                return error.UnexpectedVectorPosition;
            },
        }
        next += 1;
    }

    return vec;
}

pub fn toksIntoFace(toks: anytype) !Face {
    var rv = Face.init();
    var count: u32 = 0;
    while (toks.next()) |tok| {
        if (tok.len == 0)
            continue;
        var face_desc = std.mem.tokenizeAny(u8, tok, "/");
        var ic: u32 = 0; // ic= inner_count
        if (count >= 4) {
            continue;
        }
        while (face_desc.next()) |prop| {
            switch (ic) {
                0 => {
                    rv.vertex[count] = std.fmt.parseInt(u32, prop, 10) catch 0;
                },
                1 => {
                    rv.texture[count] = std.fmt.parseInt(u32, prop, 10) catch 0;
                },
                2 => {
                    rv.normal[count] = std.fmt.parseInt(u32, prop, 10) catch 0;
                },
                else => return error.TooManyfaceProperties,
            }

            ic += 1;
        }
        count += 1;
    }

    rv.count = count;

    if (rv.count > 4) {
        std.debug.print("We have a face larger than 4 polys? polyCount = {d}\n", .{rv.count});
    }

    return rv;
}

fn parse_line(lineIn: []const u8, allocator: std.mem.Allocator) !LineParseResult {
    _ = allocator;
    var line: []const u8 = lineIn;

    if (line.len <= 0)
        return LineParseResult{ .comment = "<<empty line>>" };
    while (line[0] == ' ') {
        line = line[1..line.len];
    }

    var tokens = std.mem.tokenizeAny(u8, line, " ");
    const first = tokens.next().?;

    if (line[0] == '#') {
        return LineParseResult{
            .comment = if (line.len > 1) line[1..line.len] else line[0..line.len],
        };
    }

    if (std.mem.eql(u8, "mtllib", first)) {
        return LineParseResult{
            .comment = "gonna ignore mtllibs for now.",
        };
    }

    if (std.mem.eql(u8, "vt", first)) {
        return LineParseResult{
            .texture = try iterIntoVec2(&tokens),
        };
    }

    if (std.mem.eql(u8, "vn", first)) {
        return LineParseResult{
            .normal = try iterIntoVec3(&tokens),
        };
    }

    if (std.mem.eql(u8, "v", first)) {
        return LineParseResult{
            .vertex = try iterIntoVec3(&tokens),
        };
    }
    if (std.mem.eql(u8, "f", first)) {
        return LineParseResult{
            .face = try toksIntoFace(&tokens),
        };
    } else if (std.mem.eql(u8, "g", first)) {
        // get a slice of the entire group
        const groupName = line[first.len + 1 .. line.len];
        return LineParseResult{
            .group = groupName,
        };
    } else if (std.mem.eql(u8, "o", first)) {
        // get a slice of the entire group
        const groupName = line[first.len + 1 .. line.len];
        std.debug.print("LOADING OBJECT: {s}\n", .{groupName});
        return LineParseResult{
            .object = groupName,
        };
    } else if (std.mem.eql(u8, "usemtl", first)) {
        return LineParseResult{
            .comment = "not yet implemented",
        };
    } else if (std.mem.eql(u8, "s", first)) {
        return LineParseResult{
            .comment = "not yet implemented",
        };
    }

    // std.debug.print("error: unrecognized header: `{s}` in line: {s} \n", .{ first, line });

    return error.NotImplemented;
}

test "parse_vector" {
    {
        const result = try parse_line("v 0.437500 0.765625 -0.164063", std.testing.allocator);
        std.debug.print("\n", .{});
        std.debug.print("{any}\n", .{result});
        try std.testing.expect(result == .vertex);
    }

    {
        const result = try parse_line("vn 0.437500 0.765625 -0.164063", std.testing.allocator);
        std.debug.print("\n", .{});
        std.debug.print("{any}\n", .{result});
        try std.testing.expect(result == .normal);
    }

    {
        const result = try parse_line("f 47//1 1//1 3//1 45//1", std.testing.allocator);
        std.debug.print("\n", .{});
        std.debug.print("{any}\n", .{result});
        try std.testing.expect(result == .face);
    }

    {
        const result = try parse_line("f 47//1 1//1 3//1 ", std.testing.allocator);
        std.debug.print("\n", .{});
        std.debug.print("{any}\n", .{result});
        try std.testing.expect(result == .face);
    }

    {
        const result = try parse_line("o Suzanne", std.testing.allocator);
        std.debug.print("\n", .{});
        std.debug.print("{any}\n", .{result});
        try std.testing.expect(result == .object);
    }

    {
        const result = try parse_line("g Suzanne", std.testing.allocator);
        std.debug.print("\n", .{});
        std.debug.print("{any}\n", .{result});
        try std.testing.expect(result == .group);
    }

    {
        const result = try parse_line("  # this is a comment ", std.testing.allocator);
        std.debug.print("\n", .{});
        try std.testing.expect(result == .comment);
        std.debug.print("{s}\n", .{result.comment});
    }
}

pub fn fileIntoLines(file_contents: []const u8) std.mem.SplitIterator(u8, .any) {
    // find a \n and see if it has \r\n
    var index: u32 = 0;
    while (index < file_contents.len) : (index += 1) {
        if (file_contents[index] == '\n') {
            if (index > 0) {
                if (file_contents[index - 1] == '\r') {
                    return std.mem.splitAny(u8, file_contents, "\r\n");
                } else {
                    return std.mem.splitAny(u8, file_contents, "\n");
                }
            } else {
                return std.mem.splitAny(u8, file_contents, "\n");
            }
        }
    }
    return std.mem.splitAny(u8, file_contents, "\n");
}

const ObjContents = struct {
    meshes: std.ArrayList(ObjMesh),

    pub fn load(allocator: std.mem.Allocator, filename: []const u8) !ObjContents {
        var self = ObjContents{
            .meshes = std.ArrayList(ObjMesh).init(allocator),
        };

        var mesh = try ObjMesh.init("root", allocator);

        const file_contents = try loadFileAlloc(allocator, filename, std.mem.Alignment.@"1");
        defer allocator.free(file_contents);
        var lines = fileIntoLines(file_contents);

        while (lines.next()) |line| {
            const result = parse_line(line, allocator) catch continue;

            if (result == .object) {
                if (mesh.v_positions.items.len > 0) {
                    try self.meshes.append(mesh);
                    mesh = try ObjMesh.init(result.object, allocator);
                } else {
                    try mesh.setName(result.object);
                }
            }

            if (result == .vertex) {
                try mesh.v_positions.append(mesh.allocator, result.vertex);
            }

            if (result == .normal) {
                try mesh.v_normals.append(mesh.allocator, result.normal);
            }

            if (result == .face) {
                try mesh.v_faces.append(mesh.allocator, result.face);
            }

            if (result == .texture) {
                try mesh.v_uvs.append(mesh.allocator, result.texture);
            }
        }
        try self.meshes.append(mesh);
        return self;
    }

    pub fn deinit(self: *ObjContents) void {
        for (self.meshes.items, 0..) |_, i| {
            self.meshes.items[i].deinit();
        }
        self.meshes.deinit();
    }
};

test "load_monkey_full" {
    const monkey_obj_path = "test/monkey.obj";
    var obj_contents = try ObjContents.load(std.testing.allocator, monkey_obj_path);
    defer obj_contents.deinit();
    try std.testing.expect(obj_contents.meshes.items.len == 1);
    obj_contents.meshes.items[0].print_stats();
}

test "parse_monkey" {
    const monkey_obj_path = "test/monkey.obj";
    const monkey_mtl_path = "test/monkey.mtl";
    _ = monkey_mtl_path;

    const file_contents = try loadFileAlloc(std.testing.allocator, monkey_obj_path, std.mem.Alignment.@"1");
    defer std.testing.allocator.free(file_contents);
    var lines = fileIntoLines(file_contents);
    var count: u32 = 0;
    var vertex_count: u32 = 0;
    var normal_count: u32 = 0;
    var faces_count: u32 = 0;
    var texture_count: u32 = 0;

    while (lines.next()) |line| {
        const result = parse_line(line, std.testing.allocator) catch {
            continue;
        };
        if (result == .vertex)
            vertex_count += 1;

        if (result == .normal)
            normal_count += 1;

        if (result == .face)
            faces_count += 1;

        if (result == .texture)
            texture_count += 1;

        count += 1;
    }

    std.debug.print("{s} loaded, Vertices count = {d} Normals count = {d}, faces = {d}\n", .{
        monkey_obj_path,
        vertex_count,
        normal_count,
        faces_count,
    });
}
