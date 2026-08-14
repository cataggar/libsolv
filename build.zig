const std = @import("std");

// Public headers installed for each library, mirroring src/CMakeLists.txt
// and ext/CMakeLists.txt so that consumers see the same public API surface
// as the CMake build.
const solv_public_headers = [_][]const u8{
    "bitmap.h",      "evr.h",        "hash.h",         "policy.h",
    "poolarch.h",    "poolvendor.h", "pool.h",         "poolid.h",
    "pooltypes.h",   "queue.h",      "solvable.h",     "solver.h",
    "solverdebug.h", "repo.h",       "repodata.h",     "repo_solv.h",
    "repo_write.h",  "util.h",       "selection.h",    "strpool.h",
    "dirpool.h",     "knownid.h",    "transaction.h",  "rules.h",
    "problems.h",    "chksum.h",     "dataiterator.h",
};

const solvext_public_headers = [_][]const u8{
    "tools_util.h", "solv_xfopen.h", "testcase.h",
};

// Core libsolv sources, matching libsolv_SRCS in src/CMakeLists.txt
// (excluding the optional conda.c / apk.c, which are added conditionally).
const solv_base_sources = [_][]const u8{
    "bitmap.c",        "poolarch.c",       "poolvendor.c",       "poolid.c",
    "pooldep.c",       "poollang.c",       "poolwhatprovides.c", "pool.c",
    "strpool.c",       "dirpool.c",        "solver.c",           "solverdebug.c",
    "repo_solv.c",     "repo_write.c",     "evr.c",              "queue.c",
    "repo.c",          "repodata.c",       "repopage.c",         "util.c",
    "policy.c",        "solvable.c",       "transaction.c",      "order.c",
    "rules.c",         "problems.c",       "linkedpkg.c",        "cplxdeps.c",
    "chksum.c",        "chksum_impl.c",    "md5.c",              "sha1.c",
    "sha2.c",          "solvversion.c",    "selection.c",        "fileprovides.c",
    "diskusage.c",     "suse.c",           "solver_util.c",      "cleandeps.c",
    "userinstalled.c", "filelistfilter.c", "decision.c",
};

// Base libsolvext sources that don't depend on any optional repo format,
// matching the unconditional part of libsolvext_SRCS in ext/CMakeLists.txt.
const solvext_base_sources = [_][]const u8{
    "solv_xfopen.c", "testcase.c", "repo_testcase.c",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const t = target.result;

    const shared = b.option(bool, "shared", "Build shared libraries instead of static ones") orelse false;
    const linkage: std.builtin.LinkMode = if (shared) .dynamic else .static;

    const enable_conda = b.option(bool, "conda", "Enable conda dependency support (src/conda.c)") orelse false;
    const multi_semantics = b.option(bool, "multi-semantics", "Enable support for multiple distribution types (src/apk.c)") orelse enable_conda;
    const enable_debian = b.option(bool, "debian", "Build with Debian EVR/dependency semantics and repository support") orelse false;

    const with_ext = b.option(bool, "ext", "Build libsolvext (compression + testcase helpers)") orelse true;
    const ext_zlib = b.option(bool, "zlib", "libsolvext: enable zlib (.gz) compression support") orelse true;
    const ext_lzma = b.option(bool, "lzma", "libsolvext: enable lzma/xz compression support") orelse enable_debian;
    const ext_bzip2 = b.option(bool, "bzip2", "libsolvext: enable bzip2 compression support") orelse false;
    const ext_zstd = b.option(bool, "zstd", "libsolvext: enable zstd compression support") orelse false;

    const with_tools = b.option(bool, "tools", "Build the dumpsolv command-line tool") orelse false;

    // A handful of libc feature checks that CMake performs with
    // CHECK_FUNCTION_EXISTS / TEST_BIG_ENDIAN. All of these are optional
    // performance/feature toggles with safe fallbacks in the C code, so it's
    // fine to be conservative here.
    const words_bigendian = t.cpu.arch.endian() == .big;
    const have_strchrnul = t.os.tag == .linux; // both glibc and musl provide it
    const have_fopencookie = t.os.tag == .linux and t.abi == .gnu;
    const have_funopen = switch (t.os.tag) {
        .macos, .ios, .tvos, .watchos, .visionos, .freebsd, .openbsd, .netbsd, .dragonfly => true,
        else => false,
    };

    // Equivalent of CMake's CONFIGURE_FILE(src/solvversion.h.in src/solvversion.h),
    // using Zig's built-in CMake-style config header renderer.
    const version_h = b.addConfigHeader(.{
        .style = .{ .cmake = b.path("src/solvversion.h.in") },
        .include_path = "solvversion.h",
    }, .{
        .VERSION = "0.7.39",
        .LIBSOLV_MAJOR = 0,
        .LIBSOLV_MINOR = 7,
        .LIBSOLV_PATCH = 39,
        .LIBSOLV_FEATURE_LINKED_PKGS = false,
        .LIBSOLV_FEATURE_COMPLEX_DEPS = false,
        .LIBSOLV_FEATURE_MULTI_SEMANTICS = multi_semantics,
        .LIBSOLV_FEATURE_CONDA = enable_conda,
        .LIBSOLVEXT_FEATURE_RPMPKG = false,
        .LIBSOLVEXT_FEATURE_RPMDB = false,
        .LIBSOLVEXT_FEATURE_RPMDB_BYRPMHEADER = false,
        .LIBSOLVEXT_FEATURE_PUBKEY = false,
        .LIBSOLVEXT_FEATURE_RPMMD = false,
        .LIBSOLVEXT_FEATURE_SUSEREPO = false,
        .LIBSOLVEXT_FEATURE_COMPS = false,
        .LIBSOLVEXT_FEATURE_HELIXREPO = false,
        .LIBSOLVEXT_FEATURE_DEBIAN = with_ext and enable_debian,
        .LIBSOLVEXT_FEATURE_ARCHREPO = false,
        .LIBSOLVEXT_FEATURE_HAIKU = false,
        .LIBSOLVEXT_FEATURE_APPDATA = false,
        .LIBSOLVEXT_FEATURE_APK = false,
        .LIBSOLVEXT_FEATURE_ZLIB_COMPRESSION = with_ext and ext_zlib,
        .LIBSOLVEXT_FEATURE_LZMA_COMPRESSION = with_ext and ext_lzma,
        .LIBSOLVEXT_FEATURE_BZIP2_COMPRESSION = with_ext and ext_bzip2,
        .LIBSOLVEXT_FEATURE_ZSTD_COMPRESSION = with_ext and ext_zstd,
        .LIBSOLVEXT_FEATURE_ZCHUNK_COMPRESSION = false,
    });

    // ---------------------------------------------------------------
    // libsolv (core)
    // ---------------------------------------------------------------
    const solv_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    solv_mod.addConfigHeader(version_h);
    solv_mod.addIncludePath(b.path("src"));

    var solv_flags: std.ArrayList([]const u8) = .empty;
    solv_flags.append(b.allocator, "-DLIBSOLV_INTERNAL=1") catch @panic("OOM");
    solv_flags.append(b.allocator, "-D_FILE_OFFSET_BITS=64") catch @panic("OOM");
    if (have_strchrnul) solv_flags.append(b.allocator, "-DHAVE_STRCHRNUL=1") catch @panic("OOM");
    if (words_bigendian) solv_flags.append(b.allocator, "-DWORDS_BIGENDIAN=1") catch @panic("OOM");
    if (enable_conda) solv_flags.append(b.allocator, "-DENABLE_CONDA=1") catch @panic("OOM");
    if (multi_semantics) solv_flags.append(b.allocator, "-DMULTI_SEMANTICS=1") catch @panic("OOM");
    if (enable_debian) solv_flags.append(b.allocator, "-DDEBIAN=1") catch @panic("OOM");

    var solv_srcs: std.ArrayList([]const u8) = .empty;
    solv_srcs.appendSlice(b.allocator, &solv_base_sources) catch @panic("OOM");
    if (enable_conda) solv_srcs.append(b.allocator, "conda.c") catch @panic("OOM");
    if (multi_semantics) solv_srcs.append(b.allocator, "apk.c") catch @panic("OOM");

    solv_mod.addCSourceFiles(.{
        .root = b.path("src"),
        .files = solv_srcs.items,
        .flags = solv_flags.items,
    });

    const solv_lib = b.addLibrary(.{
        .name = "solv",
        .linkage = linkage,
        .root_module = solv_mod,
    });
    for (solv_public_headers) |h| {
        solv_lib.installHeader(b.path(b.fmt("src/{s}", .{h})), b.fmt("solv/{s}", .{h}));
    }
    if (enable_conda) solv_lib.installHeader(b.path("src/conda.h"), "solv/conda.h");
    solv_lib.installHeader(version_h.getOutputFile(), "solv/solvversion.h");
    b.installArtifact(solv_lib);

    // ---------------------------------------------------------------
    // libsolvext (optional): compression backends + testcase helpers
    // ---------------------------------------------------------------
    var ext_lib: ?*std.Build.Step.Compile = null;
    if (with_ext) {
        const ext_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        ext_mod.addConfigHeader(version_h);
        ext_mod.addIncludePath(b.path("src"));
        ext_mod.addIncludePath(b.path("ext"));
        ext_mod.linkLibrary(solv_lib);

        var ext_flags: std.ArrayList([]const u8) = .empty;
        ext_flags.append(b.allocator, "-D_FILE_OFFSET_BITS=64") catch @panic("OOM");
        if (have_fopencookie) ext_flags.append(b.allocator, "-DHAVE_FOPENCOOKIE=1") catch @panic("OOM");
        if (have_funopen) ext_flags.append(b.allocator, "-DHAVE_FUNOPEN=1") catch @panic("OOM");
        if (ext_zlib) ext_flags.append(b.allocator, "-DENABLE_ZLIB_COMPRESSION=1") catch @panic("OOM");
        if (ext_lzma) ext_flags.append(b.allocator, "-DENABLE_LZMA_COMPRESSION=1") catch @panic("OOM");
        if (ext_bzip2) ext_flags.append(b.allocator, "-DENABLE_BZIP2_COMPRESSION=1") catch @panic("OOM");
        if (ext_zstd) ext_flags.append(b.allocator, "-DENABLE_ZSTD_COMPRESSION=1") catch @panic("OOM");
        if (enable_debian) ext_flags.append(b.allocator, "-DENABLE_DEBIAN=1") catch @panic("OOM");

        var ext_srcs: std.ArrayList([]const u8) = .empty;
        ext_srcs.appendSlice(b.allocator, &solvext_base_sources) catch @panic("OOM");
        if (enable_debian) ext_srcs.append(b.allocator, "repo_deb.c") catch @panic("OOM");
        ext_mod.addCSourceFiles(.{
            .root = b.path("ext"),
            .files = ext_srcs.items,
            .flags = ext_flags.items,
        });

        if (ext_zlib) ext_mod.linkSystemLibrary("z", .{});
        if (ext_lzma) ext_mod.linkSystemLibrary("lzma", .{});
        if (ext_bzip2) ext_mod.linkSystemLibrary("bz2", .{});
        if (ext_zstd) ext_mod.linkSystemLibrary("zstd", .{});

        ext_lib = b.addLibrary(.{
            .name = "solvext",
            .linkage = linkage,
            .root_module = ext_mod,
        });
        for (solvext_public_headers) |h| {
            ext_lib.?.installHeader(b.path(b.fmt("ext/{s}", .{h})), b.fmt("solv/{s}", .{h}));
        }
        if (enable_debian) ext_lib.?.installHeader(b.path("ext/repo_deb.h"), "solv/repo_deb.h");
        b.installArtifact(ext_lib.?);
    }

    const test_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addConfigHeader(version_h);
    test_mod.addIncludePath(b.path("src"));
    test_mod.addIncludePath(b.path("ext"));
    test_mod.linkLibrary(solv_lib);

    var test_flags: std.ArrayList([]const u8) = .empty;
    test_flags.append(b.allocator, "-D_FILE_OFFSET_BITS=64") catch @panic("OOM");
    if (enable_debian) test_flags.append(b.allocator, "-DDEBIAN=1") catch @panic("OOM");
    if (with_ext and enable_debian) test_flags.append(b.allocator, "-DENABLE_DEBIAN=1") catch @panic("OOM");
    test_mod.addCSourceFiles(.{
        .root = b.path("test/zig"),
        .files = &.{"debian.c"},
        .flags = test_flags.items,
    });
    if (with_ext and enable_debian) {
        var loader_test_flags: std.ArrayList([]const u8) = .empty;
        loader_test_flags.append(b.allocator, "-D_FILE_OFFSET_BITS=64") catch @panic("OOM");
        loader_test_flags.append(b.allocator, "-DENABLE_DEBIAN=1") catch @panic("OOM");
        if (ext_zlib) loader_test_flags.append(b.allocator, "-DENABLE_ZLIB_COMPRESSION=1") catch @panic("OOM");
        if (ext_lzma) loader_test_flags.append(b.allocator, "-DENABLE_LZMA_COMPRESSION=1") catch @panic("OOM");
        if (ext_zstd) loader_test_flags.append(b.allocator, "-DENABLE_ZSTD_COMPRESSION=1") catch @panic("OOM");
        test_mod.addCSourceFiles(.{
            .root = b.path("ext"),
            .files = &.{"repo_deb.c"},
            .flags = loader_test_flags.items,
        });
        if (ext_zlib) test_mod.linkSystemLibrary("z", .{});
        if (ext_lzma) test_mod.linkSystemLibrary("lzma", .{});
        if (ext_zstd) test_mod.linkSystemLibrary("zstd", .{});
    }

    const test_exe = b.addExecutable(.{
        .name = "libsolv-zig-test",
        .root_module = test_mod,
    });
    const test_step = b.step("test", "Run Zig build integration tests");
    test_step.dependOn(&b.addRunArtifact(test_exe).step);
    if (ext_lib) |lib| test_step.dependOn(&lib.step);

    // ---------------------------------------------------------------
    // tools/dumpsolv (optional): exercises the core library end-to-end
    // ---------------------------------------------------------------
    if (with_tools) {
        const dumpsolv_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        dumpsolv_mod.addConfigHeader(version_h);
        dumpsolv_mod.addIncludePath(b.path("src"));
        dumpsolv_mod.linkLibrary(solv_lib);
        dumpsolv_mod.addCSourceFiles(.{
            .root = b.path("tools"),
            .files = &.{"dumpsolv.c"},
            .flags = &.{"-D_FILE_OFFSET_BITS=64"},
        });

        const dumpsolv_exe = b.addExecutable(.{
            .name = "dumpsolv",
            .root_module = dumpsolv_mod,
        });
        b.installArtifact(dumpsolv_exe);
    }
}
