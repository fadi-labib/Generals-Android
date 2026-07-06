# BUG: endian_compat.h letoh helpers truncate to 16-bit swap (latent)

**File:** `Dependencies/Utility/Utility/endian_compat.h`
**Found:** 2026-07-06, during the Android-port codebase read-through
**Severity:** Latent — no effect on any current target (all little-endian); wrong on big-endian hosts
**Status:** Fixed in-tree (see commit); offer upstream to TheSuperHackers

## The defect

In the non-VC6 template section (`namespace Endian`), the 4- and 8-byte
**little-endian-to-host** helpers call `le16toh` instead of `le32toh`/`le64toh`:

```cpp
// 4 byte integer, enum
template <typename Type> struct letohHelper<Type, 4> { static Type swap(Type value) { return static_cast<Type>(le16toh(static_cast<SwapType32>(value))); } };
// 8 byte integer, enum
template <typename Type> struct letohHelper<Type, 8> { static Type swap(Type value) { return static_cast<Type>(le16toh(static_cast<SwapType64>(value))); } };
// float
template <> struct letohHelper<float, 4> { static float swap(float value) { SwapType32 v = le16toh(*reinterpret_cast<SwapType32*>(&value)); ... } };
// double
template <> struct letohHelper<double, 8> { static double swap(double value) { SwapType64 v = le16toh(*reinterpret_cast<SwapType64*>(&value)); ... } };
```

The `betoh` float/double specializations are correct (`be32toh`/`be64toh`);
only the `letoh` family is affected.

## Why nothing is broken today

On little-endian hosts (x86_64 Linux/Windows, arm64 macOS/iOS/Android),
`le16toh`, `le32toh`, and `le64toh` are all identity macros, so the wrong call
compiles to the right no-op. The `betoh` path — which does real swapping on
these hosts and is what BIG-archive parsing uses (`StdBIGFileSystem` calls
`betoh` on file counts/offsets/sizes) — is correct.

## When it would break

Any big-endian target (none planned), OR any refactor that starts trusting
`letoh<T>` for 32/64-bit disk formats on a big-endian host: values would get a
16-bit swap semantic applied to a 32/64-bit quantity (with glibc's macro
implementations, effectively garbage for the upper bytes).

## Fix (one-liner family)

Replace `le16toh` with `le32toh` in the `<Type, 4>` and `<float, 4>` helpers,
and with `le64toh` in the `<Type, 8>` and `<double, 8>` helpers. No behavior
change on current targets (identity either way) — safe to land any time, with
a `// GeneralsX @bugfix` annotation, and worth offering upstream
(TheSuperHackers/GeneralsGameCode) since the header comes from there.
