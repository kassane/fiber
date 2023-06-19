const std = @import("std");
const GitRepoStep = @import("GitRepoStep.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const tests = b.option(bool, "Tests", "Build tests [default: false]") orelse false;
    const boost = boostLibraries(b, target);
    const lib = b.addStaticLibrary(.{
        .name = "fiber",
        .target = target,
        .optimize = optimize,
    });
    switch (optimize) {
        .ReleaseSafe, .Debug => lib.bundle_compiler_rt = true,
        else => lib.strip = true,
    }
    const bc = boostContext(b, .{
        target,
        optimize,
    });
    for (bc.include_dirs.items) |include| {
        lib.include_dirs.append(include) catch @panic("fail imports");
    }
    for (boost.include_dirs.items) |include| {
        lib.include_dirs.append(include) catch @panic("fail imports");
    }
    lib.addIncludePath(.{ .path = "include" });
    lib.addCSourceFiles(src, cxxFlags);
    lib.addCSourceFiles(switch (target.getOsTag()) {
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
    }, cxxFlags);
    lib.linkLibrary(boost);
    lib.linkLibrary(bc);
    lib.linkLibCpp();
    lib.installHeadersDirectory("include", "");
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
        .optimize = info.lib.optimize,
        .target = info.lib.target,
    });
    for (info.lib.include_dirs.items) |include| {
        test_exe.include_dirs.append(include) catch {};
    }
    test_exe.addCSourceFile(.{ .file = .{ .path = info.path }, .flags = cxxFlags });
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

fn boostLibraries(b: *std.Build, target: std.zig.CrossTarget) *std.Build.Step.Compile {
    const lib = b.addStaticLibrary(.{
        .name = "boost",
        .target = target,
        .optimize = .ReleaseFast,
    });

    const boostCore = GitRepoStep.create(b, .{
        .url = "https://github.com/boostorg/core.git",
        .branch = "develop",
        .sha = "216999e552e7f73e63c7bcc88b8ce9c179bbdbe2",
        .fetch_enabled = true,
    });
    const boostAlg = GitRepoStep.create(b, .{
        .url = "https://github.com/boostorg/algorithm.git",
        .branch = "develop",
        .sha = "faac048d59948b1990c0a8772a050d8e47279343",
        .fetch_enabled = true,
    });
    const boostConfig = GitRepoStep.create(b, .{
        .url = "https://github.com/boostorg/config.git",
        .branch = "develop",
        .sha = "a1cf5d531405e62927b0257b5cbecc66a545b508",
        .fetch_enabled = true,
    });
    const boostAssert = GitRepoStep.create(b, .{
        .url = "https://github.com/boostorg/assert.git",
        .branch = "develop",
        .sha = "02256c84fd0cd58a139d9dc1b25b5019ca976ada",
        .fetch_enabled = true,
    });
    const boostTraits = GitRepoStep.create(b, .{
        .url = "https://github.com/boostorg/type_traits.git",
        .branch = "develop",
        .sha = "1ebd31e60eab91bd8bdc586d8df00586ecfb53e4",
        .fetch_enabled = true,
    });
    const boostRange = GitRepoStep.create(b, .{
        .url = "https://github.com/boostorg/range.git",
        .branch = "develop",
        .sha = "3920ef2e7ad91354224010ea27f9e0c8116ffe7d",
        .fetch_enabled = true,
    });
    const boostFunctional = GitRepoStep.create(b, .{
        .url = "https://github.com/boostorg/functional.git",
        .branch = "develop",
        .sha = "6a573e4b8333ee63ee62ce95558c3667348db233",
        .fetch_enabled = true,
    });
    const boostPreprocessor = GitRepoStep.create(b, .{
        .url = "https://github.com/boostorg/preprocessor.git",
        .branch = "develop",
        .sha = "667e87b3392db338a919cbe0213979713aca52e3",
        .fetch_enabled = true,
    });
    const boostHash = GitRepoStep.create(b, .{
        .url = "https://github.com/boostorg/container_hash.git",
        .branch = "develop",
        .sha = "226eb066e949adbf37b220e993d64ecefeeaae99",
        .fetch_enabled = true,
    });
    const boostDescribe = GitRepoStep.create(b, .{
        .url = "https://github.com/boostorg/describe.git",
        .branch = "develop",
        .sha = "a0eafb08100eb15a57b6dae6d270c0012a56aa21",
        .fetch_enabled = true,
    });
    const boostMpl = GitRepoStep.create(b, .{
        .url = "https://github.com/boostorg/mpl.git",
        .branch = "develop",
        .sha = "b440c45c2810acbddc917db057f2e5194da1a199",
        .fetch_enabled = true,
    });
    const boostIterator = GitRepoStep.create(b, .{
        .url = "https://github.com/boostorg/iterator.git",
        .branch = "develop",
        .sha = "80bb1ac9e401d0d679718e29bef2f2aaf0123fcb",
        .fetch_enabled = true,
    });
    const boostStaticAssert = GitRepoStep.create(b, .{
        .url = "https://github.com/boostorg/static_assert.git",
        .branch = "develop",
        .sha = "45eec41c293bc5cd36ec3ed83671f70bc1aadc9f",
        .fetch_enabled = true,
    });
    const boostMove = GitRepoStep.create(b, .{
        .url = "https://github.com/boostorg/move.git",
        .branch = "develop",
        .sha = "60f782350aa7c64e06ac6d2a6914ff6f6ff35ce1",
        .fetch_enabled = true,
    });
    const boostDetail = GitRepoStep.create(b, .{
        .url = "https://github.com/boostorg/detail.git",
        .branch = "develop",
        .sha = "b75c261492862448cdc5e1c0d5900203497122d6",
        .fetch_enabled = true,
    });
    const boostThrow = GitRepoStep.create(b, .{
        .url = "https://github.com/boostorg/throw_exception.git",
        .branch = "develop",
        .sha = "23dd41e920ecd91237500ac6428f7d392a7a875c",
        .fetch_enabled = true,
    });
    const boostPredef = GitRepoStep.create(b, .{
        .url = "https://github.com/boostorg/predef.git",
        .branch = "develop",
        .sha = "e508ed842c153b5dd4858e2cdafd58d2ede418d4",
        .fetch_enabled = true,
    });
    const boostCCheck = GitRepoStep.create(b, .{
        .url = "https://github.com/boostorg/concept_check.git",
        .branch = "develop",
        .sha = "37c9bddf0bdefaaae0ca5852c1a153d9fc43f278",
        .fetch_enabled = true,
    });
    const boostUtil = GitRepoStep.create(b, .{
        .url = "https://github.com/boostorg/utility.git",
        .branch = "develop",
        .sha = "eb721609af5ba8eea53e405ae6d901718866605f",
        .fetch_enabled = true,
    });
    const boostSystem = GitRepoStep.create(b, .{
        .url = "https://github.com/boostorg/system.git",
        .branch = "develop",
        .sha = "2e7e46a802d5b87f9af636ddbe3dbf224ca9c794",
        .fetch_enabled = true,
    });
    const boostBind = GitRepoStep.create(b, .{
        .url = "https://github.com/boostorg/bind.git",
        .branch = "develop",
        .sha = "55d037093bc715d3cf5682f6f84c3dc3456a3b97",
        .fetch_enabled = true,
    });
    const boostOptional = GitRepoStep.create(b, .{
        .url = "https://github.com/boostorg/optional.git",
        .branch = "develop",
        .sha = "2f8d019f523ed8dd098afe02c1617bfb3560165e",
        .fetch_enabled = true,
    });
    const boostSmartPtr = GitRepoStep.create(b, .{
        .url = "https://github.com/boostorg/smart_ptr.git",
        .branch = "develop",
        .sha = "13be03abf880cdb616d0597c38880f53f1b415b8",
        .fetch_enabled = true,
    });
    const boostIO = GitRepoStep.create(b, .{
        .url = "https://github.com/boostorg/io.git",
        .branch = "develop",
        .sha = "83e927f998e83a29be8fb033389110affe8787f5",
        .fetch_enabled = true,
    });
    const boostContainer = GitRepoStep.create(b, .{
        .url = "https://github.com/boostorg/container.git",
        .branch = "develop",
        .sha = "b8b089730ad7a9cd4a97f5796827177475462d0c",
        .fetch_enabled = true,
    });
    const boostFunction = GitRepoStep.create(b, .{
        .url = "https://github.com/boostorg/function.git",
        .branch = "develop",
        .sha = "4d3b477d71fff41bac83d21b5d52ad62ee1a3c5b",
        .fetch_enabled = true,
    });
    const boostFS = GitRepoStep.create(b, .{
        .url = "https://github.com/boostorg/filesystem.git",
        .branch = "develop",
        .sha = "e65ddb6ef21697970f7d1438f7a46c5233940059",
        .fetch_enabled = true,
    });
    const boostFormat = GitRepoStep.create(b, .{
        .url = "https://github.com/boostorg/format.git",
        .branch = "develop",
        .sha = "78ef371d2d90462671b90c3af407fae07820b193",
        .fetch_enabled = true,
    });
    const boostPool = GitRepoStep.create(b, .{
        .url = "https://github.com/boostorg/pool.git",
        .branch = "develop",
        .sha = "8ec1be1e82ba559744ecfa3c6ec13f71f9c175cc",
        .fetch_enabled = true,
    });
    const boostInteger = GitRepoStep.create(b, .{
        .url = "https://github.com/boostorg/integer.git",
        .branch = "develop",
        .sha = "28ba36fd3ab9e02736508398670995fe286a05fe",
        .fetch_enabled = true,
    });
    const boostWinApi = GitRepoStep.create(b, .{
        .url = "https://github.com/boostorg/winapi.git",
        .branch = "develop",
        .sha = "02b4161832e7ca5f78e996967a793120e36b22dc",
        .fetch_enabled = true,
    });

    lib.defineCMacro("BOOST_FILESYSTEM_SINGLE_THREADED", null);
    lib.addCSourceFiles(&.{
        b.pathJoin(&.{ boostFS.path, "src/codecvt_error_category.cpp" }),
        b.pathJoin(&.{ boostFS.path, "src/directory.cpp" }),
        b.pathJoin(&.{ boostFS.path, "src/exception.cpp" }),
        b.pathJoin(&.{ boostFS.path, "src/operations.cpp" }),
        b.pathJoin(&.{ boostFS.path, "src/path.cpp" }),
        b.pathJoin(&.{ boostFS.path, "src/path_traits.cpp" }),
        b.pathJoin(&.{ boostFS.path, "src/portability.cpp" }),
        b.pathJoin(&.{ boostFS.path, "src/unique_path.cpp" }),
        b.pathJoin(&.{ boostFS.path, "src/utf8_codecvt_facet.cpp" }),
        b.pathJoin(&.{ boostFS.path, "src/windows_file_codecvt.cpp" }),
    }, cxxFlags);
    if (target.getAbi() != .msvc)
        lib.linkLibCpp()
    else
        lib.linkLibC();

    lib.addIncludePath(.{ .path = b.pathJoin(&.{ boostCore.path, "include/" }) });
    lib.addIncludePath(.{ .path = b.pathJoin(&.{ boostAlg.path, "include/" }) });
    lib.addIncludePath(.{ .path = b.pathJoin(&.{ boostConfig.path, "include/" }) });
    lib.addIncludePath(.{ .path = b.pathJoin(&.{ boostAssert.path, "include/" }) });
    lib.addIncludePath(.{ .path = b.pathJoin(&.{ boostFunctional.path, "include/" }) });
    lib.addIncludePath(.{ .path = b.pathJoin(&.{ boostTraits.path, "include/" }) });
    lib.addIncludePath(.{ .path = b.pathJoin(&.{ boostRange.path, "include/" }) });
    lib.addIncludePath(.{ .path = b.pathJoin(&.{ boostPreprocessor.path, "include/" }) });
    lib.addIncludePath(.{ .path = b.pathJoin(&.{ boostHash.path, "include/" }) });
    lib.addIncludePath(.{ .path = b.pathJoin(&.{ boostStaticAssert.path, "include/" }) });
    lib.addIncludePath(.{ .path = b.pathJoin(&.{ boostMove.path, "include/" }) });
    lib.addIncludePath(.{ .path = b.pathJoin(&.{ boostDetail.path, "include/" }) });
    lib.addIncludePath(.{ .path = b.pathJoin(&.{ boostThrow.path, "include/" }) });
    lib.addIncludePath(.{ .path = b.pathJoin(&.{ boostPredef.path, "include/" }) });
    lib.addIncludePath(.{ .path = b.pathJoin(&.{ boostCCheck.path, "include/" }) });
    lib.addIncludePath(.{ .path = b.pathJoin(&.{ boostIterator.path, "include/" }) });
    lib.addIncludePath(.{ .path = b.pathJoin(&.{ boostMpl.path, "include/" }) });
    lib.addIncludePath(.{ .path = b.pathJoin(&.{ boostUtil.path, "include/" }) });
    lib.addIncludePath(.{ .path = b.pathJoin(&.{ boostOptional.path, "include/" }) });
    lib.addIncludePath(.{ .path = b.pathJoin(&.{ boostSystem.path, "include/" }) });
    lib.addIncludePath(.{ .path = b.pathJoin(&.{ boostBind.path, "include/" }) });
    lib.addIncludePath(.{ .path = b.pathJoin(&.{ boostSmartPtr.path, "include/" }) });
    lib.addIncludePath(.{ .path = b.pathJoin(&.{ boostContainer.path, "include/" }) });
    lib.addIncludePath(.{ .path = b.pathJoin(&.{ boostFunction.path, "include/" }) });
    lib.addIncludePath(.{ .path = b.pathJoin(&.{ boostFS.path, "include/" }) });
    lib.addIncludePath(.{ .path = b.pathJoin(&.{ boostFS.path, "src/" }) });
    lib.addIncludePath(.{ .path = b.pathJoin(&.{ boostIO.path, "include/" }) });
    lib.addIncludePath(.{ .path = b.pathJoin(&.{ boostFormat.path, "include/" }) });
    lib.addIncludePath(.{ .path = b.pathJoin(&.{ boostPool.path, "include/" }) });
    lib.addIncludePath(.{ .path = b.pathJoin(&.{ boostInteger.path, "include/" }) });
    lib.addIncludePath(.{ .path = b.pathJoin(&.{ boostWinApi.path, "include/" }) });

    lib.step.dependOn(&boostCore.step);
    boostCore.step.dependOn(&boostTraits.step);
    boostCore.step.dependOn(&boostAssert.step);
    boostCore.step.dependOn(&boostAlg.step);
    boostCore.step.dependOn(&boostConfig.step);
    boostCore.step.dependOn(&boostFunctional.step);
    boostCore.step.dependOn(&boostRange.step);
    boostCore.step.dependOn(&boostPreprocessor.step);
    boostCore.step.dependOn(&boostHash.step);
    boostCore.step.dependOn(&boostDescribe.step);
    boostCore.step.dependOn(&boostMpl.step);
    boostCore.step.dependOn(&boostIterator.step);
    boostCore.step.dependOn(&boostStaticAssert.step);
    boostCore.step.dependOn(&boostMove.step);
    boostCore.step.dependOn(&boostDetail.step);
    boostCore.step.dependOn(&boostThrow.step);
    boostCore.step.dependOn(&boostPredef.step);
    boostCore.step.dependOn(&boostCCheck.step);
    boostCore.step.dependOn(&boostUtil.step);
    boostCore.step.dependOn(&boostSystem.step);
    boostCore.step.dependOn(&boostBind.step);
    boostCore.step.dependOn(&boostOptional.step);
    boostCore.step.dependOn(&boostSmartPtr.step);
    boostCore.step.dependOn(&boostIO.step);
    boostCore.step.dependOn(&boostContainer.step);
    boostCore.step.dependOn(&boostFunction.step);
    boostCore.step.dependOn(&boostFS.step);
    boostCore.step.dependOn(&boostFormat.step);
    boostCore.step.dependOn(&boostPool.step);
    boostCore.step.dependOn(&boostInteger.step);
    boostCore.step.dependOn(&boostWinApi.step);

    return lib;
}

const BuildInfo = struct {
    lib: *std.Build.CompileStep,
    path: []const u8,

    fn filename(self: BuildInfo) []const u8 {
        var split = std.mem.splitSequence(u8, std.fs.path.basename(self.path), ".");
        return split.first();
    }
};
