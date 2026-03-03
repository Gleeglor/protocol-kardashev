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
    render_type: u32 = 0,
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

    var render_dataset: std.MultiArrayList(shader.RenderType) = std.MultiArrayList(shader.RenderType){};
    defer render_dataset.deinit(fa);

    // Add atleast the default render type
    _ = try render_dataset.append(fa, .{});

    const bullet_count = 5000;
    var bullet_dataset: std.MultiArrayList(Object) = std.MultiArrayList(Object){};
    defer bullet_dataset.deinit(fa);

    const bullet_ratio = @sqrt(@as(f32, @floatFromInt(bullet_count))) * 4;
    var i: u32 = 0;
    while (i < bullet_count) : (i += 1) {
        const x = random.float(f32) * bullet_ratio - bullet_ratio / 2;
        const y = random.float(f32) * bullet_ratio - bullet_ratio / 2;
        const bullet: Object = .{
            .pos = .{ x, y },
        };
        _ = try bullet_dataset.append(fa, bullet);
    }

    const spaceship_count = 5000000;
    var spaceship_dataset = std.MultiArrayList(Object){};
    try spaceship_dataset.ensureTotalCapacity(fa, spaceship_count);
    defer spaceship_dataset.deinit(fa);
    spaceship_dataset.len = spaceship_count;

    const pos = spaceship_dataset.items(.pos); // assuming .pos = [2]f32 or Vec2 {x: f32, y: f32}

    const spaceship_ratio = @sqrt(@as(f32, @floatFromInt(spaceship_count))) * 4;
    i = 0;
    while (i < spaceship_count) : (i += 1) {
        pos[i] = .{
            random.float(f32) * spaceship_ratio - spaceship_ratio / 2,
            random.float(f32) * spaceship_ratio - spaceship_ratio / 2,
        };
    }

    const player_index = 0; // try spaceship_dataset.addOne(allocator);

    const spaceship_rectangle = shader.Rectangle{
        .indices = .{ 0, 1, 3, 1, 2, 3 },
        .vertices = .{
            .{ .x = -0.5, .y = -0.75 }, // left
            .{ .x = 0, .y = -0.25 }, // bottom
            .{ .x = 0.5, .y = -0.75 }, // right
            .{ .x = 0, .y = 0.75 }, // top
        },
    };

    const bullet_triangle = shader.Triangle{
        .vertices = .{
            .{ .x = -0.5, .y = -0.2887 }, // bottom left
            .{ .x = 0.5, .y = -0.2887 }, // bottom right
            .{ .x = 0.0, .y = 0.5774 }, // top
        },
    };

    var spaceship_vao: zopengl.wrapper.Uint = undefined; // header
    var spaceship_vbo: zopengl.wrapper.Uint = undefined; // body
    var pos_ssbo: zopengl.wrapper.Uint = undefined;
    var angle_ssbo: zopengl.wrapper.Uint = undefined;
    var type_ssbo: zopengl.wrapper.Uint = undefined;
    var ebo: zopengl.wrapper.Uint = undefined;
    var bullet_vao: zopengl.wrapper.Uint = undefined; // header
    var bullet_vbo: zopengl.wrapper.Uint = undefined; // body
    var bullet_ssbo: zopengl.wrapper.Uint = undefined;

    gl.genVertexArrays(1, @ptrCast(&spaceship_vao));
    defer gl.deleteVertexArrays(1, @ptrCast(&spaceship_vao));

    gl.genBuffers(1, @ptrCast(&spaceship_vbo));
    defer gl.deleteBuffers(1, @ptrCast(&spaceship_vbo));

    gl.genBuffers(1, @ptrCast(&pos_ssbo));
    defer gl.deleteBuffers(1, @ptrCast(&pos_ssbo));

    gl.genBuffers(1, @ptrCast(&angle_ssbo));
    defer gl.deleteBuffers(1, @ptrCast(&angle_ssbo));

    gl.genBuffers(1, @ptrCast(&type_ssbo));
    defer gl.deleteBuffers(1, @ptrCast(&type_ssbo));

    gl.genBuffers(1, @ptrCast(&ebo));
    defer gl.deleteBuffers(1, @ptrCast(&ebo));

    gl.genVertexArrays(1, @ptrCast(&bullet_vao));
    defer gl.deleteVertexArrays(1, @ptrCast(&bullet_vao));

    gl.genBuffers(1, @ptrCast(&bullet_vbo));
    defer gl.deleteBuffers(1, @ptrCast(&bullet_vbo));

    gl.genBuffers(1, @ptrCast(&bullet_ssbo));
    defer gl.deleteBuffers(1, @ptrCast(&bullet_ssbo));

    gl.bindVertexArray(spaceship_vao);

    gl.bindBufferBase(gl.SHADER_STORAGE_BUFFER, 0, pos_ssbo);
    gl.bindBufferBase(gl.SHADER_STORAGE_BUFFER, 1, angle_ssbo);
    gl.bindBufferBase(gl.SHADER_STORAGE_BUFFER, 2, type_ssbo);

    gl.bindBuffer(gl.ARRAY_BUFFER, spaceship_vbo);
    gl.bufferData(gl.ARRAY_BUFFER, @sizeOf(@TypeOf(spaceship_rectangle.vertices)), &spaceship_rectangle.vertices, gl.STATIC_DRAW);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, @sizeOf(shader.Vertex), @ptrFromInt(0));

    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo);
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, @sizeOf(@TypeOf(spaceship_rectangle.indices)), &spaceship_rectangle.indices, gl.STATIC_DRAW);

    gl.bindVertexArray(bullet_vao);

    gl.bindBuffer(gl.ARRAY_BUFFER, bullet_vbo);
    gl.bufferData(gl.ARRAY_BUFFER, @sizeOf(@TypeOf(bullet_triangle.vertices)), &bullet_triangle.vertices, gl.STATIC_DRAW);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, @sizeOf(shader.Vertex), @ptrFromInt(0));

    gl.bindBuffer(gl.SHADER_STORAGE_BUFFER, bullet_ssbo);
    gl.bindBufferBase(gl.SHADER_STORAGE_BUFFER, 2, bullet_ssbo);

    gl.vertexAttribDivisor(0, 0);

    while (!window.shouldClose()) {
        glfw.pollEvents();

        gl.clearColor(0.06, 0.06, 0.08, 1.0);
        gl.clear(gl.COLOR_BUFFER_BIT);

        gl.useProgram(program);

        const projection_loc = gl.getUniformLocation(program, @ptrCast("projection"));
        const view_loc = gl.getUniformLocation(program, @ptrCast("view"));

        var view = zmath.identity();
        var projection = zmath.identity();

        const zoom = camera.zoom * std.math.pow(f32, 2.0, @floatCast(-mouse.scroll[1] * 0.3));

        var player_entity = spaceship_dataset.get(player_index);
        if (glfw.getKey(window, glfw.Key.w) != glfw.Action.release) {
            const sincos = zmath.sincos(player_entity.angle);
            player_entity.acc[0] += sincos[0] * 0.06;
            player_entity.acc[1] += sincos[1] * 0.06;
        }

        if (glfw.getKey(window, glfw.Key.s) != glfw.Action.release) {
            const sincos = zmath.sincos(player_entity.angle);
            player_entity.acc[0] -= sincos[0] * 0.1;
            player_entity.acc[1] -= sincos[1] * 0.1;
        }

        if (glfw.getKey(window, glfw.Key.a) != glfw.Action.release) {
            player_entity.angle = player_entity.angle - 0.05;
        }

        if (glfw.getKey(window, glfw.Key.d) != glfw.Action.release) {
            player_entity.angle = player_entity.angle + 0.05;
        }

        player_entity.vel[0] += player_entity.acc[0];
        player_entity.vel[1] += player_entity.acc[1];

        player_entity.acc[0] = 0;
        player_entity.acc[1] = 0;

        player_entity.pos[0] += player_entity.vel[0];
        player_entity.pos[1] += player_entity.vel[1];

        player_entity.vel[0] *= 0.93;
        player_entity.vel[1] *= 0.93;

        spaceship_dataset.set(player_index, player_entity);

        camera.pos = player_entity.pos;
        view = zmath.mul(view, zmath.translation(-camera.pos[0], -camera.pos[1], -zoom));
        projection = zmath.mul(projection, zmath.perspectiveFovRhGl(math.degreesToRadians(45), aspect_ratio, 0.001, 10000));

        gl.uniformMatrix4fv(projection_loc, 1, gl.FALSE, @ptrCast(&projection));
        gl.uniformMatrix4fv(view_loc, 1, gl.FALSE, @ptrCast(&view));

        gl.bindVertexArray(spaceship_vao);
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo);

        const n = spaceship_dataset.len;
        const sd_slice = spaceship_dataset.slice();

        for (pos) |*p| {
            p[0] += 0.1;
        }

        gl.bindBuffer(gl.SHADER_STORAGE_BUFFER, pos_ssbo);
        gl.bufferData(
            gl.SHADER_STORAGE_BUFFER,
            @sizeOf([2]f32) * @as(i32, @intCast(n)),
            sd_slice.items(.pos).ptr,
            gl.DYNAMIC_DRAW,
        );

        gl.bindBuffer(gl.SHADER_STORAGE_BUFFER, angle_ssbo);
        gl.bufferData(
            gl.SHADER_STORAGE_BUFFER,
            @sizeOf(f32) * @as(i32, @intCast(n)),
            sd_slice.items(.angle).ptr,
            gl.DYNAMIC_DRAW,
        );

        gl.bindBuffer(gl.SHADER_STORAGE_BUFFER, type_ssbo);
        gl.bufferData(
            gl.SHADER_STORAGE_BUFFER,
            @sizeOf(u32) * @as(i32, @intCast(n)),
            sd_slice.items(.render_type).ptr,
            gl.DYNAMIC_DRAW,
        );

        gl.drawElementsInstanced(
            gl.TRIANGLES,
            6,
            gl.UNSIGNED_INT,
            @ptrFromInt(0),
            @as(i32, @intCast(1)),
        );

        // // Bullets
        // for (bullet_list.items, 0..) |*bullet, index| {
        //     bullet.angle = @as(f32, @floatCast(glfw.getTime() * 10)) + @as(f32, @floatFromInt(index));
        // }

        // gl.bindVertexArray(bullet_vao);

        // gl.bufferData(
        //     gl.SHADER_STORAGE_BUFFER,
        //     @sizeOf(shader.RenderData) * @as(i32, @intCast(bullet_list.items.len)),
        //     bullet_list.items.ptr,
        //     gl.DYNAMIC_DRAW,
        // );

        // gl.drawArraysInstanced(
        //     gl.TRIANGLES,
        //     0,
        //     3,
        //     @as(i32, @intCast(bullet_list.items.len)),
        // );

        gl.bindVertexArray(0);

        window.swapBuffers();
    }
}
