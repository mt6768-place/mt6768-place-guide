# mt6768-place — build guide

Build **PixelOS 17 (Android 17)** for the Xiaomi **merlinx**
(Redmi Note 9 / Redmi 10X 4G, MT6768 Helio G85) from this organisation's
device trees.

> The **recovery (OrangeFox)** guide lives on the [`recovery`](../../tree/recovery)
> branch of this repository.

---

## 1. Requirements

- Linux x86_64, 16 GB RAM or more, **~300 GB** free
- `repo`, `git`, `git-lfs`, `ccache`, JDK 17, Python 3

## 2. Sync

```bash
bash scripts/sync.sh ~/pixelos-merlinx
```

This runs `repo init` against the PixelOS manifest, drops
`local_manifests/merlinx.xml` in place and syncs.

| Path | Repository | Branch |
|---|---|---|
| `device/xiaomi/merlinx` | `device_xiaomi_merlinx` | `a17` |
| `device/xiaomi/mt6768-common` | `device_xiaomi_mt6768-common` | `a17` |
| `kernel/xiaomi/mt6768` | `android_kernel_xiaomi_mt6768-s` | `a17` |
| `vendor/xiaomi/mt6768-common` | `proprietary_vendor_xiaomi_mt6768-common` | `a17` |
| `device/mediatek/sepolicy_vndr` | `android_device_mediatek_sepolicy_vndr` | `a17` |
| `hardware/mediatek` | `android_hardware_mediatek` | `a17` |

**The kernel is the S-vendor one.** The old repository ending in `-r` targeted
an R vendor and does not work here.

`vendor/xiaomi/merlinx` and `hardware/xiaomi` carry no changes of ours, so the
manifest points at their real upstream rather than mirroring them.

## 3. Apply the AOSP patches

```bash
bash scripts/apply-patches.sh ~/pixelos-merlinx
```

Three small changes that live in AOSP repositories. The script detects patches
that are already applied.

## 4. Build

```bash
cd ~/pixelos-merlinx
source build/envsetup.sh
lunch custom_merlinx-cp2a-userdebug
m pixelos -j$(nproc --all)
```

The flashable zip lands in `out/target/product/merlinx/`.

---

## What Android 17 required

### Black screen at boot — ION

This kernel is 4.19 and **exposes only ION**, with no `/dev/dma_heap`. From
Android 17 `libdmabufheap` and `libion` drop the ION path unless the legacy
implementation is requested, so MediaTek's gralloc cannot allocate **a single
graphic buffer** and the device boots to a black screen.

Both halves are needed; either one alone does nothing:

```makefile
# mt6768.mk
$(call soong_config_set_bool,libion,legacy_impl,true)

# BoardConfigCommon.mk
include device/lineage/sepolicy/libion/sepolicy.mk
```

The second grants `/dev/ion` to surfaceflinger, the allocator, the composer,
bootanim, codec2 and the camera. Without it the allocator cannot even open the
device.

### MediaTek blobs colliding with AOSP module names

`/vendor/lib64/libmnl.so` is MediaTek's **GPS** library and is unrelated to the
netlink libmnl in `external/libmnl`; the same applies to `libformatter`. With
the upstream module names the AOSP one overwrites MediaTek's and `mnld` is left
with unresolved `mtk_gps_*` symbols.

They are shipped as `libmnl_mtk` / `libformatter_mtk` with a `stem` that
preserves the installed file name, and `vendor_available` is dropped in
`external/libmnl`.

### AudioTrack ABI

Android 17 added a `codecProvenance` parameter to the `AudioTrack` constructor,
which changes the mangled symbol. `libsink-mtk.so` is a prebuilt that still
imports the old one and fails to link. The patch drops the parameter and passes
an empty provenance internally.

### Telephony

MediaTek's blobs extend classes upstream marked `final` or `private`. The patch
relaxes `RuimFileHandler`, `CsimFileHandler`, `SIMFileHandler`,
`UsimFileHandler`, `GsmMmiCode`, `ImsPhoneMmiCode` and `GsmSMSDispatcher`, and
makes `DataNetwork`'s states `protected`.

### SELinux

- `domain.te`: the mali service rule named `native_app_zygote`, a private type
  vendor policy may not reference. Expressed through `appdomain` / `coredomain`
  set arithmetic instead.
- `genfs_contexts`: dropped the `sysfs /class/typec` genfscon, which now
  collides with the platform policy.
- `seapp_contexts`: dropped `com.qualcomm.qti.poweroffalarm`, absent here.

---

## Performance: stutter and freezes

Diagnosed from a real five minute logcat. The chain was:

1. `nr_free` dropped to **35 MB** and PSI pressure reached **70%**
2. lmkd killed **~25 processes in 22 seconds**
3. threads holding `system_server` locks stalled in direct reclaim:
   **53 lock waits over one second, the worst at 4.4 s**, in
   `ActivityManagerService`, `BroadcastController`, `ShortcutService` and
   `PackageManagerService`
4. with those locks held the UI froze: `Skipped 713 frames` (about 12 seconds),
   292, 127...
5. killed apps relaunched, and **all 225 slow operations in the log were
   `startProcess`**, feeding the loop

### Cause: lmkd was never tuned

The tree defined **no** `ro.lmk.*` property and no `ro.config.low_ram`. In
`system/memory/lmkd/lmkd.cpp`:

```c
low_ram_device = property_get_bool("ro.config.low_ram", false);   // -> false
thrashing_limit = low_ram_device ? DEF_THRASHING_LOWRAM : DEF_THRASHING;
#define DEF_THRASHING_LOWRAM 30
#define DEF_THRASHING        100
```

So `thrashing_limit=100`: lmkd does not treat the system as thrashing until the
refault ratio reaches 100%, tolerating seconds of heavy swapping, with the UI
already frozen, before killing anything.

```properties
ro.lmk.thrashing_limit=30
ro.lmk.swap_free_low_percentage=20
```

### Secondary cause: ADPF was disabled

```
E perf_hint: createSessionUsingConfig: PerformanceHint cannot create session.
             PowerHintSessions are not supported!
```

SystemUI, Chrome, Reddit and GMS all asked for performance hint sessions and
**every one failed**. The Lineage power HAL does implement `PowerHintSession`,
but the gate is:

```cpp
if (!HintManager::GetInstance()->IsAdpfSupported())
    return EX_UNSUPPORTED_OPERATION;   // IsAdpfSupported() == !adpfs_.empty()
```

and `configs/powerhint.json` only carried `Nodes` and `Actions`, with no
`AdpfConfig`. A profile with the 20 fields the parser requires was added.

The kernel side was also missing: `CONFIG_UCLAMP_TASK` **was already in the
code** of this 4.19 tree but had never been enabled, and it is how the HAL
raises the minimum frequency of UI threads.
`CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL=y` satisfies its dependency.

### Verify it is live

```bash
adb shell getprop ro.lmk.thrashing_limit             # 30
adb shell cat /proc/sys/kernel/sched_util_clamp_min  # exists = uclamp active
adb logcat -d | grep perf_hint                       # no "not supported"
adb shell dumpsys android.hardware.power.IPower/default | grep -A3 "ADPF list"
```

The last one should list live sessions, for example from SystemUI.

---

## A note on zram

The fstab asks for `zramsize=50%`. Do not raise it by hand with a kernel
manager app: compressed pages **still occupy physical RAM**, so an oversized
zram takes real memory away from the working set and causes more thrashing,
which is exactly what this is trying to avoid. A 3 GB unit was seen with a
manually set 2 GiB zram, 71% of its RAM.
