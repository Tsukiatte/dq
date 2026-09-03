"""Minimal Roblox binary place (.rbxl) reader.

Enough of the format to recover the instance tree and every script source:
header -> SSTR (shared strings) -> INST (classes + referents) -> PROP
(properties) -> PRNT (parent links). Chunks are zstd or LZ4 block compressed.
"""
import struct
import sys
import os

# ---------------------------------------------------------------- decompress
try:
    from compression import zstd as _zstd           # Python 3.14+
    def zstd_decompress(b):
        return _zstd.decompress(b)
except ImportError:
    try:
        import zstandard
        def zstd_decompress(b):
            return zstandard.ZstdDecompressor().decompressobj().decompress(b)
    except ImportError:
        def zstd_decompress(b):
            raise RuntimeError("no zstd module available")


def lz4_block_decompress(src, expected):
    """LZ4 block format, no frame header."""
    dst = bytearray()
    i = 0
    n = len(src)
    while i < n:
        token = src[i]; i += 1
        lit = token >> 4
        if lit == 15:
            while True:
                b = src[i]; i += 1
                lit += b
                if b != 255:
                    break
        dst += src[i:i + lit]; i += lit
        if i >= n:
            break
        offset = src[i] | (src[i + 1] << 8); i += 2
        match = token & 0x0F
        if match == 15:
            while True:
                b = src[i]; i += 1
                match += b
                if b != 255:
                    break
        match += 4
        start = len(dst) - offset
        for k in range(match):
            dst.append(dst[start + k])
    return bytes(dst)


# ------------------------------------------------------------------- reading
class Reader:
    def __init__(self, data):
        self.d = data
        self.i = 0

    def bytes(self, n):
        b = self.d[self.i:self.i + n]; self.i += n
        return b

    def u8(self):
        v = self.d[self.i]; self.i += 1
        return v

    def u32(self):
        v = struct.unpack_from("<I", self.d, self.i)[0]; self.i += 4
        return v

    def i32(self):
        v = struct.unpack_from("<i", self.d, self.i)[0]; self.i += 4
        return v

    def string(self):
        n = self.u32()
        return self.bytes(n)

    def eof(self):
        return self.i >= len(self.d)


def untransform_i32(v):
    """Roblox stores signed ints zigzag-encoded."""
    return (v >> 1) ^ (-(v & 1))


def deinterleave_u32(buf, count):
    """Bytes are transposed: all byte0s, then all byte1s, ... big-endian."""
    out = []
    for i in range(count):
        out.append((buf[i] << 24) | (buf[count + i] << 16)
                   | (buf[2 * count + i] << 8) | buf[3 * count + i])
    return out


def read_referents(r, count):
    raw = deinterleave_u32(r.bytes(4 * count), count)
    refs, acc = [], 0
    for v in raw:
        acc += untransform_i32(v)
        refs.append(acc)
    return refs


# --------------------------------------------------------------------- parse
def parse(path):
    data = open(path, "rb").read()
    assert data[:8] == b"<roblox!", "not a binary rbxl"
    class_count = struct.unpack_from("<I", data, 0x10)[0]
    inst_count = struct.unpack_from("<I", data, 0x14)[0]

    pos = 0x20
    chunks = []
    while pos < len(data):
        name = data[pos:pos + 4]
        comp_len, uncomp_len, _res = struct.unpack_from("<III", data, pos + 4)
        pos += 16
        payload = data[pos:pos + (comp_len if comp_len else uncomp_len)]
        pos += comp_len if comp_len else uncomp_len
        if comp_len:
            if payload[:4] == b"\x28\xb5\x2f\xfd":
                payload = zstd_decompress(payload)
            else:
                payload = lz4_block_decompress(payload, uncomp_len)
        chunks.append((name, payload))
        if name == b"END\x00":
            break

    shared = []
    classes = {}          # classIndex -> {"name":str, "refs":[int]}
    props = {}            # referent -> {propName: value}
    parents = {}          # referent -> parent referent

    for name, payload in chunks:
        r = Reader(payload)
        if name == b"SSTR":
            r.u32()                       # version
            n = r.u32()
            for _ in range(n):
                r.bytes(16)               # md5, unused
                shared.append(r.string())

        elif name == b"INST":
            idx = r.u32()
            cname = r.string().decode("utf8", "replace")
            fmt = r.u8()
            n = r.u32()
            refs = read_referents(r, n)
            if fmt == 1:
                r.bytes(n)                # isService flags
            classes[idx] = {"name": cname, "refs": refs}
            for ref in refs:
                props.setdefault(ref, {})["__class"] = cname

        elif name == b"PROP":
            idx = r.u32()
            pname = r.string().decode("utf8", "replace")
            if idx not in classes:
                continue
            refs = classes[idx]["refs"]
            n = len(refs)
            if r.eof():
                continue
            type_id = r.u8()
            try:
                if type_id == 0x01:                        # String
                    for ref in refs:
                        props[ref][pname] = r.string()
                elif type_id == 0x1C:                      # SharedString
                    ids = deinterleave_u32(r.bytes(4 * n), n)
                    for ref, sid in zip(refs, ids):
                        if sid < len(shared):
                            props[ref][pname] = shared[sid]
                elif type_id == 0x02:                      # Bool
                    for ref in refs:
                        props[ref][pname] = bool(r.u8())
                elif type_id == 0x03:                      # Int32
                    vals = deinterleave_u32(r.bytes(4 * n), n)
                    for ref, v in zip(refs, vals):
                        props[ref][pname] = untransform_i32(v)
                elif type_id == 0x13:                      # Referent
                    for ref, v in zip(refs, read_referents(r, n)):
                        props[ref][pname] = ("ref", v)
                # everything else is skipped; the chunk is self-contained
            except Exception:
                pass

        elif name == b"PRNT":
            r.u8()
            n = r.u32()
            children = read_referents(r, n)
            par = read_referents(r, n)
            for c, p in zip(children, par):
                parents[c] = p

    return {"classes": classes, "props": props, "parents": parents,
            "shared": shared, "class_count": class_count,
            "inst_count": inst_count}


def build_paths(model):
    props, parents = model["props"], model["parents"]

    def nameof(ref):
        v = props.get(ref, {}).get("Name")
        if isinstance(v, bytes):
            return v.decode("utf8", "replace")
        return v or props.get(ref, {}).get("__class", "?")

    cache = {}

    def path(ref, depth=0):
        if ref in cache:
            return cache[ref]
        if depth > 60:
            return nameof(ref)
        p = parents.get(ref, -1)
        out = nameof(ref) if p == -1 else path(p, depth + 1) + "." + nameof(ref)
        cache[ref] = out
        return out

    return path, nameof


if __name__ == "__main__":
    src = sys.argv[1]
    outdir = sys.argv[2]
    m = parse(src)
    path, nameof = build_paths(m)
    os.makedirs(outdir, exist_ok=True)

    SCRIPTS = {"Script", "LocalScript", "ModuleScript"}
    counts = {}
    lines = []
    scripts = []
    for ref, p in sorted(m["props"].items(), key=lambda kv: path(kv[0])):
        cls = p.get("__class", "?")
        counts[cls] = counts.get(cls, 0) + 1
        lines.append("%s\t%s" % (cls, path(ref)))
        if cls in SCRIPTS:
            srcv = p.get("Source")
            scripts.append((path(ref), cls,
                            srcv.decode("utf8", "replace") if isinstance(srcv, bytes) else ""))

    open(os.path.join(outdir, "tree.tsv"), "w", encoding="utf8").write("\n".join(lines))
    with open(os.path.join(outdir, "scripts.txt"), "w", encoding="utf8") as f:
        for p, cls, s in sorted(scripts):
            f.write("\n\n" + "=" * 100 + "\n=== %s  [%s]  (%d chars)\n" % (p, cls, len(s))
                    + "=" * 100 + "\n" + s)

    print("instances parsed:", len(m["props"]), "of", m["inst_count"])
    print("scripts:", len(scripts), " with source:", sum(1 for _, _, s in scripts if s))
    print("total source chars:", sum(len(s) for _, _, s in scripts))
    print("\ntop classes:")
    for c, n in sorted(counts.items(), key=lambda kv: -kv[1])[:25]:
        print("  %6d  %s" % (n, c))
