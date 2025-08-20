const Face = @This();

pub const Error = error{
    FaceReferencesInvalidVertex,
    TooManyFaceProperties,
    InvalidIndex,
};

vertex: @Vector(4, u32),
texture: @Vector(4, u32),
normal: @Vector(4, u32),
vertex_count: u32,

pub fn init() Face {
    return .{
        .vertex = .{ 0, 0, 0, 0 },
        .texture = .{ 0, 0, 0, 0 },
        .normal = .{ 0, 0, 0, 0 },
        .vertex_count = 0,
    };
}
