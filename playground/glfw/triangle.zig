const std = @import("std");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");

const gl_version_major: u16 = 4;
const gl_version_minor: u16 = 0;

const vertex_shader_src =
    \\#version 400 core
    \\layout(location = 0) in vec2 aPos;
    \\layout(location = 1) in vec3 aColor;
    \\out vec3 vColor;
    \\void main() {
    \\    gl_Position = vec4(aPos, 0.0, 1.0);
    \\    vColor = aColor;
    \\}
;

const fragment_shader_src =
    \\#version 400 core
    \\in vec3 vColor;
    \\out vec4 FragColor;
    \\void main() {
    \\    FragColor = vec4(vColor, 1.0);
    \\}
;

fn compileShader(source: [:0]const u8, kind: zopengl.wrapper.Enum) !zopengl.wrapper.Uint {
    const gl = zopengl.bindings;
    const id = gl.createShader(kind);
    if (id == 0) return error.CreateShaderFailed;

    gl.shaderSource(id, 1, @ptrCast(&source.ptr), null);
    gl.compileShader(id);

    var success: c_int = 0;
    gl.getShaderiv(id, gl.COMPILE_STATUS, &success);
    if (success == 0) {
        var info_log: [512]u8 = undefined;
        var len: c_int = 0;
        gl.getShaderInfoLog(id, 512, &len, &info_log);
        std.debug.print("Shader compile error:\n{s}\n", .{info_log[0..@intCast(len)]});
        gl.deleteShader(id);
        return error.CompileFailed;
    }
    return id;
}

fn createShaderProgram() !zopengl.wrapper.Uint {
    const gl = zopengl.bindings;

    const vs = try compileShader(vertex_shader_src, gl.VERTEX_SHADER);
    defer gl.deleteShader(vs);

    const fs = try compileShader(fragment_shader_src, gl.FRAGMENT_SHADER);
    defer gl.deleteShader(fs);

    const prog = gl.createProgram();
    if (prog == 0) return error.CreateProgramFailed;

    gl.attachShader(prog, vs);
    gl.attachShader(prog, fs);
    gl.linkProgram(prog);

    var success: c_int = 0;
    gl.getProgramiv(prog, gl.LINK_STATUS, &success);
    if (success == 0) {
        var info_log: [512]u8 = undefined;
        var len: c_int = 0;
        gl.getProgramInfoLog(prog, 512, &len, &info_log);
        std.debug.print("Program link error:\n{s}\n", .{info_log[0..@intCast(len)]});
        gl.deleteProgram(prog);
        return error.LinkFailed;
    }

    return prog;
}

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

    glfw.makeContextCurrent(window);
    glfw.swapInterval(1);

    try zopengl.loadCoreProfile(glfw.getProcAddress, gl_version_major, gl_version_minor);
    const gl = zopengl.bindings;

    // ── Shader setup ────────────────────────────────────────────────
    const program = try createShaderProgram();
    defer gl.deleteProgram(program);

    // ── Triangle data ───────────────────────────────────────────────
    const vertices = [_]f32{
        //   x      y       r     g     b
        -0.5, -0.5, 1.0, 0.0, 0.0,
        0.5,  -0.5, 0.0, 1.0, 0.0,
        0.0,  0.5,  0.0, 0.0, 1.0,
    };

    var vao: zopengl.wrapper.Uint = undefined;
    var vbo: zopengl.wrapper.Uint = undefined;

    gl.genVertexArrays(1, @ptrCast(&vao));
    defer gl.deleteVertexArrays(1, @ptrCast(&vao));

    gl.genBuffers(1, @ptrCast(&vbo));
    defer gl.deleteBuffers(1, @ptrCast(&vbo));

    gl.bindVertexArray(vao);

    gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
    gl.bufferData(gl.ARRAY_BUFFER, @sizeOf(@TypeOf(vertices)), &vertices, gl.STATIC_DRAW);

    // position (location 0)
    gl.vertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, 5 * @sizeOf(f32), @ptrFromInt(0));
    gl.enableVertexAttribArray(0);

    // color (location 1)
    gl.vertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, 5 * @sizeOf(f32), @ptrFromInt(2 * @sizeOf(f32)));
    gl.enableVertexAttribArray(1);

    gl.bindVertexArray(0); // optional – good practice

    while (!window.shouldClose()) {
        glfw.pollEvents();

        gl.clearColor(0.12, 0.24, 0.36, 1.0);
        gl.clear(gl.COLOR_BUFFER_BIT);

        gl.useProgram(program);
        gl.bindVertexArray(vao);
        gl.drawArrays(gl.TRIANGLES, 0, 3);
        gl.bindVertexArray(0);

        window.swapBuffers();
    }
}
