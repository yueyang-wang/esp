const zig_std = @import("std");
const embed = @import("embed");
const build_config = @import("build_config");
const esp_idf = @import("esp_idf");
const binding = @import("binding.zig");

const AuthenticationError = embed.crypto.errors.AuthenticationError;
const IdentityElementError = embed.crypto.errors.IdentityElementError;
const mem = embed.mem;

const empty_ptr = "".ptr;

pub const Sha256 = Hash256;
pub const Sha384 = Hash384;
pub const Sha512 = Hash512;

pub const HmacSha256 = Hmac(Hash256);
pub const HmacSha384 = Hmac(Hash384);
pub const HmacSha512 = Hmac(Hash512);

pub const HkdfSha256 = Hkdf(HmacSha256);
pub const HkdfSha384 = Hkdf(HmacSha384);

pub const Aes128Gcm = AesGcm(128);
pub const Aes256Gcm = AesGcm(256);
pub const ChaCha20Poly1305 = ChaCha20Poly1305Impl;
pub const has_hardware_support = hardwareAesEnabled();

const RandomState = struct {
    fn fill(_: *RandomState, buf: []u8) void {
        if (buf.len == 0) return;
        const rc = binding.espz_mbedtls_random_bytes(buf.ptr, buf.len);
        panicOnNonZero(rc, "mbedTLS random generation failed");
    }
};

var random_state: RandomState = .{};
pub const random = embed.Random.init(&random_state, RandomState.fill);

pub const Ed25519 = struct {
    pub const noise_length: usize = 32;

    pub const Signature = struct {
        pub const encoded_length: usize = 64;

        bytes: [encoded_length]u8,

        pub const VerifyError = anyerror;

        pub fn fromBytes(bytes: [encoded_length]u8) Signature {
            return .{ .bytes = bytes };
        }

        pub fn toBytes(self: Signature) [encoded_length]u8 {
            return self.bytes;
        }

        pub fn verify(_: Signature, _: []const u8, _: PublicKey) !void {
            if (!binding.espz_mbedtls_has_ed25519)
                return error.UnsupportedEd25519;
            unreachable;
        }

        pub fn verifier(_: Signature, _: PublicKey) !Verifier {
            if (!binding.espz_mbedtls_has_ed25519)
                return error.UnsupportedEd25519;
            unreachable;
        }

        pub const Verifier = struct {
            pub const InitError = anyerror;
            pub const VerifyError = anyerror;

            pub fn update(_: *Verifier, _: []const u8) void {}

            pub fn verify(_: *Verifier) !void {
                return error.UnsupportedEd25519;
            }
        };
    };

    pub const PublicKey = struct {
        pub const encoded_length: usize = 32;

        bytes: [encoded_length]u8,

        pub fn fromBytes(bytes: [encoded_length]u8) !PublicKey {
            if (!binding.espz_mbedtls_has_ed25519)
                return error.UnsupportedEd25519;
            return .{ .bytes = bytes };
        }

        pub fn toBytes(self: PublicKey) [encoded_length]u8 {
            return self.bytes;
        }
    };

    pub const SecretKey = struct {
        pub const encoded_length: usize = 64;

        bytes: [encoded_length]u8,

        pub fn fromBytes(bytes: [encoded_length]u8) !SecretKey {
            if (!binding.espz_mbedtls_has_ed25519)
                return error.UnsupportedEd25519;
            return .{ .bytes = bytes };
        }

        pub fn toBytes(self: SecretKey) [encoded_length]u8 {
            return self.bytes;
        }
    };

    pub const KeyPair = struct {
        pub const seed_length: usize = 32;

        public_key: PublicKey,
        secret_key: SecretKey,

        pub fn generate() KeyPair {
            @panic("Ed25519 is not enabled in the current ESP-IDF mbedTLS / PSA configuration");
        }

        pub fn fromSecretKey(_: SecretKey) !KeyPair {
            return error.UnsupportedEd25519;
        }

        pub fn sign(_: KeyPair, _: []const u8, _: ?[noise_length]u8) !Signature {
            return error.UnsupportedEd25519;
        }
    };
};

pub const EcdsaP256Sha256 = zig_std.crypto.sign.ecdsa.EcdsaP256Sha256;
pub const EcdsaP384Sha384 = zig_std.crypto.sign.ecdsa.EcdsaP384Sha384;

pub const X25519 = struct {
    pub const secret_length: usize = 32;
    pub const public_length: usize = 32;
    pub const shared_length: usize = 32;
    pub const seed_length: usize = 32;

    pub const KeyPair = struct {
        secret_key: [secret_length]u8,
        public_key: [public_length]u8,

        pub fn generate() KeyPair {
            if (!binding.espz_mbedtls_has_x25519)
                @panic("X25519 is not enabled in the current ESP-IDF mbedTLS / PSA configuration");

            var secret_key: [secret_length]u8 = undefined;
            var public_key: [public_length]u8 = undefined;
            const rc = binding.espz_mbedtls_x25519_generate(&secret_key, &public_key);
            panicOnNonZero(rc, "mbedTLS X25519 key generation failed");
            return .{
                .secret_key = secret_key,
                .public_key = public_key,
            };
        }
    };

    pub fn recoverPublicKey(secret_key: [secret_length]u8) IdentityElementError![public_length]u8 {
        if (!binding.espz_mbedtls_has_x25519)
            return error.IdentityElement;

        var public_key: [public_length]u8 = undefined;
        const rc = binding.espz_mbedtls_x25519_recover_public(&secret_key, &public_key);
        if (rc != 0) return error.IdentityElement;
        return public_key;
    }

    pub fn scalarmult(secret_key: [secret_length]u8, public_key: [public_length]u8) IdentityElementError![shared_length]u8 {
        if (!binding.espz_mbedtls_has_x25519)
            return error.IdentityElement;

        var shared: [shared_length]u8 = undefined;
        const rc = binding.espz_mbedtls_x25519_scalarmult(&secret_key, &public_key, &shared);
        if (rc != 0) return error.IdentityElement;
        return shared;
    }
};

pub const P256 = struct {
    pub const Fe = [32]u8;
    pub const scalar = [32]u8;
    pub const basePoint = [_]u8{};
};

pub const Aes128 = AesBlock(128);
pub const Aes256 = AesBlock(256);

pub const Certificate = struct {
    buffer: []const u8,
    index: u32,

    pub const Version = enum(u8) {
        v1 = 0,
        v2 = 1,
        v3 = 2,
    };

    pub const AlgorithmCategory = enum(u8) {
        hash,
        signature,
        public_key,
        unknown,
    };

    pub const Algorithm = enum(u8) {
        sha256,
        sha384,
        sha512,
        rsa_pkcs1v15,
        rsa_pss,
        ecdsa,
        unknown,
    };

    pub const NamedCurve = enum(u8) {
        secp256r1,
        secp384r1,
        x25519,
        unknown,
    };

    pub const ExtensionId = enum(u16) {
        subject_alt_name = 17,
        basic_constraints = 19,
        subject_key_identifier = 14,
        authority_key_identifier = 35,
        unknown = 0xffff,
    };

    pub const ParseError = error{InvalidCertificate};
    pub const Error = error{
        InvalidCertificate,
        CertificateVerificationFailed,
        CertificateIssuerNotFound,
        HostVerificationFailed,
        UnsupportedBundle,
        UnsupportedHash,
        InvalidRsaPublicKey,
        InvalidRsaSignature,
        RsaVerificationFailed,
    };

    pub const Parsed = struct {
        buffer: []const u8,
        index: u32,
        validity: Validity,
        pk_offset: usize,
        pk_len: usize,

        pub const Validity = struct {
            not_before: i64,
            not_after: i64,
        };

        pub fn pubKey(self: Parsed) []const u8 {
            return self.buffer[self.pk_offset .. self.pk_offset + self.pk_len];
        }

        pub fn verifyHostName(self: Parsed, hostname: []const u8) Error!void {
            const ptr = if (hostname.len == 0) empty_ptr else hostname.ptr;
            const rc = binding.espz_mbedtls_certificate_verify_hostname(self.buffer.ptr, self.buffer.len, ptr, hostname.len);
            if (rc != 0) return error.HostVerificationFailed;
        }

        pub fn verify(self: Parsed, issuer: Parsed, now_sec: i64) Error!void {
            const rc = binding.espz_mbedtls_certificate_verify(
                self.buffer.ptr,
                self.buffer.len,
                issuer.buffer.ptr,
                issuer.buffer.len,
                now_sec,
            );
            if (rc != 0) return error.CertificateVerificationFailed;
        }
    };

    pub const Bundle = struct {
        pub fn verify(_: Bundle, _: Parsed, _: i64) Error!void {
            return error.UnsupportedBundle;
        }

        pub fn rescan(_: *Bundle, _: embed.mem.Allocator) Error!void {}

        pub fn deinit(_: *Bundle, _: embed.mem.Allocator) void {}
    };

    pub const rsa = struct {
        pub const PublicKey = struct {
            exponent: []const u8,
            modulus: []const u8,

            pub const FromBytesError = Error;
            pub const ParseDerError = Error;

            pub fn parseDer(pub_key: []const u8) ParseDerError!struct {
                modulus: []const u8,
                exponent: []const u8,
            } {
                var offset: usize = 0;
                const seq = try readDerSequence(pub_key, &offset);
                var seq_offset: usize = 0;
                const modulus = try readDerInteger(seq, &seq_offset);
                const exponent = try readDerInteger(seq, &seq_offset);
                if (seq_offset != seq.len) return error.InvalidRsaPublicKey;
                return .{
                    .modulus = modulus,
                    .exponent = exponent,
                };
            }

            pub fn fromBytes(pub_bytes: []const u8, modulus_bytes: []const u8) FromBytesError!PublicKey {
                if (pub_bytes.len == 0 or modulus_bytes.len == 0) return error.InvalidRsaPublicKey;
                return .{
                    .exponent = pub_bytes,
                    .modulus = modulus_bytes,
                };
            }
        };

        pub const PSSSignature = struct {
            pub const VerifyError = Error;

            pub fn fromBytes(comptime modulus_len: usize, msg: []const u8) [modulus_len]u8 {
                return signatureFromBytes(modulus_len, msg);
            }

            pub fn verify(
                comptime modulus_len: usize,
                sig: [modulus_len]u8,
                msg: []const u8,
                public_key: PublicKey,
                comptime Hash: type,
            ) VerifyError!void {
                var digest: [Hash.digest_length]u8 = undefined;
                Hash.hash(msg, &digest, .{});
                try verifySignature(.pss, sig[0..], digest[0..], public_key, hashKindFor(Hash));
            }

            pub fn concatVerify(
                comptime modulus_len: usize,
                sig: [modulus_len]u8,
                msg: []const []const u8,
                public_key: PublicKey,
                comptime Hash: type,
            ) VerifyError!void {
                var hash = Hash.init(.{});
                for (msg) |chunk| hash.update(chunk);
                var digest: [Hash.digest_length]u8 = undefined;
                hash.final(&digest);
                try verifySignature(.pss, sig[0..], digest[0..], public_key, hashKindFor(Hash));
            }
        };

        pub const PKCS1v1_5Signature = struct {
            pub const VerifyError = Error;

            pub fn fromBytes(comptime modulus_len: usize, msg: []const u8) [modulus_len]u8 {
                return signatureFromBytes(modulus_len, msg);
            }

            pub fn verify(
                comptime modulus_len: usize,
                sig: [modulus_len]u8,
                msg: []const u8,
                public_key: PublicKey,
                comptime Hash: type,
            ) VerifyError!void {
                var digest: [Hash.digest_length]u8 = undefined;
                Hash.hash(msg, &digest, .{});
                try verifySignature(.pkcs1v15, sig[0..], digest[0..], public_key, hashKindFor(Hash));
            }

            pub fn concatVerify(
                comptime modulus_len: usize,
                sig: [modulus_len]u8,
                msg: []const []const u8,
                public_key: PublicKey,
                comptime Hash: type,
            ) VerifyError!void {
                var hash = Hash.init(.{});
                for (msg) |chunk| hash.update(chunk);
                var digest: [Hash.digest_length]u8 = undefined;
                hash.final(&digest);
                try verifySignature(.pkcs1v15, sig[0..], digest[0..], public_key, hashKindFor(Hash));
            }
        };
    };

    pub fn parse(cert: Certificate) ParseError!Parsed {
        var info: binding.CertificateInfo = undefined;
        const rc = binding.espz_mbedtls_certificate_parse(cert.buffer.ptr, cert.buffer.len, &info);
        if (rc != 0) return error.InvalidCertificate;
        return .{
            .buffer = cert.buffer,
            .index = cert.index,
            .validity = .{
                .not_before = info.not_before,
                .not_after = info.not_after,
            },
            .pk_offset = info.pk_offset,
            .pk_len = info.pk_len,
        };
    }

    pub fn verify(subject: Certificate, issuer: Certificate, now_sec: i64) Error!void {
        const rc = binding.espz_mbedtls_certificate_verify(
            subject.buffer.ptr,
            subject.buffer.len,
            issuer.buffer.ptr,
            issuer.buffer.len,
            now_sec,
        );
        if (rc != 0) return error.CertificateVerificationFailed;
    }

    const Padding = enum {
        pkcs1v15,
        pss,
    };

    fn verifySignature(
        padding: Padding,
        signature: []const u8,
        digest: []const u8,
        public_key: rsa.PublicKey,
        hash_kind: binding.RsaHash,
    ) Error!void {
        const rc = switch (padding) {
            .pkcs1v15 => binding.espz_mbedtls_rsa_verify_pkcs1v15(
                public_key.modulus.ptr,
                public_key.modulus.len,
                public_key.exponent.ptr,
                public_key.exponent.len,
                hash_kind,
                digest.ptr,
                digest.len,
                signature.ptr,
                signature.len,
            ),
            .pss => binding.espz_mbedtls_rsa_verify_pss(
                public_key.modulus.ptr,
                public_key.modulus.len,
                public_key.exponent.ptr,
                public_key.exponent.len,
                hash_kind,
                digest.ptr,
                digest.len,
                signature.ptr,
                signature.len,
            ),
        };
        if (rc != 0) return error.RsaVerificationFailed;
    }
};

pub fn Hmac(comptime Hash: type) type {
    return struct {
        pub const mac_length: usize = Hash.digest_length;
        pub const key_length: usize = mac_length;
        pub const key_length_min: usize = 0;

        inner: Hash,
        outer_pad: [Hash.block_length]u8,

        const Self = @This();

        pub fn create(out: *[mac_length]u8, msg: []const u8, key: []const u8) void {
            var ctx = Self.init(key);
            ctx.update(msg);
            ctx.final(out);
        }

        pub fn init(key: []const u8) Self {
            var block: [Hash.block_length]u8 = [_]u8{0} ** Hash.block_length;
            if (key.len > Hash.block_length) {
                var hashed: [Hash.digest_length]u8 = undefined;
                Hash.hash(key, &hashed, .{});
                @memcpy(block[0..Hash.digest_length], hashed[0..]);
            } else if (key.len > 0) {
                @memcpy(block[0..key.len], key);
            }

            var ipad = block;
            var opad = block;
            for (&ipad) |*b| b.* ^= 0x36;
            for (&opad) |*b| b.* ^= 0x5c;

            var inner = Hash.init(.{});
            inner.update(&ipad);
            return .{
                .inner = inner,
                .outer_pad = opad,
            };
        }

        pub fn update(self: *Self, msg: []const u8) void {
            self.inner.update(msg);
        }

        pub fn final(self: *Self, out: *[mac_length]u8) void {
            var inner_digest: [Hash.digest_length]u8 = undefined;
            self.inner.final(&inner_digest);

            var outer = Hash.init(.{});
            outer.update(&self.outer_pad);
            outer.update(&inner_digest);
            outer.final(out);
        }
    };
}

pub fn Hkdf(comptime HmacType: type) type {
    return struct {
        pub const prk_length: usize = HmacType.mac_length;

        pub fn extract(salt: []const u8, ikm: []const u8) [prk_length]u8 {
            var prk: [prk_length]u8 = undefined;
            HmacType.create(&prk, ikm, salt);
            return prk;
        }

        pub fn expand(out: []u8, ctx: []const u8, prk: [prk_length]u8) void {
            embed.debug.assert(out.len <= 255 * prk_length);

            var offset: usize = 0;
            var block: [prk_length]u8 = undefined;
            var block_len: usize = 0;
            var counter: u8 = 1;

            while (offset < out.len) : (counter += 1) {
                var mac = HmacType.init(&prk);
                if (block_len != 0) mac.update(block[0..block_len]);
                mac.update(ctx);
                mac.update(&[_]u8{counter});
                mac.final(&block);
                block_len = block.len;

                const remaining = out.len - offset;
                const chunk_len = @min(remaining, block.len);
                @memcpy(out[offset .. offset + chunk_len], block[0..chunk_len]);
                offset += chunk_len;
            }
        }
    };
}

fn HashImpl(
    comptime digest_length_: usize,
    comptime block_length_: usize,
    comptime Context: type,
    comptime initFn: fn (*Context) callconv(.c) void,
    comptime updateFn: fn (*Context, [*]const u8, usize) callconv(.c) void,
    comptime finalFn: fn (*Context, *[digest_length_]u8) callconv(.c) void,
) type {
    return struct {
        pub const digest_length: usize = digest_length_;
        pub const block_length: usize = block_length_;
        pub const Options = struct {};

        ctx: Context,

        const Self = @This();

        pub fn hash(msg: []const u8, out: *[digest_length]u8, _: Options) void {
            var self = Self.init(.{});
            self.update(msg);
            self.final(out);
        }

        pub fn init(_: Options) Self {
            var self: Self = undefined;
            initFn(&self.ctx);
            return self;
        }

        pub fn update(self: *Self, msg: []const u8) void {
            if (msg.len == 0) return;
            updateFn(&self.ctx, msg.ptr, msg.len);
        }

        pub fn final(self: *Self, out: *[digest_length]u8) void {
            finalFn(&self.ctx, out);
        }

        pub fn finalResult(self: *Self) [digest_length]u8 {
            var out: [digest_length]u8 = undefined;
            self.final(&out);
            return out;
        }

        pub fn peek(self: Self) [digest_length]u8 {
            var copy = self;
            return copy.finalResult();
        }
    };
}

const Hash256 = HashImpl(
    32,
    64,
    binding.sha256_context,
    binding.espz_mbedtls_sha256_init,
    binding.espz_mbedtls_sha256_update,
    binding.espz_mbedtls_sha256_final,
);

const Hash384 = HashImpl(
    48,
    128,
    binding.sha512_context,
    binding.espz_mbedtls_sha384_init,
    binding.espz_mbedtls_sha384_update,
    binding.espz_mbedtls_sha384_final,
);

const Hash512 = HashImpl(
    64,
    128,
    binding.sha512_context,
    binding.espz_mbedtls_sha512_init,
    binding.espz_mbedtls_sha512_update,
    binding.espz_mbedtls_sha512_final,
);

fn AesGcm(comptime key_bits: comptime_int) type {
    return struct {
        pub const tag_length: usize = 16;
        pub const nonce_length: usize = 12;
        pub const key_length: usize = key_bits / 8;

        pub fn encrypt(c: []u8, tag: *[tag_length]u8, m: []const u8, ad: []const u8, npub: [nonce_length]u8, key: [key_length]u8) void {
            embed.debug.assert(c.len == m.len);
            const ad_ptr: ?[*]const u8 = if (ad.len == 0) null else ad.ptr;
            const msg_ptr: ?[*]const u8 = if (m.len == 0) null else m.ptr;
            const out_ptr: ?[*]u8 = if (c.len == 0) null else c.ptr;
            const rc = binding.espz_mbedtls_aes_gcm_encrypt(
                key_bits,
                &key,
                &npub,
                npub.len,
                ad_ptr,
                ad.len,
                msg_ptr,
                m.len,
                out_ptr,
                tag,
                tag_length,
            );
            panicOnNonZero(rc, "mbedTLS AES-GCM encrypt failed");
        }

        pub fn decrypt(m: []u8, c: []const u8, tag: [tag_length]u8, ad: []const u8, npub: [nonce_length]u8, key: [key_length]u8) AuthenticationError!void {
            embed.debug.assert(m.len == c.len);
            const ad_ptr: ?[*]const u8 = if (ad.len == 0) null else ad.ptr;
            const msg_ptr: ?[*]const u8 = if (c.len == 0) null else c.ptr;
            const out_ptr: ?[*]u8 = if (m.len == 0) null else m.ptr;
            const rc = binding.espz_mbedtls_aes_gcm_decrypt(
                key_bits,
                &key,
                &npub,
                npub.len,
                ad_ptr,
                ad.len,
                msg_ptr,
                c.len,
                out_ptr,
                &tag,
                tag_length,
            );
            if (rc != 0) return error.AuthenticationFailed;
        }
    };
}

const ChaCha20Poly1305Impl = struct {
    pub const tag_length: usize = 16;
    pub const nonce_length: usize = 12;
    pub const key_length: usize = 32;

    pub fn encrypt(c: []u8, tag: *[tag_length]u8, m: []const u8, ad: []const u8, npub: [nonce_length]u8, key: [key_length]u8) void {
        if (!binding.espz_mbedtls_has_chacha20poly1305)
            @panic("ChaCha20Poly1305 is not enabled in the current ESP-IDF mbedTLS / PSA configuration");

        embed.debug.assert(c.len == m.len);
        const ad_ptr: ?[*]const u8 = if (ad.len == 0) null else ad.ptr;
        const msg_ptr: ?[*]const u8 = if (m.len == 0) null else m.ptr;
        const out_ptr: ?[*]u8 = if (c.len == 0) null else c.ptr;
        const rc = binding.espz_mbedtls_chacha20poly1305_encrypt(
            &key,
            &npub,
            npub.len,
            ad_ptr,
            ad.len,
            msg_ptr,
            m.len,
            out_ptr,
            tag,
            tag_length,
        );
        panicOnNonZero(rc, "mbedTLS ChaCha20-Poly1305 encrypt failed");
    }

    pub fn decrypt(m: []u8, c: []const u8, tag: [tag_length]u8, ad: []const u8, npub: [nonce_length]u8, key: [key_length]u8) AuthenticationError!void {
        if (!binding.espz_mbedtls_has_chacha20poly1305)
            @panic("ChaCha20Poly1305 is not enabled in the current ESP-IDF mbedTLS / PSA configuration");

        embed.debug.assert(m.len == c.len);
        const ad_ptr: ?[*]const u8 = if (ad.len == 0) null else ad.ptr;
        const msg_ptr: ?[*]const u8 = if (c.len == 0) null else c.ptr;
        const out_ptr: ?[*]u8 = if (m.len == 0) null else m.ptr;
        const rc = binding.espz_mbedtls_chacha20poly1305_decrypt(
            &key,
            &npub,
            npub.len,
            ad_ptr,
            ad.len,
            msg_ptr,
            c.len,
            out_ptr,
            &tag,
            tag_length,
        );
        if (rc != 0) return error.AuthenticationFailed;
    }
};

fn AesBlock(comptime aes_key_bits: comptime_int) type {
    return struct {
        pub const key_bits: usize = aes_key_bits;
        pub const block = [16]u8;

        pub const EncryptCtx = struct {
            ctx: binding.aes_context,

            const Self = @This();

            pub fn encrypt(self: Self, out: *[16]u8, in: *const [16]u8) void {
                const rc = binding.espz_mbedtls_aes_encrypt_block(&self.ctx, in, out);
                panicOnNonZero(rc, "mbedTLS AES block encrypt failed");
            }
        };

        pub const DecryptCtx = struct {
            ctx: binding.aes_context,

            const Self = @This();

            pub fn decrypt(self: Self, out: *[16]u8, in: *const [16]u8) void {
                const rc = binding.espz_mbedtls_aes_decrypt_block(&self.ctx, in, out);
                panicOnNonZero(rc, "mbedTLS AES block decrypt failed");
            }
        };

        pub fn initEnc(key: [aes_key_bits / 8]u8) EncryptCtx {
            var ctx: binding.aes_context = undefined;
            const rc = binding.espz_mbedtls_aes_init_enc(&ctx, &key, aes_key_bits);
            panicOnNonZero(rc, "mbedTLS AES encrypt context init failed");
            return .{ .ctx = ctx };
        }

        pub fn initDec(key: [aes_key_bits / 8]u8) DecryptCtx {
            var ctx: binding.aes_context = undefined;
            const rc = binding.espz_mbedtls_aes_init_dec(&ctx, &key, aes_key_bits);
            panicOnNonZero(rc, "mbedTLS AES decrypt context init failed");
            return .{ .ctx = ctx };
        }
    };
}

fn Ecdsa(
    comptime seed_len: usize,
    comptime sig_len: usize,
    comptime compressed_len: usize,
    comptime uncompressed_len: usize,
) type {
    return struct {
        pub const KeyPair = struct {
            pub const seed_length: usize = seed_len;
        };

        pub const Signature = struct {
            pub const encoded_length: usize = sig_len;

            bytes: [encoded_length]u8,

            pub fn fromBytes(bytes: [encoded_length]u8) Signature {
                return .{ .bytes = bytes };
            }

            pub fn toBytes(self: Signature) [encoded_length]u8 {
                return self.bytes;
            }
        };

        pub const PublicKey = struct {
            pub const compressed_sec1_encoded_length: usize = compressed_len;
            pub const uncompressed_sec1_encoded_length: usize = uncompressed_len;
        };

        pub const SecretKey = struct {
            pub const encoded_length: usize = seed_len;
        };
    };
}

fn readDerSequence(bytes: []const u8, offset: *usize) Certificate.Error![]const u8 {
    if (offset.* >= bytes.len or bytes[offset.*] != 0x30) return error.InvalidRsaPublicKey;
    offset.* += 1;
    const len = try readDerLength(bytes, offset);
    if (offset.* + len > bytes.len) return error.InvalidRsaPublicKey;
    const out = bytes[offset.* .. offset.* + len];
    offset.* += len;
    return out;
}

fn readDerInteger(bytes: []const u8, offset: *usize) Certificate.Error![]const u8 {
    if (offset.* >= bytes.len or bytes[offset.*] != 0x02) return error.InvalidRsaPublicKey;
    offset.* += 1;
    const len = try readDerLength(bytes, offset);
    if (offset.* + len > bytes.len or len == 0) return error.InvalidRsaPublicKey;
    var out = bytes[offset.* .. offset.* + len];
    offset.* += len;
    while (out.len > 1 and out[0] == 0) {
        out = out[1..];
    }
    return out;
}

fn readDerLength(bytes: []const u8, offset: *usize) Certificate.Error!usize {
    if (offset.* >= bytes.len) return error.InvalidRsaPublicKey;
    const first = bytes[offset.*];
    offset.* += 1;
    if ((first & 0x80) == 0) return first;

    const count = first & 0x7f;
    if (count == 0 or count > @sizeOf(usize) or offset.* + count > bytes.len)
        return error.InvalidRsaPublicKey;

    var len: usize = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        len = (len << 8) | bytes[offset.* + i];
    }
    offset.* += count;
    return len;
}

fn signatureFromBytes(comptime modulus_len: usize, msg: []const u8) [modulus_len]u8 {
    embed.debug.assert(msg.len == modulus_len);
    var out: [modulus_len]u8 = undefined;
    @memcpy(out[0..], msg);
    return out;
}

fn hashKindFor(comptime Hash: type) binding.RsaHash {
    if (Hash == Sha256) return .sha256;
    if (Hash == Sha384) return .sha384;
    if (Hash == Sha512) return .sha512;
    @compileError("RSA verification requires a sha2 hash implementation");
}

fn hardwareAesEnabled() bool {
    return build_config.config.mbedtls.mbedtls_hardware_aes;
}

fn panicOnNonZero(rc: c_int, message: []const u8) void {
    if (rc != 0) @panic(message);
}
