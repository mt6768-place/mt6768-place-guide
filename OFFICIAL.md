# Going official

Notes for the day these trees are submitted for official ROM support
(LineageOS, PixelOS or similar). Nothing here is required to build; it is a
checklist of what maintainers ask for.

## Already in place

- [x] **Signed, verified commits** under a single identity
- [x] **One commit per topic**, with a message explaining *why*, not just what
- [x] **No vendor blobs committed into device trees**
- [x] **Changes to AOSP repositories kept as patches**, not as forks of AOSP
- [x] **Build reproducible from a local manifest** checked into this repository

## Still to do

- [ ] **Repository naming.** Upstream expects `android_device_xiaomi_merlinx`,
      `android_device_xiaomi_mt6768-common`, `proprietary_vendor_xiaomi_merlinx`.
      Ours partly follow that already; renaming is a settings change and GitHub
      keeps redirects.

- [ ] **Branch naming.** Official trees use the ROM's branch name
      (`lineage-23.2`, `seventeen`, ...) rather than `a17`. Keep `a17` as the
      working branch and add the ROM-named branch when submitting.

- [ ] **`extract-files.sh` and `proprietary-files.txt`** in the vendor tree, so
      anyone can regenerate the blobs from a stock image instead of trusting a
      commited copy.

- [ ] **Upstream the AOSP patches.** `external/libmnl`, `frameworks/av` and
      `frameworks/opt/telephony` carry local workarounds. Official ROMs will
      not take device-specific hacks in shared repositories, so these need
      either an upstreamable form or a move into the device tree.

      The `libmnl` one in particular is a device-specific workaround for a
      MediaTek blob name collision; upstream will want it solved differently.

- [ ] **Clean up `-ftrivial-auto-var-init` findings.** Two of the fixes in the
      recovery branch are genuine uninitialised-memory bugs in TWRP and AOSP
      code. They are worth sending upstream on their own merit.

- [ ] **A device wiki entry** with the maintainer, supported variants and
      known issues.

## Known deviations a reviewer will ask about

| Deviation | Why |
|---|---|
| `libion.legacy_impl` | 4.19 kernel with no `/dev/dma_heap`. Not a hack: it is the supported switch for exactly this case. |
| Renamed MediaTek blobs | `libmnl` / `libformatter` collide with AOSP module names. The `stem` keeps the installed file name, so nothing else changes. |
| `AudioTrack` ABI | A prebuilt imports the pre-A17 symbol. Cannot be fixed without the blob's source. |
| `ro.lmk.*` tuning | The device has 3-4 GB; the defaults assume a roomier device. |
