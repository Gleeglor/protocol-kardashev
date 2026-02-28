const std = @import("std");

const BuildOptions = struct {
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
};

const ScriptOptions = struct {
    build_options: BuildOptions,
    name: []const u8,
    root_file: []const u8,
    dependencies: []const DependencySetup = &.{},
};

pub const DependencySetup = *const fn (BuildOptions, *std.Build.Step.Compile) void;

fn createScript(
    options: ScriptOptions,
) *std.Build.Step.Compile {
    const b = options.build_options.b;

    const exe = b.addExecutable(.{
        .name = options.name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(options.root_file),
            .target = options.build_options.target,
            .optimize = options.build_options.optimize,
            .imports = &.{},
        }),
    });

    for (options.dependencies) |setup| {
        setup(options.build_options, exe);
    }

    b.installArtifact(exe);

    const run_step = b.step(options.name, "Run playground script");
    const run_cmd = b.addRunArtifact(exe);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step(
        b.fmt("test-{s}", .{options.name}),
        b.fmt("Run test for {s}", .{options.name}),
    );

    test_step.dependOn(&run_exe_tests.step);

    return exe;
}

// fn addGLFW_ZIG(options: BuildOptions, exe: *std.Build.Step.Compile) void {
//     const dep = options.b.dependency("glfw_zig", .{
//         .target = options.target,
//         .optimize = options.optimize,
//     });
//     exe.linkLibrary(dep.artifact("glfw"));
//     // exe.root_module.addImport("glfw_zig", dep.module("glfw_zig"));
// }
fn addZMath(options: BuildOptions, exe: *std.Build.Step.Compile) void {
    const zmath = options.b.dependency("zmath", .{
        .target = options.target,
        .optimize = options.optimize,
    });
    exe.root_module.addImport("zmath", zmath.module("root"));
}

fn addZGFLW(options: BuildOptions, exe: *std.Build.Step.Compile) void {
    const zglfw = options.b.dependency("zglfw", .{
        .target = options.target,
        .optimize = options.optimize,
    });
    exe.root_module.addImport("zglfw", zglfw.module("root"));
    exe.linkLibrary(zglfw.artifact("glfw"));
}

fn addZOpenGL(options: BuildOptions, exe: *std.Build.Step.Compile) void {
    const zopengl = options.b.dependency("zopengl", .{});
    exe.root_module.addImport("zopengl", zopengl.module("root"));
}

// fn addGL(options: BuildOptions, exe: *std.Build.Step.Compile) void {
//     const gl_bindings = @import("zigglgen").generateBindingsModule(options.b, .{
//         .api = .gl,
//         .version = .@"4.1",
//         .profile = .core,
//         .extensions = &.{ .ARB_clip_control, .NV_scissor_exclusive },
//     });

//     // Import the generated module.
//     exe.root_module.addImport("gl", gl_bindings);
// }

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const defaultOptions = BuildOptions{ .b = b, .target = target, .optimize = optimize };

    _ = createScript(.{
        .build_options = defaultOptions,
        .name = "hello-world",
        .root_file = "playground/hello-world/main.zig",
    });

    _ = createScript(.{
        .build_options = defaultOptions,
        .name = "glfw-window",
        .root_file = "playground/glfw/window.zig",
        .dependencies = &[_]DependencySetup{ addZOpenGL, addZGFLW },
    });

    _ = createScript(.{
        .build_options = defaultOptions,
        .name = "glfw-triangle",
        .root_file = "playground/glfw/triangle.zig",
        .dependencies = &[_]DependencySetup{ addZOpenGL, addZGFLW },
    });

    _ = createScript(.{
        .build_options = defaultOptions,
        .name = "rotating-triangle",
        .root_file = "playground/glfw/rotating-triangle.zig",
        .dependencies = &[_]DependencySetup{ addZOpenGL, addZGFLW, addZMath },
    });

    _ = createScript(.{
        .build_options = defaultOptions,
        .name = "in-world",
        .root_file = "playground/glfw/in-world.zig",
        .dependencies = &[_]DependencySetup{ addZOpenGL, addZGFLW, addZMath },
    });

    _ = createScript(.{
        .build_options = defaultOptions,
        .name = "space-shooter",
        .root_file = "playground/games/space-shooter/main.zig",
        .dependencies = &[_]DependencySetup{ addZOpenGL, addZGFLW, addZMath },
    });
}
