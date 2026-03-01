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

// fn getThisAndOther(i: u32) struct { this_value: f32, other: u32, level: u32 } {
//     if (i == 0) return .{ .this_value = 0.0, .other = 0, .level = 0 };

//     var remaining: u32 = i;
//     var level: u32 = 1;

//     while (true) {
//         const group_size: u32 = math.pow(u32, level + 2, 2);

//         if (remaining <= group_size) {
//             const this_value = std.math.pow(f32, @as(f32, @floatFromInt(level)) + 2, 2);
//             return .{ .this_value = this_value, .other = remaining, .level = level };
//         }

//         remaining -= group_size;
//         level += 1;
//     }
// }

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

    glfw.swapInterval(1);

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

    const Spaceship = struct {
        pos: [2]f32 = .{ 0, 0 },
        angle: f32 = 0,
        vel: [2]f32 = .{ 0, 0 },
        acc: [2]f32 = .{ 0, 0 },
    };

    var player: Spaceship = .{};

    const bullet_count = 5000;
    var bullet_list = std.ArrayList(shader.InstanceData).empty;
    defer bullet_list.deinit(allocator);

    const bullet_ratio = @sqrt(@as(f32, @floatFromInt(bullet_count))) * 4;
    var i: u32 = 0;
    while (i < bullet_count) : (i += 1) {
        var mat = zmath.identity();
        mat = zmath.mul(mat, zmath.translation(random.float(f32) * bullet_ratio - bullet_ratio / 2, random.float(f32) * bullet_ratio - bullet_ratio / 2, 0));
        try bullet_list.append(allocator, .{
            .mat = mat,
            .color = .{ 1, 1, 1, 1 },
        });
    }

    const spaceship_count = 5000;
    var spaceship_list = std.ArrayList(shader.InstanceData).empty;
    defer spaceship_list.deinit(allocator);

    const spaceship_ratio = @sqrt(@as(f32, @floatFromInt(spaceship_count))) * 4;
    i = 0;
    while (i < spaceship_count) : (i += 1) {
        var mat = zmath.identity();
        mat = zmath.mul(mat, zmath.translation(random.float(f32) * spaceship_ratio - spaceship_ratio / 2, random.float(f32) * spaceship_ratio - spaceship_ratio / 2, 0));
        try spaceship_list.append(allocator, .{
            .mat = mat,
            .color = .{ 1, 1, 1, 1 },
        });
    }

    const player_index = spaceship_list.items.len;
    try spaceship_list.append(allocator, .{
        .mat = zmath.identity(),
        .color = .{ 1, 1, 1, 1 },
    });

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
    var spaceship_ssbo: zopengl.wrapper.Uint = undefined;
    var ebo: zopengl.wrapper.Uint = undefined;
    var bullet_vao: zopengl.wrapper.Uint = undefined; // header
    var bullet_vbo: zopengl.wrapper.Uint = undefined; // body
    var bullet_ssbo: zopengl.wrapper.Uint = undefined;

    gl.genVertexArrays(1, @ptrCast(&spaceship_vao));
    defer gl.deleteVertexArrays(1, @ptrCast(&spaceship_vao));

    gl.genBuffers(1, @ptrCast(&spaceship_vbo));
    defer gl.deleteBuffers(1, @ptrCast(&spaceship_vbo));

    gl.genBuffers(1, @ptrCast(&spaceship_ssbo));
    defer gl.deleteBuffers(1, @ptrCast(&spaceship_ssbo));

    gl.genBuffers(1, @ptrCast(&ebo));
    defer gl.deleteBuffers(1, @ptrCast(&ebo));

    gl.genVertexArrays(1, @ptrCast(&bullet_vao));
    defer gl.deleteVertexArrays(1, @ptrCast(&bullet_vao));

    gl.genBuffers(1, @ptrCast(&bullet_vbo));
    defer gl.deleteBuffers(1, @ptrCast(&bullet_vbo));

    gl.genBuffers(1, @ptrCast(&bullet_ssbo));
    defer gl.deleteBuffers(1, @ptrCast(&bullet_ssbo));

    gl.bindVertexArray(spaceship_vao);

    gl.bindBuffer(gl.ARRAY_BUFFER, spaceship_vbo);
    gl.bufferData(gl.ARRAY_BUFFER, @sizeOf(@TypeOf(spaceship_rectangle.vertices)), &spaceship_rectangle.vertices, gl.STATIC_DRAW);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, @sizeOf(shader.Vertex), @ptrFromInt(0));

    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo);
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, @sizeOf(@TypeOf(spaceship_rectangle.indices)), &spaceship_rectangle.indices, gl.STATIC_DRAW);

    gl.bindBuffer(gl.SHADER_STORAGE_BUFFER, spaceship_ssbo);
    gl.bindBufferBase(gl.SHADER_STORAGE_BUFFER, 2, spaceship_ssbo);

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

        player = player;
        camera = camera;

        if (glfw.getKey(window, glfw.Key.w) != glfw.Action.release) {
            const sincos = zmath.sincos(player.angle);
            player.acc[0] += sincos[0] * 0.06;
            player.acc[1] += sincos[1] * 0.06;
        }

        if (glfw.getKey(window, glfw.Key.s) != glfw.Action.release) {
            const sincos = zmath.sincos(player.angle);
            player.acc[0] -= sincos[0] * 0.1;
            player.acc[1] -= sincos[1] * 0.1;
        }

        if (glfw.getKey(window, glfw.Key.a) != glfw.Action.release) {
            player.angle -= 0.05;
        }

        if (glfw.getKey(window, glfw.Key.d) != glfw.Action.release) {
            player.angle += 0.05;
        }

        player.vel[0] += player.acc[0];
        player.vel[1] += player.acc[1];

        player.acc[0] = 0;
        player.acc[1] = 0;

        player.pos[0] += player.vel[0];
        player.pos[1] += player.vel[1];

        player.vel[0] *= 0.93;
        player.vel[1] *= 0.93;

        var mat = zmath.identity();
        mat = zmath.mul(mat, zmath.rotationZ(-player.angle));
        mat = zmath.mul(mat, zmath.translation(player.pos[0], player.pos[1], 0));
        spaceship_list.items[player_index].mat = mat;

        camera.pos = player.pos;
        view = zmath.mul(view, zmath.translation(-camera.pos[0], -camera.pos[1], -zoom));
        projection = zmath.mul(projection, zmath.perspectiveFovRhGl(math.degreesToRadians(45), aspect_ratio, 0.001, 10000));

        gl.uniformMatrix4fv(projection_loc, 1, gl.FALSE, @ptrCast(&projection));
        gl.uniformMatrix4fv(view_loc, 1, gl.FALSE, @ptrCast(&view));

        gl.bindVertexArray(spaceship_vao);
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo);

        // Spaceship
        gl.bufferData(
            gl.SHADER_STORAGE_BUFFER,
            @sizeOf(shader.InstanceData) * @as(i32, @intCast(spaceship_list.items.len)),
            spaceship_list.items.ptr,
            gl.DYNAMIC_DRAW,
        );

        gl.drawElementsInstanced(
            gl.TRIANGLES,
            6,
            gl.UNSIGNED_INT,
            @ptrFromInt(0),
            @as(i32, @intCast(spaceship_list.items.len)),
        );

        // Bullets
        for (bullet_list.items, 0..) |*bullet, index| {
            const pos_x = bullet.mat[3][0];
            const pos_y = bullet.mat[3][1];
            var trans = zmath.translation(pos_x, pos_y, 0);
            const rot = zmath.rotationZ(@as(f32, @floatCast(glfw.getTime() * 10)) + @as(f32, @floatFromInt(index)));
            const scale = zmath.scalingV([_]f32{0.2} ** 4);
            trans = zmath.mul(scale, trans);
            bullet.mat = zmath.mul(rot, trans);
        }

        gl.bindVertexArray(bullet_vao);

        gl.bufferData(
            gl.SHADER_STORAGE_BUFFER,
            @sizeOf(shader.InstanceData) * @as(i32, @intCast(bullet_list.items.len)),
            bullet_list.items.ptr,
            gl.DYNAMIC_DRAW,
        );

        gl.drawArraysInstanced(
            gl.TRIANGLES,
            0,
            3,
            @as(i32, @intCast(bullet_list.items.len)),
        );

        gl.bindVertexArray(0);

        window.swapBuffers();
    }
}
