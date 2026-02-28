const std = @import("std");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const zmath = @import("zmath");
const math = std.math;
const shader = @import("shader.zig");
const file = @import("file.zig");

const gl = zopengl.bindings;
const gl_version_major: u16 = 4;
const gl_version_minor: u16 = 0;

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
    glfw.swapInterval(1);

    try zopengl.loadCoreProfile(glfw.getProcAddress, gl_version_major, gl_version_minor);

    // ── Shader setup ────────────────────────────────────────────────
    const vertex_shader: []u8 = try file.read_file("res/shaders/in-world.vert");
    const fragment_shader: []u8 = try file.read_file("res/shaders/in-world.frag");

    const program = try shader.createShaderProgram(vertex_shader, fragment_shader);
    defer gl.deleteProgram(program);

    // ── Triangle data ───────────────────────────────────────────────
    const Vertex = struct {
        x: f32,
        y: f32,
        r: f32,
        g: f32,
        b: f32,
    };

    const vertices = [_]Vertex{
        .{ .x = 0.5, .y = 0.5, .r = 0.0, .g = 0.0, .b = 1.0 },
        .{ .x = 0.5, .y = -0.5, .r = 0.0, .g = 1.0, .b = 0.0 },
        .{ .x = -0.5, .y = -0.5, .r = 1.0, .g = 0.0, .b = 0.0 },
        .{ .x = -0.5, .y = 0.5, .r = 1.0, .g = 1.0, .b = 0.0 },
    };

    const indices = [_]i32{ 0, 1, 3, 1, 2, 3 };

    var vao: zopengl.wrapper.Uint = undefined; // header
    var vbo: zopengl.wrapper.Uint = undefined; // body

    var ebo: zopengl.wrapper.Uint = undefined;

    gl.genVertexArrays(1, @ptrCast(&vao));
    defer gl.deleteVertexArrays(1, @ptrCast(&vao));

    gl.genBuffers(1, @ptrCast(&vbo));
    defer gl.deleteBuffers(1, @ptrCast(&vbo));

    gl.genBuffers(1, @ptrCast(&ebo));
    defer gl.deleteBuffers(1, @ptrCast(&ebo));

    gl.bindVertexArray(vao);

    gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
    gl.bufferData(gl.ARRAY_BUFFER, @sizeOf(@TypeOf(vertices)), &vertices, gl.STATIC_DRAW);

    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo);
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, @sizeOf(@TypeOf(indices)), &indices, gl.STATIC_DRAW);

    // position (location 0)
    gl.vertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), @ptrFromInt(0));
    gl.enableVertexAttribArray(0);

    // color (location 1)
    gl.vertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), @ptrFromInt(2 * @sizeOf(f32)));
    gl.enableVertexAttribArray(1);

    gl.bindVertexArray(0); // optional – good practice
    // gl.polygonMode(gl.FRONT_AND_BACK, gl.LINE);
    while (!window.shouldClose()) {
        glfw.pollEvents();

        gl.clearColor(0.12, 0.24, 0.36, 1.0);
        gl.clear(gl.COLOR_BUFFER_BIT);

        gl.useProgram(program);

        const projection_loc = gl.getUniformLocation(program, @ptrCast("projection"));
        const view_loc = gl.getUniformLocation(program, @ptrCast("view"));
        const model_loc = gl.getUniformLocation(program, @ptrCast("model"));

        // var trans = math.identity();
        // const scale = math.scalingV([_]f32{0.5} ** 4);

        // trans = math.mul(trans, scale);
        // trans = math.mul(trans, math.rotationZ(@floatCast(glfw.getTime())));

        // gl.uniformMatrix4fv(transform_loc, 1, gl.FALSE, @ptrCast(&trans));

        var model = zmath.identity();
        var view = zmath.identity();
        var projection = zmath.identity();

        model = zmath.mul(model, zmath.rotationZ(@floatCast(0)));
        view = zmath.mul(view, zmath.translation(0, 0, -10));
        projection = zmath.mul(projection, zmath.perspectiveFovRhGl(math.degreesToRadians(45), aspect_ratio, 0.1, 1000));

        gl.uniformMatrix4fv(projection_loc, 1, gl.FALSE, @ptrCast(&projection));
        gl.uniformMatrix4fv(view_loc, 1, gl.FALSE, @ptrCast(&view));
        gl.uniformMatrix4fv(model_loc, 1, gl.FALSE, @ptrCast(&model));

        gl.bindVertexArray(vao);
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo);
        gl.drawElements(gl.TRIANGLES, 6, gl.UNSIGNED_INT, @ptrFromInt(0));
        gl.bindVertexArray(0);

        window.swapBuffers();
    }
}
