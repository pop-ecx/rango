const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const base64 = std.base64;
const Aes256 = std.crypto.core.aes.Aes256;
const time = std.time;

pub const CryptoUtils = struct {
    allocator: Allocator,
    const block_length = 16;

    pub fn init(allocator: Allocator) CryptoUtils {
        return CryptoUtils{
            .allocator = allocator,
        };
    }

    pub fn generateSessionId(self: *CryptoUtils, io: Io) ![]const u8 {
        var session_bytes: [8]u8 = undefined;
        Io.random(io, &session_bytes);
        return try std.fmt.allocPrint(self.allocator, "{x}", .{std.mem.readInt(u64, &session_bytes, .big)});
    }

    pub fn generateAESKey(io: Io) [32]u8 {
        var aes_key: [32]u8 = undefined;
        Io.random(io, &aes_key);
        return aes_key;
    }

    // We have to rawdog this because Zig doesn't have a cbc mode
    // ── AES-256-CBC + PKCS#7 (inspired zig-crypto)

    /// Encrypts plaintext → ciphertext (PKCS#7 padded).
    /// Caller owns `out` buffer; must be ≥ padded length.
    /// Returns number of ciphertext bytes written.
    pub fn cbcEncrypt(key: *const [32]u8, iv: *const [16]u8, plaintext: []const u8, out: []u8) !usize {
        const padded_len = ((plaintext.len / block_length) + 1) * block_length;
        if (out.len < padded_len) return error.BufferTooSmall;

        var padded = try std.heap.page_allocator.alloc(u8, padded_len);
        defer std.heap.page_allocator.free(padded);

        @memcpy(padded[0..plaintext.len], plaintext);
        const pad_byte: u8 = @intCast(padded_len - plaintext.len);
        @memset(padded[plaintext.len..padded_len], pad_byte);

        const ctx = std.crypto.core.aes.AesEncryptCtx(Aes256).init(key.*);
        var prev_block: [block_length]u8 = iv.*;
        var offset: usize = 0;
        while (offset < padded_len) : (offset += block_length) {
            var block: [block_length]u8 = undefined;
            for (0..block_length) |i| {
                block[i] = padded[offset + i] ^ prev_block[i];
            }
            ctx.encrypt(&block, &block);
            @memcpy(out[offset..][0..block_length], &block);
            prev_block = block;
        }
        return padded_len;
    }

    pub fn cbcDecrypt(key: *const [32]u8, iv: *const [16]u8, ciphertext: []const u8, out: []u8) !usize {
        if (ciphertext.len == 0 or ciphertext.len % block_length != 0) return error.InvalidCiphertext;
        if (out.len < ciphertext.len) return error.BufferTooSmall;

        const ctx = std.crypto.core.aes.AesDecryptCtx(Aes256).init(key.*);
        var prev_block: [block_length]u8 = iv.*;
        var offset: usize = 0;
        while (offset < ciphertext.len) : (offset += block_length) {
            var block: [block_length]u8 = undefined;
            const ct_block = ciphertext[offset..][0..block_length];
            ctx.decrypt(&block, ct_block);
            for (0..block_length) |i| {
                out[offset + i] = block[i] ^ prev_block[i];
            }
            prev_block = ct_block.*;
        }
        const pad_byte = out[ciphertext.len - 1];
        if (pad_byte == 0 or pad_byte > block_length) return error.InvalidPadding;
        const pad_start = ciphertext.len - pad_byte;
        for (out[pad_start..ciphertext.len]) |b| {
            if (b != pad_byte) return error.InvalidPadding;
        }
        return pad_start;
    }

    // ── Mythic full blob: IV || CT || HMAC-SHA256 ─────────────────────

    /// Encrypts JSON plaintext into Mythic’s encrypted blob:
    ///   IV(16) + Ciphertext + HMAC-SHA256(key, IV||CT)(32)
    /// Caller must free the returned slice.
    pub fn mythicEncrypt(self: *CryptoUtils, key: *const [32]u8, plaintext: []const u8, io: Io) ![]u8 {
        var iv: [16]u8 = undefined;
        Io.random(io, &iv);

        const padded_len = ((plaintext.len / block_length) + 1) * block_length;
        var ct_buf = try self.allocator.alloc(u8, padded_len);
        defer self.allocator.free(ct_buf);

        const ct_len = try cbcEncrypt(key, &iv, plaintext, ct_buf);

        // HMAC over (IV || CT)
        var mac_input = try self.allocator.alloc(u8, 16 + ct_len);
        defer self.allocator.free(mac_input);
        @memcpy(mac_input[0..16], &iv);
        @memcpy(mac_input[16..], ct_buf[0..ct_len]);

        var mac: [32]u8 = undefined;
        std.crypto.auth.hmac.sha2.HmacSha256.create(&mac, mac_input, key);

        // Final blob: IV + CT + MAC
        const blob = try self.allocator.alloc(u8, 16 + ct_len + 32);
        @memcpy(blob[0..16], &iv);
        @memcpy(blob[16 .. 16 + ct_len], ct_buf[0..ct_len]);
        @memcpy(blob[16 + ct_len ..], &mac);
        return blob;
    }

    pub fn mythicDecrypt(self: *CryptoUtils, key: *const [32]u8, blob: []const u8) ![]u8 {
        if (blob.len < 16 + 32) return error.InvalidBlob;
        const iv = blob[0..16];
        const mac = blob[blob.len - 32 ..];
        const ct = blob[16 .. blob.len - 32];

        // Verify HMAC
        var mac_input = try self.allocator.alloc(u8, 16 + ct.len);
        defer self.allocator.free(mac_input);
        @memcpy(mac_input[0..16], iv);
        @memcpy(mac_input[16..], ct);

        var expected: [32]u8 = undefined;
        std.crypto.auth.hmac.sha2.HmacSha256.create(&expected, mac_input, key);
        if (!std.crypto.timing_safe.eql([32]u8, expected, mac[0..32].*)) {
            return error.AuthenticationFailed;
        }

        const pt_buf = try self.allocator.alloc(u8, ct.len);
        errdefer self.allocator.free(pt_buf);

        const pt_len = try cbcDecrypt(key, iv[0..16], ct, pt_buf);
        return try self.allocator.realloc(pt_buf, pt_len);
    }
};

test "AES-256-CBC encrypt/decrypt round-trip" {
    const key = [_]u8{
        0x60, 0x3d, 0xeb, 0x10, 0x15, 0xca, 0x71, 0xbe, 0x2b, 0x73, 0xae, 0xf0, 0x85, 0x7d, 0x77, 0x81,
        0x1f, 0x35, 0x2c, 0x07, 0x3b, 0x61, 0x08, 0xd7, 0x2d, 0x98, 0x10, 0xa3, 0x09, 0x14, 0xdf, 0xf4,
    };
    const iv = [_]u8{ 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f };
    const plaintext = "Hello, AES-256-CBC for Mythic!";

    var ciphertext: [64]u8 = undefined;
    const ct_len = try CryptoUtils.cbcEncrypt(&key, &iv, plaintext, &ciphertext);

    // Must be multiple of 16 and larger than plaintext (PKCS#7)
    try std.testing.expect(ct_len % 16 == 0);
    try std.testing.expect(ct_len > plaintext.len);

    var decrypted: [64]u8 = undefined;
    const pt_len = try CryptoUtils.cbcDecrypt(&key, &iv, ciphertext[0..ct_len], &decrypted);

    try std.testing.expectEqualSlices(u8, plaintext, decrypted[0..pt_len]);
}

test "AES-256-CBC block-aligned input (full extra pad block)" {
    const key = [_]u8{0xAA} ** 32;
    const iv = [_]u8{0xBB} ** 16;
    const plaintext = "0123456789abcdef";

    var ciphertext: [48]u8 = undefined;
    const ct_len = try CryptoUtils.cbcEncrypt(&key, &iv, plaintext, &ciphertext);
    try std.testing.expectEqual(@as(usize, 32), ct_len);

    var decrypted: [48]u8 = undefined;
    const pt_len = try CryptoUtils.cbcDecrypt(&key, &iv, ciphertext[0..ct_len], &decrypted);
    try std.testing.expectEqualSlices(u8, plaintext, decrypted[0..pt_len]);
}

test "AES-256-CBC empty plaintext" {
    const key = [_]u8{0} ** 32;
    const iv = [_]u8{0} ** 16;
    const plaintext = "";

    var ciphertext: [32]u8 = undefined;
    const ct_len = try CryptoUtils.cbcEncrypt(&key, &iv, plaintext, &ciphertext);
    try std.testing.expectEqual(@as(usize, 16), ct_len);

    var decrypted: [32]u8 = undefined;
    const pt_len = try CryptoUtils.cbcDecrypt(&key, &iv, ciphertext[0..ct_len], &decrypted);
    try std.testing.expectEqual(@as(usize, 0), pt_len);
}

test "AES-256-CBC rejects bad padding" {
    const key = [_]u8{0} ** 32;
    const iv = [_]u8{0} ** 16;

    var ciphertext: [32]u8 = undefined;
    _ = try CryptoUtils.cbcEncrypt(&key, &iv, "test", &ciphertext);
    ciphertext[31] = 0xFF; // wrong padding

    var out: [32]u8 = undefined;
    try std.testing.expectError(error.InvalidPadding, CryptoUtils.cbcDecrypt(&key, &iv, &ciphertext, &out));
}

test "AES-256-CBC rejects non-block-aligned ciphertext" {
    const key = [_]u8{0} ** 32;
    const iv = [_]u8{0} ** 16;
    const bad = [_]u8{0} ** 15;

    var out: [32]u8 = undefined;
    try std.testing.expectError(error.InvalidCiphertext, CryptoUtils.cbcDecrypt(&key, &iv, &bad, &out));
}
