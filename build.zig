const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const tests = b.option(bool, "Tests", "Build tests [default: false]") orelse false;
    const lib = boostLibraries(b, .{
        .target = target,
        .optimize = optimize,
    });

    lib.installHeadersDirectory(b.path("include"), "", .{});
    b.installArtifact(lib);

    if (tests) {
        buildTest(b, .{
            .path = "examples/adapt_callbacks.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "examples/adapt_method_calls.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "examples/adapt_nonblocking.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "examples/barrier.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "examples/join.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "examples/numa/topology.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "examples/future.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "examples/priority.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "examples/range_for.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "examples/simple.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "examples/ping_pong.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "examples/segmented_stack.cpp",
            .lib = lib,
        });
    }
}

fn buildTest(b: *std.Build, info: BuildInfo) void {
    const test_exe = b.addExecutable(.{
        .name = info.filename(),
        .optimize = info.lib.root_module.optimize.?,
        .target = info.lib.root_module.resolved_target.?,
    });
    for (info.lib.root_module.include_dirs.items) |include| {
        test_exe.root_module.include_dirs.append(b.allocator, include) catch {};
    }
    test_exe.addCSourceFile(.{
        .file = b.path(info.path),
        .flags = cxxFlags,
    });
    test_exe.linkLibrary(info.lib);
    test_exe.linkLibCpp();
    b.installArtifact(test_exe);

    const run_cmd = b.addRunArtifact(test_exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step(
        b.fmt("{s}", .{info.filename()}),
        b.fmt("Run the {s} test", .{info.filename()}),
    );
    run_step.dependOn(&run_cmd.step);
}

fn boostContext(b: *std.Build, attr: anytype) *std.Build.Step.Compile {
    const context_dep = b.dependency("context", .{
        .target = attr.@"0",
        .optimize = attr.@"1",
    });
    const context = context_dep.artifact("context");
    return context;
}

const src = &.{
    "src/algo/algorithm.cpp",
    "src/algo/round_robin.cpp",
    "src/algo/shared_work.cpp",
    "src/algo/work_stealing.cpp",
    "src/barrier.cpp",
    "src/condition_variable.cpp",
    "src/context.cpp",
    "src/fiber.cpp",
    "src/future.cpp",
    "src/mutex.cpp",
    "src/numa/algo/work_stealing.cpp",
    "src/properties.cpp",
    "src/recursive_mutex.cpp",
    "src/recursive_timed_mutex.cpp",
    "src/scheduler.cpp",
    "src/timed_mutex.cpp",
    "src/waker.cpp",
};
const cxxFlags: []const []const u8 = &.{
    "-Wall",
    "-Wextra",
    "-Wpedantic",
    "-Wshadow",
    "-std=c++20",
};

fn boostLibraries(b: *std.Build, options: struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
}) *std.Build.Step.Compile {
    const lib = b.addStaticLibrary(.{
        .name = "boost",
        .target = options.target,
        .optimize = options.optimize,
    });

    const boostlib = b.dependency("boost", .{
        .target = options.target,
        .optimize = options.optimize,
        .@"headers-only" = false,
        .filesystem = true,
        .context = true,
    });
    const boost = boostlib.artifact("boost");
    for (boost.root_module.include_dirs.items) |include| {
        lib.root_module.include_dirs.append(b.allocator, include) catch {};
    }

    lib.addIncludePath(b.path("include"));
    lib.addCSourceFiles(.{
        .files = src,
        .flags = cxxFlags,
    });
    lib.addCSourceFiles(.{
        .files = switch (lib.rootModuleTarget().os.tag) {
            .aix => &[_][]const u8{
                "src/numa/aix/pin_thread.cpp",
                "src/numa/aix/topology.cpp",
            },
            .windows => &[_][]const u8{
                "src/numa/windows/pin_thread.cpp",
                "src/numa/windows/topology.cpp",
            },
            .linux => &[_][]const u8{
                "src/numa/linux/pin_thread.cpp",
                "src/numa/linux/topology.cpp",
            },
            .freebsd => &[_][]const u8{
                "src/numa/freebsd/pin_thread.cpp",
                "src/numa/freebsd/topology.cpp",
            },
            .solaris => &[_][]const u8{
                "src/numa/solaris/pin_thread.cpp",
                "src/numa/solaris/topology.cpp",
            },
            else => &[_][]const u8{
                "src/numa/pin_thread.cpp",
                "src/numa/topology.cpp",
            },
        },
        .flags = cxxFlags,
    });
    lib.linkLibrary(boost);

    if (lib.rootModuleTarget().abi != .msvc)
        lib.linkLibCpp()
    else
        lib.linkLibC();
    return lib;
}

const BuildInfo = struct {
    lib: *std.Build.Step.Compile,
    path: []const u8,

    fn filename(self: BuildInfo) []const u8 {
        var split = std.mem.splitSequence(u8, std.fs.path.basename(self.path), ".");
        return split.first();
    }
};
