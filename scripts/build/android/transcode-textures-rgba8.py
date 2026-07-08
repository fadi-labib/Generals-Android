#!/usr/bin/env python3
# GeneralsX @android - Offline BC->RGBA8 texture repacker (issue #9, option 1).
#
# Non-Adreno mobile GPUs (Samsung Xclipse/Exynos, ARM Mali) report
# textureCompressionBC=0 and cannot sample the game's DXT1/3/5 DDS textures
# natively; DXVK emulates them at runtime. This tool rebuilds each texture .big
# archive with those DDS transcoded to uncompressed A8R8G8B8, everything else
# copied verbatim. The rebuilt .big *replaces* the stock one on non-Adreno
# devices (push-assets).
#
# Delivery is a single repacked archive, NOT loose files: /sdcard is FUSE
# emulated storage where opening thousands of small files is ~30x slower than
# one sequential .big read, which made loose overlays take minutes to load.
#
# See docs/superpowers/specs/2026-07-08-android-rgba8-texture-overlay-design.md
#
# Usage:
#   transcode-textures-rgba8.py [--asset-dir DIR] [--out-dir DIR] [--limit N] [--force]
#   transcode-textures-rgba8.py --selftest
import argparse
import io
import os
import struct
import sys

# --- DDS constants ------------------------------------------------------------
DDS_MAGIC = b"DDS "
DDSD_CAPS = 0x1
DDSD_HEIGHT = 0x2
DDSD_WIDTH = 0x4
DDSD_PITCH = 0x8
DDSD_PIXELFORMAT = 0x1000
DDSD_MIPMAPCOUNT = 0x20000
DDPF_ALPHAPIXELS = 0x1
DDPF_RGB = 0x40
DDSCAPS_COMPLEX = 0x8
DDSCAPS_TEXTURE = 0x1000
DDSCAPS_MIPMAP = 0x400000

DXT_FOURCC = {b"DXT1", b"DXT2", b"DXT3", b"DXT4", b"DXT5"}


def dds_fourcc(data):
    """Return the FourCC of a DDS blob, or None if it isn't a compressed DDS."""
    if len(data) < 88 or data[:4] != DDS_MAGIC:
        return None
    flags = struct.unpack_from("<I", data, 80)[0]  # ddspf.dwFlags
    DDPF_FOURCC = 0x4
    if not (flags & DDPF_FOURCC):
        return None  # already uncompressed
    return data[84:88]


def dds_mipcount(data):
    mc = struct.unpack_from("<I", data, 28)[0]
    return mc if mc > 0 else 1


def write_a8r8g8b8_dds(top_rgba, mip_count):
    """PIL RGBA image + regenerated mip chain -> uncompressed A8R8G8B8 DDS
    (little-endian ARGB == BGRA byte order in memory)."""
    from PIL import Image

    w, h = top_rgba.size
    flags = (DDSD_CAPS | DDSD_HEIGHT | DDSD_WIDTH | DDSD_PIXELFORMAT
             | DDSD_PITCH | DDSD_MIPMAPCOUNT)
    caps = DDSCAPS_TEXTURE
    if mip_count > 1:
        caps |= DDSCAPS_COMPLEX | DDSCAPS_MIPMAP

    hdr = bytearray(124)
    struct.pack_into("<I", hdr, 0, 124)              # dwSize
    struct.pack_into("<I", hdr, 4, flags)            # dwFlags
    struct.pack_into("<I", hdr, 8, h)                # dwHeight
    struct.pack_into("<I", hdr, 12, w)               # dwWidth
    struct.pack_into("<I", hdr, 16, w * 4)           # dwPitchOrLinearSize
    struct.pack_into("<I", hdr, 24, mip_count)       # dwMipMapCount
    struct.pack_into("<I", hdr, 72, 32)              # ddspf.dwSize
    struct.pack_into("<I", hdr, 76, DDPF_RGB | DDPF_ALPHAPIXELS)
    struct.pack_into("<I", hdr, 84, 32)              # dwRGBBitCount
    struct.pack_into("<I", hdr, 88, 0x00FF0000)      # R mask
    struct.pack_into("<I", hdr, 92, 0x0000FF00)      # G mask
    struct.pack_into("<I", hdr, 96, 0x000000FF)      # B mask
    struct.pack_into("<I", hdr, 100, 0xFF000000)     # A mask
    struct.pack_into("<I", hdr, 104, caps)           # dwCaps

    out = bytearray(DDS_MAGIC)
    out += hdr
    img = top_rgba
    for level in range(mip_count):
        r, g, b, a = img.split()
        out += Image.merge("RGBA", (b, g, r, a)).tobytes()  # BGRA for A8R8G8B8
        if level + 1 < mip_count:
            img = img.resize((max(1, img.width // 2), max(1, img.height // 2)),
                             Image.Resampling.BOX)
    return bytes(out)


def transcode_one(dds_bytes):
    """DXT DDS bytes -> A8R8G8B8 DDS bytes, or None if unsupported."""
    from PIL import Image

    if dds_fourcc(dds_bytes) not in DXT_FOURCC:
        return None
    try:
        img = Image.open(io.BytesIO(dds_bytes)).convert("RGBA")
    except Exception:
        return None
    return write_a8r8g8b8_dds(img, dds_mipcount(dds_bytes))


# --- BIG archive I/O ----------------------------------------------------------
def iter_big_entries(path):
    """Yield (name, data) for every file in a BIGF archive."""
    with open(path, "rb") as f:
        if f.read(4) != b"BIGF":
            return
        f.read(4)                                        # archive size (BE)
        count = struct.unpack(">I", f.read(4))[0]
        f.read(4)                                        # first-data offset (BE)
        entries = []
        for _ in range(count):
            off = struct.unpack(">I", f.read(4))[0]
            size = struct.unpack(">I", f.read(4))[0]
            name = bytearray()
            while True:
                c = f.read(1)
                if c in (b"\0", b""):
                    break
                name += c
            entries.append((name.decode("latin1"), off, size))
        for name, off, size in entries:
            f.seek(off)
            yield name, f.read(size)


def write_big(entries, out_path):
    """Write a BIGF archive. entries: list of (name, data_bytes). Names keep
    their original (backslash) spelling so the engine resolves them unchanged.
    Streamed: never holds a second full copy of the payload."""
    names = [n.encode("latin1") for n, _ in entries]
    header_size = 16 + sum(8 + len(nb) + 1 for nb in names)
    with open(out_path, "wb") as f:
        f.write(b"BIGF")
        f.write(b"\0" * 12)                              # size/count/hdr — filled below
        off = header_size
        for (name, data), nb in zip(entries, names):
            f.write(struct.pack(">II", off, len(data)))
            f.write(nb + b"\0")
            off += len(data)
        for _, data in entries:
            f.write(data)
        total = off
        f.seek(4)
        f.write(struct.pack(">I", total))
        f.write(struct.pack(">I", len(entries)))
        f.write(struct.pack(">I", header_size))


def source_stamp(bigs):
    return "\n".join(f"{p}\t{os.path.getsize(p)}\t{int(os.path.getmtime(p))}"
                     for p in sorted(bigs))


def repack_big(src_big, out_path, limit):
    """Rebuild one .big with DXT DDS -> RGBA8. Returns (done, skipped, failed)
    or None if the archive has no DXT textures (nothing to do)."""
    entries = list(iter_big_entries(src_big))
    if not any(n.lower().endswith(".dds") and dds_fourcc(d) in DXT_FOURCC
               for n, d in entries):
        return None

    out, done, skipped, failed = [], 0, 0, 0
    for name, data in entries:
        is_dxt = name.lower().endswith(".dds") and dds_fourcc(data) in DXT_FOURCC
        if is_dxt and not (limit and done >= limit):
            try:
                rgba8 = transcode_one(data)
            except Exception as e:  # noqa: BLE001 - one bad texture must not abort
                print(f"  FAIL {name}: {e}", file=sys.stderr)
                rgba8 = None
            if rgba8 is None:
                failed += 1
                out.append((name, data))          # keep original so archive stays complete
            else:
                done += 1
                out.append((name, rgba8))
                if done % 500 == 0:
                    print(f"  ...{done} transcoded")
        else:
            skipped += 1
            out.append((name, data))              # TGA / non-DXT / over --limit: verbatim
    write_big(out, out_path)
    return done, skipped, failed


def run(asset_dir, out_dir, limit, force):
    bigs = sorted(os.path.join(asset_dir, n) for n in os.listdir(asset_dir)
                  if n.lower().endswith(".big"))
    if not bigs:
        sys.exit(f"No .big archives in {asset_dir}")

    stamp_path = os.path.join(out_dir, ".source-stamp")
    stamp = source_stamp(bigs)
    if not force and not limit and os.path.exists(stamp_path):
        with open(stamp_path) as fh:
            if fh.read() == stamp:
                print(f"==> Up to date: {out_dir} (source .big unchanged)")
                return

    repacked = []
    for big in bigs:
        res = repack_big(big, os.path.join(out_dir, os.path.basename(big)), limit)
        if res is None:
            continue
        done, skipped, failed = res
        name = os.path.basename(big)
        sz = os.path.getsize(os.path.join(out_dir, name))
        print(f"==> {name}: transcoded={done} verbatim={skipped} failed={failed} "
              f"-> {sz // (1024*1024)} MB")
        repacked.append(name)

    if not repacked:
        print("==> No .big contained DXT textures; nothing repacked.")
        return
    if not limit:
        with open(stamp_path, "w") as fh:
            fh.write(stamp)
    print(f"==> Done. Repacked: {', '.join(repacked)}")


# --- self-check ---------------------------------------------------------------
def selftest():
    from PIL import Image

    # 1) DDS writer + BGRA swizzle + mip chain
    img = Image.new("RGBA", (4, 4), (10, 20, 30, 40))
    img.putpixel((0, 0), (1, 2, 3, 4))
    blob = write_a8r8g8b8_dds(img, 3)             # 4x4 -> 2x2 -> 1x1
    assert blob[:4] == DDS_MAGIC
    w = struct.unpack_from("<I", blob, 4 + 12)[0]
    mc = struct.unpack_from("<I", blob, 4 + 24)[0]
    amask = struct.unpack_from("<I", blob, 4 + 100)[0]
    assert (w, mc, amask) == (4, 3, 0xFF000000), (w, mc, hex(amask))
    assert blob[4 + 124: 4 + 128] == bytes((3, 2, 1, 4)), "BGRA swizzle wrong"
    assert len(blob) == 4 + 124 + (16 + 4 + 1) * 4, "mip payload size wrong"

    # 2) BIG writer round-trips through the reader with names + data intact
    import tempfile
    ents = [("Art\\Textures\\a.dds", b"HELLO-A"), ("data\\b.tga", b"BB")]
    with tempfile.NamedTemporaryFile(suffix=".big", delete=False) as tf:
        tmp = tf.name
    try:
        write_big(ents, tmp)
        back = list(iter_big_entries(tmp))
        assert back == ents, back
    finally:
        os.unlink(tmp)
    print("selftest OK")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--asset-dir",
                    default=os.path.expanduser("~/GeneralsX/GeneralsZH"))
    ap.add_argument("--out-dir", default=os.path.join(
        os.path.dirname(__file__), "..", "..", "..",
        "build", "android-textures-rgba8"))
    ap.add_argument("--limit", type=int, default=0,
                    help="transcode only the first N DXT textures per archive "
                         "(rest copied verbatim) — for fast testing")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()

    if args.selftest:
        selftest()
        return
    os.makedirs(args.out_dir, exist_ok=True)
    run(args.asset_dir, os.path.abspath(args.out_dir), args.limit, args.force)


if __name__ == "__main__":
    main()
