#!/usr/bin/env python3
# GeneralsX @android - Offline BC->RGBA8 texture transcoder (issue #9, option 1).
#
# Non-Adreno mobile GPUs (Samsung Xclipse/Exynos, ARM Mali) report
# textureCompressionBC=0 and cannot sample the game's DXT1/3/5 DDS textures
# natively; DXVK emulates them at runtime. This tool transcodes those textures
# to uncompressed A8R8G8B8 DDS *offline* and writes them as loose files that
# override the .big archives at load time (FileSystem::openFile tries the local
# filesystem before archives). No .big repacking, no engine changes.
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
        return None  # already uncompressed — leave the archive copy alone
    return data[84:88]


def dds_mipcount(data):
    mc = struct.unpack_from("<I", data, 28)[0]
    return mc if mc > 0 else 1


def write_a8r8g8b8_dds(top_rgba, mip_count):
    """Encode a PIL RGBA image + regenerated mip chain as an uncompressed
    A8R8G8B8 DDS (little-endian ARGB = BGRA byte order in memory)."""
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
    # ddspf @ offset 72 within the 124-byte header
    struct.pack_into("<I", hdr, 72, 32)              # ddspf.dwSize
    struct.pack_into("<I", hdr, 76, DDPF_RGB | DDPF_ALPHAPIXELS)
    struct.pack_into("<I", hdr, 84, 32)              # dwRGBBitCount
    struct.pack_into("<I", hdr, 88, 0x00FF0000)      # R mask
    struct.pack_into("<I", hdr, 92, 0x0000FF00)      # G mask
    struct.pack_into("<I", hdr, 96, 0x000000FF)      # B mask
    struct.pack_into("<I", hdr, 100, 0xFF000000)     # A mask
    struct.pack_into("<I", hdr, 104, caps)           # dwCaps

    out = bytearray()
    out += DDS_MAGIC
    out += hdr

    img = top_rgba
    for level in range(mip_count):
        r, g, b, a = img.split()
        # BGRA byte order for D3D A8R8G8B8
        out += Image.merge("RGBA", (b, g, r, a)).tobytes()
        if level + 1 < mip_count:
            nw, nh = max(1, img.width // 2), max(1, img.height // 2)
            img = img.resize((nw, nh), Image.Resampling.BOX)
    return bytes(out)


def transcode_one(dds_bytes):
    """DXT DDS bytes -> A8R8G8B8 DDS bytes, or None if unsupported."""
    from PIL import Image

    fourcc = dds_fourcc(dds_bytes)
    if fourcc not in DXT_FOURCC:
        return None
    try:
        img = Image.open(io.BytesIO(dds_bytes)).convert("RGBA")
    except Exception:
        return None
    return write_a8r8g8b8_dds(img, dds_mipcount(dds_bytes))


# --- BIG archive parsing ------------------------------------------------------
def iter_big_entries(path):
    """Yield (name, data) for every file in a BIGF archive."""
    with open(path, "rb") as f:
        if f.read(4) != b"BIGF":
            return
        f.read(4)                                        # archive size (BE)
        count = struct.unpack(">I", f.read(4))[0]
        f.read(4)                                        # header size (BE)
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


def source_stamp(bigs):
    return "\n".join(f"{p}\t{os.path.getsize(p)}\t{int(os.path.getmtime(p))}"
                     for p in sorted(bigs))


def run(asset_dir, out_dir, limit, force):
    bigs = sorted(os.path.join(asset_dir, n) for n in os.listdir(asset_dir)
                  if n.lower().endswith(".big"))
    if not bigs:
        sys.exit(f"No .big archives in {asset_dir}")

    stamp_path = os.path.join(out_dir, ".source-stamp")
    stamp = source_stamp(bigs)
    if not force and os.path.exists(stamp_path):
        with open(stamp_path) as fh:
            if fh.read() == stamp:
                print(f"==> Up to date: {out_dir} (source .big unchanged)")
                return

    done = skipped = failed = 0
    for big in bigs:
        for name, data in iter_big_entries(big):
            if not name.lower().endswith(".dds"):
                continue
            if dds_fourcc(data) not in DXT_FOURCC:
                skipped += 1
                continue
            rel = name.replace("\\", "/")
            dst = os.path.join(out_dir, rel)
            try:
                rgba8 = transcode_one(data)
                if rgba8 is None:
                    failed += 1
                    print(f"  SKIP (unsupported): {rel}", file=sys.stderr)
                    continue
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                with open(dst, "wb") as o:
                    o.write(rgba8)
                done += 1
                if done % 250 == 0:
                    print(f"  ...{done} transcoded")
                if limit and done >= limit:
                    print(f"==> --limit {limit} reached; stopping (no stamp written)")
                    print(f"    transcoded={done} skipped={skipped} failed={failed}")
                    return
            except Exception as e:  # noqa: BLE001 - one bad file must not abort the run
                failed += 1
                print(f"  FAIL {rel}: {e}", file=sys.stderr)

    with open(stamp_path, "w") as fh:
        fh.write(stamp)
    print(f"==> Done. transcoded={done} skipped(non-DXT)={skipped} failed={failed}")
    print(f"    overlay: {out_dir}")


# --- self-check ---------------------------------------------------------------
def selftest():
    """Validate the custom DDS writer + BGRA swizzle + mip chain."""
    from PIL import Image

    # 4x4 with distinct corner pixels incl. alpha
    img = Image.new("RGBA", (4, 4), (10, 20, 30, 40))
    img.putpixel((0, 0), (1, 2, 3, 4))          # R=1 G=2 B=3 A=4
    img.putpixel((3, 3), (250, 200, 150, 100))
    mip_count = 3                               # 4x4 -> 2x2 -> 1x1
    blob = write_a8r8g8b8_dds(img, mip_count)

    assert blob[:4] == DDS_MAGIC, "bad magic"
    w = struct.unpack_from("<I", blob, 4 + 12)[0]
    h = struct.unpack_from("<I", blob, 4 + 8)[0]
    mc = struct.unpack_from("<I", blob, 4 + 24)[0]
    bitcount = struct.unpack_from("<I", blob, 4 + 84)[0]
    rmask = struct.unpack_from("<I", blob, 4 + 88)[0]
    amask = struct.unpack_from("<I", blob, 4 + 100)[0]
    assert (w, h, mc, bitcount) == (4, 4, 3, 32), (w, h, mc, bitcount)
    assert rmask == 0x00FF0000 and amask == 0xFF000000, "bad masks"

    # first texel bytes must be B,G,R,A = 3,2,1,4
    px = blob[4 + 124: 4 + 124 + 4]
    assert px == bytes((3, 2, 1, 4)), f"swizzle wrong: {tuple(px)}"

    # total pixel payload = (16 + 4 + 1) texels * 4 bytes
    expected = 4 + 124 + (16 + 4 + 1) * 4
    assert len(blob) == expected, f"size {len(blob)} != {expected}"
    print("selftest OK")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--asset-dir",
                    default=os.path.expanduser("~/GeneralsX/GeneralsZH"))
    ap.add_argument("--out-dir", default=os.path.join(
        os.path.dirname(__file__), "..", "..", "..",
        "build", "android-textures-rgba8"))
    ap.add_argument("--limit", type=int, default=0)
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
