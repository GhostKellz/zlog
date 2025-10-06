const std = @import("std");

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Optional feature flags for modular builds
    const enable_json = b.option(bool, "json_format", "Enable JSON output format (default: true)") orelse true;
    const enable_async = b.option(bool, "async_io", "Enable async I/O support (default: false)") orelse false;
    const enable_file_targets = b.option(bool, "file_targets", "Enable file output and rotation (default: false)") orelse false;
    const enable_binary_format = b.option(bool, "binary_format", "Enable binary format support (default: false)") orelse false;
    const enable_aggregation = b.option(bool, "aggregation", "Enable advanced batching and filtering (default: false)") orelse false;
    const enable_network_targets = b.option(bool, "network_targets", "Enable network output targets (default: false)") orelse false;
    const enable_metrics = b.option(bool, "metrics", "Enable performance metrics (default: false)") orelse false;

    // This creates a module, which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Zig modules are the preferred way of making Zig code available to consumers.
    // addModule defines a module that we intend to make available for importing
    // to our consumers. We must give it a name because a Zig package can expose
    // multiple modules and consumers will need to be able to specify which
    // module they want to access.
    const options = b.addOptions();
    options.addOption(bool, "enable_json", enable_json);
    options.addOption(bool, "enable_async", enable_async);
    options.addOption(bool, "enable_file_targets", enable_file_targets);
    options.addOption(bool, "enable_binary_format", enable_binary_format);
    options.addOption(bool, "enable_aggregation", enable_aggregation);
    options.addOption(bool, "enable_network_targets", enable_network_targets);
    options.addOption(bool, "enable_metrics", enable_metrics);

    const options_module = options.createModule();

    const mod = b.addModule("zlog", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = if (enable_async) &[_]std.Build.Module.Import{
            .{ .name = "build_options", .module = options_module },
            .{ .name = "zsync", .module = b.dependency("zsync", .{}).module("zsync") },
        } else &[_]std.Build.Module.Import{
            .{ .name = "build_options", .module = options_module },
        },
    });

    // Here we define an executable. An executable needs to have a root module
    // which needs to expose a `main` function. While we could add a main function
    // to the module defined above, it's sometimes preferable to split business
    // logic and the CLI into two separate modules.
    //
    // If your goal is to create a Zig library for others to use, consider if
    // it might benefit from also exposing a CLI tool. A parser library for a
    // data serialization format could also bundle a CLI syntax checker, for example.
    //
    // If instead your goal is to create an executable, consider if users might
    // be interested in also being able to embed the core functionality of your
    // program in their own executable in order to avoid the overhead involved in
    // subprocessing your CLI tool.
    //
    // If neither case applies to you, feel free to delete the declaration you
    // don't need and to put everything under a single module.
    const exe = b.addExecutable(.{
        .name = "zlog",
        .root_module = b.createModule(.{
            // b.createModule defines a new module just like b.addModule but,
            // unlike b.addModule, it does not expose the module to consumers of
            // this package, which is why in this case we don't have to give it a name.
            .root_source_file = b.path("src/main.zig"),
            // Target and optimization levels must be explicitly wired in when
            // defining an executable or library (in the root module), and you
            // can also hardcode a specific target for an executable or library
            // definition if desireable (e.g. firmware for embedded devices).
            .target = target,
            .optimize = optimize,
            // List of modules available for import in source files part of the
            // root module.
            .imports = if (enable_async) &[_]std.Build.Module.Import{
                .{ .name = "build_options", .module = options_module },
                .{ .name = "zsync", .module = b.dependency("zsync", .{}).module("zsync") },
                .{ .name = "zlog", .module = mod },
            } else &[_]std.Build.Module.Import{
                .{ .name = "build_options", .module = options_module },
                .{ .name = "zlog", .module = mod },
            },
        }),
    });

    // This declares intent for the executable to be installed into the
    // install prefix when running `zig build` (i.e. when executing the default
    // step). By default the install prefix is `zig-out/` but can be overridden
    // by passing `--prefix` or `-p`.
    b.installArtifact(exe);

    // This creates a top level step. Top level steps have a name and can be
    // invoked by name when running `zig build` (e.g. `zig build run`).
    // This will evaluate the `run` step rather than the default step.
    // For a top level step to actually do something, it must depend on other
    // steps (e.g. a Run step, as we will see in a moment).
    const run_step = b.step("run", "Run the app");

    // This creates a RunArtifact step in the build graph. A RunArtifact step
    // invokes an executable compiled by Zig. Steps will only be executed by the
    // runner if invoked directly by the user (in the case of top level steps)
    // or if another step depends on it, so it's up to you to define when and
    // how this Run step will be executed. In our case we want to run it when
    // the user runs `zig build run`, so we create a dependency link.
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    // By making the run step depend on the default step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Creates an executable that will run `test` blocks from the provided module.
    // Here `mod` needs to define a target, which is why earlier we made sure to
    // set the releative field.
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    // A run step that will run the test executable.
    const run_mod_tests = b.addRunArtifact(mod_tests);

    // Creates an executable that will run `test` blocks from the executable's
    // root module. Note that test executables only test one module at a time,
    // hence why we have to create two separate ones.
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    // A run step that will run the second test executable.
    const run_exe_tests = b.addRunArtifact(exe_tests);

    // Extended test suite with comprehensive coverage
    const unit_tests = b.addTest(.{
        .name = "unit_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/unit/test_runner.zig"),
            .target = target,
            .optimize = optimize,
            .imports = if (enable_async) &[_]std.Build.Module.Import{
                .{ .name = "build_options", .module = options_module },
                .{ .name = "zsync", .module = b.dependency("zsync", .{}).module("zsync") },
                .{ .name = "zlog", .module = mod },
            } else &[_]std.Build.Module.Import{
                .{ .name = "build_options", .module = options_module },
                .{ .name = "zlog", .module = mod },
            },
        }),
    });

    const integration_tests = b.addTest(.{
        .name = "integration_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/test_runner.zig"),
            .target = target,
            .optimize = optimize,
            .imports = if (enable_async) &[_]std.Build.Module.Import{
                .{ .name = "build_options", .module = options_module },
                .{ .name = "zsync", .module = b.dependency("zsync", .{}).module("zsync") },
                .{ .name = "zlog", .module = mod },
            } else &[_]std.Build.Module.Import{
                .{ .name = "build_options", .module = options_module },
                .{ .name = "zlog", .module = mod },
            },
        }),
    });

    const benchmark_tests = b.addTest(.{
        .name = "benchmark_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/benchmarks/benchmark_suite.zig"),
            .target = target,
            .optimize = optimize,
            .imports = if (enable_async) &[_]std.Build.Module.Import{
                .{ .name = "build_options", .module = options_module },
                .{ .name = "zsync", .module = b.dependency("zsync", .{}).module("zsync") },
                .{ .name = "zlog", .module = mod },
            } else &[_]std.Build.Module.Import{
                .{ .name = "build_options", .module = options_module },
                .{ .name = "zlog", .module = mod },
            },
        }),
    });

    const platform_tests = b.addTest(.{
        .name = "platform_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/platform/platform_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = if (enable_async) &[_]std.Build.Module.Import{
                .{ .name = "build_options", .module = options_module },
                .{ .name = "zsync", .module = b.dependency("zsync", .{}).module("zsync") },
                .{ .name = "zlog", .module = mod },
            } else &[_]std.Build.Module.Import{
                .{ .name = "build_options", .module = options_module },
                .{ .name = "zlog", .module = mod },
            },
        }),
    });

    // Test execution steps
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const run_integration_tests = b.addRunArtifact(integration_tests);
    const run_benchmark_tests = b.addRunArtifact(benchmark_tests);
    const run_platform_tests = b.addRunArtifact(platform_tests);

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
    test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_integration_tests.step);
    test_step.dependOn(&run_platform_tests.step);

    // Individual test categories
    const unit_test_step = b.step("test:unit", "Run unit tests");
    unit_test_step.dependOn(&run_unit_tests.step);

    const integration_test_step = b.step("test:integration", "Run integration tests");
    integration_test_step.dependOn(&run_integration_tests.step);

    const benchmark_step = b.step("benchmark", "Run performance benchmarks");
    benchmark_step.dependOn(&run_benchmark_tests.step);

    const platform_test_step = b.step("test:platform", "Run platform-specific tests");
    platform_test_step.dependOn(&run_platform_tests.step);

    // Quick test target for rapid development (skips slow benchmarks)
    const quick_test_step = b.step("test:quick", "Run quick tests (skip benchmarks)");
    quick_test_step.dependOn(&run_mod_tests.step);
    quick_test_step.dependOn(&run_exe_tests.step);
    quick_test_step.dependOn(&run_unit_tests.step);
    quick_test_step.dependOn(&run_integration_tests.step);

    // Just like flags, top level steps are also listed in the `--help` menu.
    //
    // The Zig build system is entirely implemented in userland, which means
    // that it cannot hook into private compiler APIs. All compilation work
    // orchestrated by the build system will result in other Zig compiler
    // subcommands being invoked with the right flags defined. You can observe
    // these invocations when one fails (or you pass a flag to increase
    // verbosity) to validate assumptions and diagnose problems.
    //
    // Lastly, the Zig build system is relatively simple and self-contained,
    // and reading its source code will allow you to master it.
}
