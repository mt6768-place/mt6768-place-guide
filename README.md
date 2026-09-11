# OrangeFox for merlinx — build guide

`recovery` branch of the **mt6768-place** guide. The ROM guide is on
[`main`](../../tree/main).

Builds **OrangeFox R12.0** (TWRP 12.1 base) for the Xiaomi **merlinx**,
targeting a host ROM with an **S vendor** (Android 17).

Full write-up of every problem and its fix:
**[recovery-guide](https://github.com/mt6768-place/recovery-guide)**.

---

## Build

```bash
bash scripts/sync.sh ~/fox_12.1            # repo init + sync
bash scripts/apply-patches.sh ~/fox_12.1   # TWRP/AOSP/OrangeFox patches
bash scripts/build.sh ~/fox_12.1           # lunch + mka recoveryimage
```

The image and the flashable zip land in `out/target/product/merlinx/`.

## Repositories involved

| Path | Source | Branch |
|---|---|---|
| `device/xiaomi/merlinx` | `mt6768-place/recovery_device_xiaomi_merlinx` | `recovery-12.1` |
| everything else | `gitlab.com/OrangeFox/sync` | `fox_12.1` |

The recovery device tree is **a separate repository** from the ROM one. They
share a path inside their respective trees but are unrelated.

---

## The four patches

Changes in repositories we do not mirror. Without them the build either fails
or the recovery boots but is useless. The first two are genuine
**uninitialised-memory bugs**, only visible because Android builds with
`-ftrivial-auto-var-init=pattern`, which fills locals with `0xAA...`.

### `0001-vold-fbe-fixes.patch` — decryption without a credential

Two bugs in `system/vold/Decrypt.cpp`.

**A half-filled buffer.** For the no-credential case:

```c
unsigned char password_token[PASSWORD_TOKEN_SIZE];   // 32 bytes, uninitialised
std::string defpassword = "default-password";        // 16 bytes
memcpy(password_token, defpassword.data(), 16);      // the other 16 are garbage
```

AOSP's `SyntheticPasswordManager.stretchLskf()` does
`Arrays.copyOf(DEFAULT_PASSWORD, STRETCHED_LSKF_LENGTH)`: `"default-password"`
**zero padded to 32 bytes**. TWRP wrote only the first 16 and left the rest
uninitialised, which corrupted the `application_id` and derived the wrong key.
The fix is `= {0}`.

**The GCM tag was never checked**, which is what hid the bug above: an
uninitialised `tag` buffer was passed in and the result of
`EVP_DecryptFinal_ex` was ignored, so a wrong key returned garbage silently and
the failure only surfaced much later, in `fscrypt_unlock_user_key`, with no
clue as to the cause. The real tag is now extracted and verified.

### `0002-aidl-uninitialized-pointer.patch` — build dying at 99%

```cpp
struct ConstReferenceFinder : AidlVisitor {
  const AidlConstantReference* found;   // uninitialised
```

It holds `0xaaaaaaaaaaaaaaaa`, so `if (!found)` never fires, `Find()` returns a
garbage pointer and `AIDL_ERROR()` dereferences it: SIGSEGV on **every AIDL
annotation with parameters**. One `= nullptr` fixes it.

### `0003-twrp-theme-absolute-out.patch` — empty `twres/`

The theme is copied during **Soong analysis**, not by a ninja rule, from
`gui/libguitwrp_defaults.go`, using `ctx.Config().Getenv("OUT")`. If `OUT`
arrives as a **relative** path and `soong_build` runs from a different working
directory, the destination resolves wrong, `MkdirAll` fails and **every error
is discarded**. The build carries on and dies at 99%:

```
sed: .../recovery/root/twres/splash.xml: No such file or directory
```

The patch anchors `OUT` to an absolute path.

### `0004-orangefox-isolate-tmp.patch` — builds clobbering each other

`OrangeFox_A12.sh` keeps its state in fixed `/tmp` paths
(`/tmp/fox_build_000tmp.txt`, `/tmp/Fox_000_tmp`, `/tmp/oFox00.tmp`...). On a
shared machine, two users building OrangeFox at the same time **read each
other's variables**.

Observed symptom: the image was written to `/OrangeFox-...img`, with `$OUT`
empty, because the script loaded another user's state file for a different
device. The patch moves everything under `/tmp/ofox_$(id -un)`.

---

## Two build traps

**`vendorsetup.sh` only runs on `source build/envsetup.sh`.** Re-running
`lunch` alone does not refresh the `OF_*` / `FOX_*` variables. Worse, removing
a variable from the file is not enough: if it was already exported in the
shell it survives the re-source. Set it to `0` explicitly.

**The ramdisk staging directory is not always reinstalled.** On incremental
builds the rule that copies, say, `libminuitwrp.so` into the ramdisk does not
re-run: the library is relinked but the image still ships the old one. It is
hard to debug because it looks like your changes do nothing. `build.sh` clears
the staging directory first.

---

## What this recovery ships

- FBE decryption with **PIN, pattern, password and no credential at all**
- **MTP and adb at the same time**; `adb sideload` that exits cleanly
- Installing full ROMs with dynamic partitions (super)
- Magisk, AromaFM, init.d addon, **FRP** erase addon, lptools, nano, bash
- **Flash Current OrangeFox**, useful because the ROM overwrites the recovery
  on every boot when `install-recovery` is active
