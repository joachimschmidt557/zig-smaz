const Build = @import("std").Build;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const smaz = b.addModule("smaz", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const main_tests = b.addTest(.{
        .name = "smaz",
        .root_module = smaz,
    });

    const run_main_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);

    const benchmark_module = b.createModule(.{
        .root_source_file = b.path("src/benchmark.zig"),
        .target = target,
        .optimize = optimize,
    });
    benchmark_module.addImport("smaz", smaz);

    const benchmark = b.addExecutable(.{
        .name = "benchmark",
        .root_module = benchmark_module,
    });

    const run_benchmark = b.addRunArtifact(benchmark);
    const run_benchmark_step = b.step("benchmark", "Run benchmarks");
    run_benchmark_step.dependOn(&run_benchmark.step);

}
