const Color = @import("Color.zig");
const Face = @import("Face.zig");

const std = @import("std");

pub const F32x3 = @Vector(3, f32);
pub const F32x2 = @Vector(2, f32);

const Mesh = @This();

positions: std.ArrayListUnmanaged(F32x3) = .{},
colors: std.ArrayListUnmanaged(Color) = .{},
normals: std.ArrayListUnmanaged(F32x3) = .{},
uvs: std.ArrayListUnmanaged(F32x2) = .{},
faces: std.ArrayListUnmanaged(Face) = .{},
allocator: std.mem.Allocator,

pub fn validateMesh(self: Mesh) Face.Error!void {
    for (self.faces.items) |face| {
        var i: u32 = 0;
        while (i < face.vertex_count) : (i += 1) {
            if (face.vertex[i] > self.positions.items.len) {
                return Face.Error.FaceReferencesInvalidVertex;
            }
            if (face.normal[i] > self.normals.items.len) {
                return Face.Error.FaceReferencesInvalidVertex;
            }
            if (face.texture[i] > self.uvs.items.len) {
                return Face.Error.FaceReferencesInvalidVertex;
            }
        }
    }
}

pub fn print(self: Mesh) void {
    std.log.debug("obj: {s}, Vertices count = {d} Normals count = {d}, faces = {d} texures = {d}\n", .{
        self.object_name,
        self.positions.items.len,
        self.normals.items.len,
        self.faces.items.len,
        self.uvs.items.len,
    });
}

pub fn init(allocator: std.mem.Allocator) !Mesh {
    const self = Mesh{
        .allocator = allocator,
    };

    return self;
}

pub fn deinit(self: *Mesh) void {
    self.positions.deinit(self.allocator);
    self.colors.deinit(self.allocator);
    self.normals.deinit(self.allocator);
    self.uvs.deinit(self.allocator);
    self.faces.deinit(self.allocator);
}
