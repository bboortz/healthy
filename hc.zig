//! hc - tiny health checker (Zig, no libc, no heap).
//!
//!   hc [-t secs] [-s lo-hi] [-m str] [-H name] [-k | --ca file] <url>
//!     -t secs   overall deadline (default 5)      -s lo-hi  accepted status range (default 200-299)
//!     -m str    body must contain str             -H name   Host header + TLS SNI/verify name
//!     -k        skip TLS verification (like curl -k)
//!
//!   tcp://host:port            TCP connect
//!   tls://host:port            TCP connect + verified TLS handshake
//!   http://host[:port]/path    GET, status must be in range (default 200-299)
//!   https://host[:port]/path   same, over verified TLS
//!
//! Exit codes: 0 healthy, 1 unhealthy, 2 usage error.
//! TLS is verified against the CA(s) in `--ca file` (PEM), or against the CA
//! embedded at build time with `-Dca=path/to/ca.pem`. System roots are never used.
const std = @import("std");
const Io = std.Io;
const net = Io.net;
const tls = std.crypto.tls;
const linux = std.os.linux;
const cfg = @import("embedded_ca"); // build-time config: pem (CA to embed), with_tls
const embedded_ca = cfg.pem;

// Size: no stack traces / DWARF parsing, no segfault handler, no alternate signal stack.
pub const panic = std.debug.no_panic;
pub const std_options: std.Options = .{
    .enable_segfault_handler = false,
    .signal_stack_size = null,
    .allow_stack_tracing = false,
};

const Mode = enum { tcp, tls, http, https };

const Target = struct {
    mode: Mode,
    host: []const u8,
    port: u16,
    path: []const u8,
};

// Static buffers: no allocator, no page mapping code linked in.
const buf_len = tls.Client.min_buffer_len;
var sock_rd: [buf_len]u8 = undefined;
var sock_wr: [buf_len]u8 = undefined;
var tls_rd: [buf_len]u8 = undefined;
var tls_wr: [2048]u8 = undefined;
var heap: [32 * 1024]u8 = undefined; // CA bundle only

fn say(msg: []const u8) void {
    _ = linux.write(2, msg.ptr, msg.len);
}

// ---- hard deadline ---------------------------------------------------------
// Covers DNS, connect, handshake and read in one go. std's `setitimer` is typed
// with itimerspec (ns) but the kernel wants itimerval (us), so we declare our own.
const Itimerval = extern struct { interval_sec: isize, interval_usec: isize, sec: isize, usec: isize };

fn onAlarm(_: linux.SIG) callconv(.c) void {
    say("hc: timeout\n");
    linux.exit_group(1);
}

fn armDeadline(secs: u32) void {
    const act: linux.Sigaction = .{
        .handler = .{ .handler = onAlarm },
        .mask = linux.sigemptyset(),
        .flags = 0,
    };
    _ = linux.sigaction(.ALRM, &act, null);
    const tv: Itimerval = .{ .interval_sec = 0, .interval_usec = 0, .sec = @intCast(secs), .usec = 0 };
    _ = linux.syscall3(.setitimer, 0, @intFromPtr(&tv), 0);
}

// ---- argument parsing ------------------------------------------------------
fn parseTarget(s: []const u8) ?Target {
    const sep = std.mem.find(u8, s, "://") orelse return null;
    const mode = std.meta.stringToEnum(Mode, s[0..sep]) orelse return null;
    const rest = s[sep + 3 ..];

    const slash = std.mem.findScalar(u8, rest, '/') orelse rest.len;
    const authority = rest[0..slash];
    const path = if (slash < rest.len) rest[slash..] else "/";

    var host = authority;
    var port_str: ?[]const u8 = null;
    if (authority.len > 0 and authority[0] == '[') { // [v6]:port
        const close = std.mem.findScalar(u8, authority, ']') orelse return null;
        host = authority[1..close];
        if (close + 1 < authority.len) {
            if (authority[close + 1] != ':') return null;
            port_str = authority[close + 2 ..];
        }
    } else if (std.mem.findScalarLast(u8, authority, ':')) |c| {
        host = authority[0..c];
        port_str = authority[c + 1 ..];
    }
    if (host.len == 0) return null;

    const port: u16 = if (port_str) |p|
        std.fmt.parseInt(u16, p, 10) catch return null
    else switch (mode) {
        .http => 80,
        .https => 443,
        else => return null, // tcp/tls need an explicit port
    };
    return .{ .mode = mode, .host = host, .port = port, .path = path };
}

// ---- TLS CA bundle ---------------------------------------------------------
const Bundle = std.crypto.Certificate.Bundle;

fn addPem(bundle: *Bundle, gpa: std.mem.Allocator, pem: []const u8, now_sec: i64) !void {
    const begin = "-----BEGIN CERTIFICATE-----";
    const end = "-----END CERTIFICATE-----";
    var i: usize = 0;
    while (std.mem.findPos(u8, pem, i, begin)) |b| {
        const start = b + begin.len;
        const e = std.mem.findPos(u8, pem, start, end) orelse return error.BadPem;
        i = e + end.len;
        const b64 = std.mem.trim(u8, pem[start..e], " \t\r\n");
        const decoded_start: u32 = @intCast(bundle.bytes.items.len);
        try bundle.bytes.ensureUnusedCapacity(gpa, b64.len);
        const dest = bundle.bytes.allocatedSlice()[decoded_start..];
        bundle.bytes.items.len += try std.base64.standard.decoderWithIgnore(" \r\n\t").decode(dest, b64);
        try bundle.parseCert(gpa, decoded_start, now_sec);
    }
}

// ---- the check -------------------------------------------------------------
fn sendGet(w: *Io.Writer, t: Target, name: []const u8) !void {
    try w.writeAll("GET ");
    try w.writeAll(t.path);
    try w.writeAll(" HTTP/1.0\r\nHost: ");
    try w.writeAll(name);
    try w.writeAll("\r\nUser-Agent: hc\r\nConnection: close\r\n\r\n");
    try w.flush();
}

fn dial(io: Io, t: Target) !net.Stream {
    // No per-connect timeout: std (0.17.1) doesn't implement it on POSIX yet and
    // panics. The SIGALRM watchdog (armDeadline) bounds the whole run instead.
    const opts: net.IpAddress.ConnectOptions = .{ .mode = .stream };
    if (net.IpAddress.parse(t.host, t.port)) |addr| {
        return addr.connect(io, opts);
    } else |_| {}
    const hn = try net.HostName.init(t.host);
    return hn.connect(io, t.port, opts);
}

const Opts = struct {
    secs: u32 = 5,
    lo: u16 = 200,
    hi: u16 = 299,
    ca: ?[]const u8 = null,
    insecure: bool = false, // -k: skip certificate verification
    name: ?[]const u8 = null, // -H: Host header + TLS SNI/verify name
    match: ?[]const u8 = null, // -m: body must contain this string
    target: Target = undefined,
};

var body_buf: [1024]u8 = undefined;

fn checkResponse(r: *Io.Reader, o: Opts) !void {
    const status = try r.takeDelimiterInclusive('\n');
    // "HTTP/1.x NNN ..."
    if (status.len < 12 or !std.mem.startsWith(u8, status, "HTTP/1.") or status[8] != ' ') return error.BadResponse;
    const code = std.fmt.parseInt(u16, status[9..12], 10) catch return error.BadResponse;
    if (code < o.lo or code > o.hi) return error.BadStatus;

    const want = o.match orelse return;
    while (true) { // skip headers
        const h = try r.takeDelimiterInclusive('\n');
        if (h.len <= 2) break;
    }
    const n = try r.readSliceShort(&body_buf);
    if (std.mem.find(u8, body_buf[0..n], want) == null) return error.BodyMismatch;
}

fn run(io: Io, o: Opts) !void {
    const t = o.target;
    const stream = try dial(io, t);
    defer stream.close(io);

    var sr = stream.reader(io, &sock_rd);
    var sw = stream.writer(io, &sock_wr);

    switch (t.mode) {
        .tcp => return,
        .http => {
            try sendGet(&sw.interface, t, o.name orelse t.host);
            return checkResponse(&sr.interface, o);
        },
        .tls, .https => {
            if (comptime !cfg.with_tls) return error.TlsNotBuiltIn;
            var fba: std.heap.FixedBufferAllocator = .init(&heap);
            const gpa = fba.allocator();
            const now = Io.Timestamp.now(io, .real);

            var bundle: Bundle = .empty;
            if (o.insecure) {} else if (o.ca) |path| {
                try bundle.addCertsFromFilePath(gpa, io, now, Io.Dir.cwd(), path);
            } else {
                try addPem(&bundle, gpa, embedded_ca, now.toSeconds());
            }
            const name = o.name orelse t.host;

            var entropy: [tls.Client.Options.entropy_len]u8 = undefined;
            io.random(&entropy);
            var lock: Io.RwLock = .init;

            var c = tls.Client.init(&sr.interface, &sw.interface, .{
                .host = if (o.insecure) .no_verification else .{ .explicit = name },
                .ca = if (o.insecure) .no_verification else .{ .bundle = .{ .gpa = gpa, .io = io, .lock = &lock, .bundle = &bundle } },
                .allow_truncation_attacks = true, // we only read the head/first KB; HTTP/1.0 close-delimited
                .read_buffer = &tls_rd,
                .write_buffer = &tls_wr,
                .entropy = &entropy,
                .realtime_now = now,
            }) catch |err| switch (err) {
                error.WriteFailed => return sw.err.?,
                error.ReadFailed => return sr.err.?,
                else => |e| return e,
            };
            if (t.mode == .tls) return;

            try sendGet(&c.writer, t, name);
            try sw.interface.flush();
            return checkResponse(&c.reader, o);
        },
    }
}

pub fn main(init: std.process.Init.Minimal) u8 {
    var o: Opts = .{};
    var have_target = false;
    var it = init.args.iterate();
    _ = it.next();
    while (it.next()) |a| {
        if (std.mem.eql(u8, a, "-t")) {
            o.secs = std.fmt.parseInt(u32, it.next() orelse return usage(), 10) catch return usage();
        } else if (std.mem.eql(u8, a, "-s")) {
            const v = it.next() orelse return usage();
            const dash = std.mem.findScalar(u8, v, '-') orelse return usage();
            o.lo = std.fmt.parseInt(u16, v[0..dash], 10) catch return usage();
            o.hi = std.fmt.parseInt(u16, v[dash + 1 ..], 10) catch return usage();
        } else if (std.mem.eql(u8, a, "--ca")) {
            o.ca = it.next() orelse return usage();
        } else if (std.mem.eql(u8, a, "-k")) {
            o.insecure = true;
        } else if (std.mem.eql(u8, a, "-H")) {
            o.name = it.next() orelse return usage();
        } else if (std.mem.eql(u8, a, "-m")) {
            o.match = it.next() orelse return usage();
        } else {
            o.target = parseTarget(a) orelse return usage();
            have_target = true;
        }
    }
    if (!have_target) return usage();

    armDeadline(o.secs);

    var threaded: Io.Threaded = .init_single_threaded;
    const io = threaded.io();

    run(io, o) catch |err| {
        say("hc: ");
        say(@errorName(err));
        say("\n");
        return 1;
    };
    return 0;
}

fn usage() u8 {
    say("usage: hc [-t secs] [-s lo-hi] [-m str] [-H name] [-k | --ca file] (tcp|tls|http|https)://host[:port][/path]\n");
    return 2;
}
