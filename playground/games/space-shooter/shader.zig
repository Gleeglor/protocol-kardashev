const std = @import("std");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");

fn compileShader(source: []u8, kind: zopengl.wrapper.Enum) !zopengl.wrapper.Uint {
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

pub fn createShaderProgram(vertex_shader_src: []u8, fragment_shader_src: []u8) !zopengl.wrapper.Uint {
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
