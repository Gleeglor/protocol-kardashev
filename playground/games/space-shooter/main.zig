const std = @import("std");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const zmath = @import("zmath");
const math = std.math;
const shader = @import("shader.zig");
const file = @import("file.zig");

const gl = zopengl.bindings;
const gl_version_major: u16 = 4;
const gl_version_minor: u16 = 5;
const allocator = std.heap.page_allocator;

var global_arena: std.heap.ArenaAllocator = undefined;
var frame_arena: std.heap.ArenaAllocator = undefined;

var prng = std.Random.DefaultPrng.init(0xdeadbeef);
const random = prng.random();

const Mouse = struct {
    pos: [2]f32 = .{ 0, 0 },
    scroll: [2]f32 = .{ 0, 0 },
};

var mouse: Mouse = .{};

const Input = struct {
    keys: [512]bool = [_]bool{false} ** 512,
};

const input: Input = .{};

fn scroll_callback(_: *glfw.Window, xoffset: f64, yoffset: f64) callconv(.c) void {
    mouse.scroll[0] += @floatCast(xoffset);
    mouse.scroll[1] += @floatCast(yoffset);
}

// fn mouse_button_callback(_: *glfw.Window, mouse_button: glfw.MouseButton, action: glfw.Action, mods: glfw.Mods) callconv(.c) void {

// }

fn mouse_move_callback(_: *glfw.Window, xpos: f64, ypos: f64) callconv(.c) void {
    mouse.pos = .{ @floatCast(xpos), @floatCast(ypos) };
}

const BulletType = struct {
    damage: f32,
    scale: f32,
};

const Object = struct {
    acc: [2]f32 = .{ 0, 0 },
    pos: [2]f32 = .{ 0, 0 },
    vel: [2]f32 = .{ 0, 0 },
    angle: f32 = 0,
    render_type: u8 = 0,
};

const BoidMeta = struct {
    speed: f32 = 1,
};

const Boid = struct {
    obj: *Object,
    meta: *BoidMeta,
};

const spaceship_shape = shader.Shape{
    .indices = &[_]u32{ 0, 1, 3, 1, 2, 3 },
    .vertices = &[_]shader.Vertex{
        .{ .x = -0.5, .y = -0.75 }, // left
        .{ .x = 0, .y = -0.25 }, // bottom
        .{ .x = 0.5, .y = -0.75 }, // right
        .{ .x = 0, .y = 0.75 }, // top
    },
};

const bullet_shape = shader.Shape{
    .vertices = &[_]shader.Vertex{
        .{ .x = -0.5, .y = -0.2887 }, // bottom left
        .{ .x = 0.5, .y = -0.2887 }, // bottom right
        .{ .x = 0.0, .y = 0.5774 }, // top
    },
    .indices = &[_]u32{0},
};

const CollectionPool = struct {
    list: std.ArrayList(InstancedCollection) = std.ArrayList(InstancedCollection).empty,

    pub fn create(self: *CollectionPool, alloc: std.mem.Allocator) !usize {
        const index = self.list.items.len;
        _ = try self.list.append(alloc, InstancedCollection{});

        return index;
    }

    pub fn deinit(self: *CollectionPool, alloc: std.mem.Allocator) void {
        for (self.list.items) |*instanced_collection| {
            instanced_collection.deinit(alloc);
        }

        self.list.deinit(alloc);
    }

    pub fn bind_gl(self: *CollectionPool) void {
        for (self.list.items) |*instanced_collection| {
            instanced_collection.bind_gl();
        }
    }
};

const InstancedCollection = struct {
    list: std.MultiArrayList(Object) = std.MultiArrayList(Object).empty,

    shape: *const shader.Shape = &bullet_shape,

    vao: zopengl.wrapper.Uint = undefined,
    vbo: zopengl.wrapper.Uint = undefined,
    ebo: zopengl.wrapper.Uint = undefined,
    pos_ssbo: zopengl.wrapper.Uint = undefined,
    angle_ssbo: zopengl.wrapper.Uint = undefined,
    type_ssbo: zopengl.wrapper.Uint = undefined,

    pub fn init(self: *InstancedCollection, alloc: std.mem.Allocator, count: u32, shape: *const shader.Shape) !void {
        _ = try self.list.ensureTotalCapacity(alloc, count);
        self.list.len = count;

        self.shape = shape;

        gl.genVertexArrays(1, @ptrCast(&self.vao));
        gl.genBuffers(1, @ptrCast(&self.vbo));
        gl.genBuffers(1, @ptrCast(&self.pos_ssbo));
        gl.genBuffers(1, @ptrCast(&self.angle_ssbo));
        gl.genBuffers(1, @ptrCast(&self.type_ssbo));
        if (self.shape.indices.len != 0) {
            gl.genBuffers(1, @ptrCast(&self.ebo));
        }
    }

    pub fn deinit(self: *InstancedCollection, alloc: std.mem.Allocator) void {
        self.list.deinit(alloc);

        gl.deleteVertexArrays(1, @ptrCast(&self.vao));
        gl.deleteBuffers(1, @ptrCast(&self.vbo));
        gl.deleteBuffers(1, @ptrCast(&self.pos_ssbo));
        gl.deleteBuffers(1, @ptrCast(&self.angle_ssbo));
        gl.deleteBuffers(1, @ptrCast(&self.type_ssbo));
        if (self.shape.indices.len != 0) {
            gl.deleteBuffers(1, @ptrCast(&self.ebo));
        }
    }

    pub fn bind_gl(self: *InstancedCollection) void {
        gl.bindVertexArray(self.vao);

        gl.bindBuffer(gl.ARRAY_BUFFER, self.vbo);
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(@sizeOf(shader.Vertex) * self.shape.vertices.len), self.shape.vertices.ptr, gl.STATIC_DRAW);

        gl.vertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, @sizeOf(shader.Vertex), @ptrFromInt(0));
        gl.enableVertexAttribArray(0);

        const indices_count = self.shape.indices.len;

        // std.debug.print("{d}, {d}\n", .{ self.shape.indices.ptr[0], 0 });

        if (indices_count != 0) {
            gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.ebo);
            gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, @intCast(@sizeOf(u32) * indices_count), self.shape.indices.ptr, gl.STATIC_DRAW);
        }
        gl.bindVertexArray(0);
    }
};

pub fn main() !void {
    std.debug.print("Hello, glfw!\n", .{});

    try glfw.init();
    defer glfw.terminate();

    glfw.windowHint(.client_api, .opengl_api);
    glfw.windowHint(.context_version_major, gl_version_major);
    glfw.windowHint(.context_version_minor, gl_version_minor);
    glfw.windowHint(.opengl_profile, .opengl_core_profile);
    glfw.windowHint(.opengl_forward_compat, true);
    glfw.windowHint(.doublebuffer, true);

    const window = try glfw.createWindow(800, 800, "Zig OpenGL Triangle", null, null);
    defer window.destroy();

    const window_size = window.getSize();
    const aspect_ratio: f32 = @as(f32, @floatFromInt(window_size[0])) / @as(f32, @floatFromInt(window_size[1]));

    glfw.makeContextCurrent(window);
    try zopengl.loadCoreProfile(glfw.getProcAddress, gl_version_major, gl_version_minor);

    glfw.swapInterval(6);

    global_arena = std.heap.ArenaAllocator.init(allocator);
    defer global_arena.deinit();

    frame_arena = std.heap.ArenaAllocator.init(global_arena.allocator());
    _ = frame_arena.reset(.retain_capacity);
    const fa = frame_arena.allocator();

    // ── Shader setup ────────────────────────────────────────────────
    const vertex_shader: []u8 = try file.read_file("res/shaders/instanced-rendering.vert");
    const fragment_shader: []u8 = try file.read_file("res/shaders/instanced-rendering.frag");

    const program = try shader.createShaderProgram(vertex_shader, fragment_shader);
    defer gl.deleteProgram(program);

    // ── Triangle data ───────────────────────────────────────────────
    var camera = shader.Camera{};

    _ = glfw.setScrollCallback(window, scroll_callback);
    // _ = glfw.setMouseButtonCallback(window, mouse_button_callback);
    _ = glfw.setCursorPosCallback(window, mouse_move_callback);

    // var render_dataset: std.MultiArrayList(shader.RenderType) = std.MultiArrayList(shader.RenderType){};
    // defer render_dataset.deinit(fa);

    // // Add atleast the default render type
    // _ = try render_dataset.append(fa, .{});

    var collection_pool: CollectionPool = .{};
    defer collection_pool.deinit(fa);

    const bullet_collection_idx: usize = try collection_pool.create(fa);
    {
        const bullet_collection = &collection_pool.list.items[bullet_collection_idx];
        const bullet_count: u32 = 0;
        _ = try bullet_collection.init(fa, bullet_count, &bullet_shape);

        const pos: [][2]f32 = bullet_collection.list.items(.pos);
        const bullet_ratio = @sqrt(@as(f32, @floatFromInt(bullet_count))) * 4;
        var i: u32 = 0;
        while (i < bullet_count) : (i += 1) {
            pos[i] = .{
                random.float(f32) * bullet_ratio - bullet_ratio / 2,
                random.float(f32) * bullet_ratio - bullet_ratio / 2,
            };
        }
    }

    const boid_collection_idx: usize = try collection_pool.create(fa);
    {
        const boid_collection = &collection_pool.list.items[boid_collection_idx];
        const boid_count: u32 = 100000;
        _ = try boid_collection.init(fa, boid_count, &spaceship_shape);

        const pos: [][2]f32 = boid_collection.list.items(.pos); // assuming .pos = [2]f32 or Vec2 {x: f32, y: f32}
        const spaceship_ratio = @sqrt(@as(f32, @floatFromInt(boid_count))) * 4;
        var i: u32 = 0;
        while (i < boid_count) : (i += 1) {
            pos[i] = .{
                random.float(f32) * spaceship_ratio - spaceship_ratio / 2,
                random.float(f32) * spaceship_ratio - spaceship_ratio / 2,
            };
        }
    }

    const player_collection_idx: usize = try collection_pool.create(fa);
    {
        const player_collection = &collection_pool.list.items[player_collection_idx];
        _ = try player_collection.init(fa, 0, &spaceship_shape);
        _ = try player_collection.list.append(fa, .{});
    }

    collection_pool.bind_gl();
    gl.useProgram(program);

    gl.enable(gl.BLEND);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
    while (!window.shouldClose()) {
        glfw.pollEvents();

        gl.clearColor(0.06, 0.06, 0.08, 1.0);
        gl.clear(gl.COLOR_BUFFER_BIT);
        gl.enable(gl.PROGRAM_POINT_SIZE);

        const projection_loc = gl.getUniformLocation(program, @ptrCast("projection"));
        const view_loc = gl.getUniformLocation(program, @ptrCast("view"));
        const draw_mode_loc = gl.getUniformLocation(program, @ptrCast("draw_mode"));

        var view = zmath.identity();
        var projection = zmath.identity();

        const zoom = camera.zoom * std.math.pow(f32, 2.0, @floatCast(-mouse.scroll[1] * 0.3));

        {
            const angles = collection_pool.list.items[player_collection_idx].list.items(.angle); // assuming .pos = [2]f32 or Vec2 {x: f32, y: f32}
            const position = collection_pool.list.items[player_collection_idx].list.items(.pos); // assuming .pos = [2]f32 or Vec2 {x: f32, y: f32}
            const velocity = collection_pool.list.items[player_collection_idx].list.items(.vel); // assuming .pos = [2]f32 or Vec2 {x: f32, y: f32}
            const acceleration = collection_pool.list.items[player_collection_idx].list.items(.acc); // assuming .pos = [2]f32 or Vec2 {x: f32, y: f32}

            for (acceleration, angles) |*acc, *ang| {
                if (glfw.getKey(window, glfw.Key.w) != glfw.Action.release) {
                    const sincos = zmath.sincos(ang.*);
                    acc[0] += sincos[0] * 0.06;
                    acc[1] += sincos[1] * 0.06;
                }

                if (glfw.getKey(window, glfw.Key.s) != glfw.Action.release) {
                    const sincos = zmath.sincos(ang.*);
                    acc[0] -= sincos[0] * 0.1;
                    acc[1] -= sincos[1] * 0.1;
                }

                if (glfw.getKey(window, glfw.Key.a) != glfw.Action.release) {
                    ang.* -= 0.05;
                }

                if (glfw.getKey(window, glfw.Key.d) != glfw.Action.release) {
                    ang.* += 0.05;
                }
            }

            for (velocity, acceleration) |*vel, *acc| {
                vel[0] += acc[0];
                vel[1] += acc[1];

                acc[0] = 0;
                acc[1] = 0;
            }

            for (velocity) |*vel| {
                vel[0] *= 0.93;
                vel[1] *= 0.93;
            }

            for (position, velocity) |*pos, vel| {
                pos[0] += vel[0];
                pos[1] += vel[1];
            }

            if (position.len > 0) {
                camera.pos = position[0];
            }
        }

        {
            const angles = collection_pool.list.items[boid_collection_idx].list.items(.angle);
            const position = collection_pool.list.items[boid_collection_idx].list.items(.pos);
            const velocity = collection_pool.list.items[boid_collection_idx].list.items(.vel);
            const acceleration = collection_pool.list.items[boid_collection_idx].list.items(.acc);

            for (acceleration, angles, velocity) |*acc, *ang, vel| {
                const sc = zmath.sincos(random.float(f32) * 1000);

                acc[0] += sc[0] / 100;
                acc[1] += sc[1] / 100;

                ang.* = math.atan2(vel[0], vel[1]);
            }

            for (velocity, acceleration) |*vel, *acc| {
                vel[0] += acc[0];
                vel[1] += acc[1];

                acc[0] = 0;
                acc[1] = 0;
            }

            for (position, velocity) |*pos, vel| {
                pos[0] += vel[0];
                pos[1] += vel[1];
            }
        }

        view = zmath.mul(view, zmath.translation(-camera.pos[0], -camera.pos[1], -zoom));
        projection = zmath.mul(projection, zmath.perspectiveFovRhGl(math.degreesToRadians(45), aspect_ratio, 0.001, 1000000));

        const point_zoom = @max(100 / zoom, 1);
        gl.pointSize(@max(100 / zoom * 10, 1));
        const draw_mode: shader.DrawMode = if (point_zoom == 1) .points else .normal;

        gl.uniformMatrix4fv(projection_loc, 1, gl.FALSE, @ptrCast(&projection));
        gl.uniformMatrix4fv(view_loc, 1, gl.FALSE, @ptrCast(&view));
        gl.uniform1ui(draw_mode_loc, @as(gl.Uint, @intFromEnum(draw_mode)));

        for (collection_pool.list.items) |*collection| {
            const angles = collection.list.items(.angle);
            const position = collection.list.items(.pos);
            const render_types = collection.list.items(.render_type);

            const count = collection.list.len;

            gl.bindVertexArray(collection.vao);

            gl.bindBufferBase(gl.SHADER_STORAGE_BUFFER, 0, collection.pos_ssbo);
            gl.bindBufferBase(gl.SHADER_STORAGE_BUFFER, 1, collection.angle_ssbo);
            gl.bindBufferBase(gl.SHADER_STORAGE_BUFFER, 2, collection.type_ssbo);

            gl.bindBuffer(gl.SHADER_STORAGE_BUFFER, collection.pos_ssbo);
            gl.bufferData(
                gl.SHADER_STORAGE_BUFFER,
                @sizeOf([2]f32) * @as(i32, @intCast(count)),
                position.ptr,
                gl.DYNAMIC_DRAW,
            );

            gl.bindBuffer(gl.SHADER_STORAGE_BUFFER, collection.angle_ssbo);
            gl.bufferData(
                gl.SHADER_STORAGE_BUFFER,
                @sizeOf(f32) * @as(i32, @intCast(count)),
                angles.ptr,
                gl.DYNAMIC_DRAW,
            );

            gl.bindBuffer(gl.SHADER_STORAGE_BUFFER, collection.type_ssbo);
            gl.bufferData(
                gl.SHADER_STORAGE_BUFFER,
                @sizeOf(u8) * @as(i32, @intCast(count)),
                render_types.ptr,
                gl.DYNAMIC_DRAW,
            );

            // gl.drawArraysInstanced(gl.POINTS, 0, 1, @as(i32, @intCast(count)));

            // std.debug.print("{d}, {d}\n", .{ collection.shape.indices.len, collection.shape.vertices.len });
            if (point_zoom == 1) {
                gl.drawArraysInstanced(gl.POINTS, 0, 1, @as(i32, @intCast(count)));
            } else {
                if (collection.shape.indices.len != 0) {
                    gl.drawElementsInstanced(
                        gl.TRIANGLES,
                        @as(i32, @intCast(collection.shape.indices.len)),
                        gl.UNSIGNED_INT,
                        null,
                        @as(i32, @intCast(count)),
                    );
                } else {
                    // gl.drawArraysInstanced(
                    //     gl.TRIANGLES,
                    //     0,
                    //     @as(i32, @intCast(collection.shape.vertices.len)),
                    //     @as(i32, @intCast(count)),
                    // );
                }
            }

            const err = gl.getError();
            if (err != gl.NO_ERROR) {
                std.debug.print("GL error: {d}\n", .{err});
                return;
                // or better — break/return/panic with message
            }
        }

        gl.bindVertexArray(0);
        window.swapBuffers();
    }
}
