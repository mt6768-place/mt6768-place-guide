# mt6768-place — guia de compilacion

Como construir **PixelOS 17 (Android 17)** para Xiaomi **merlinx**
(Redmi Note 9 / Redmi 10X 4G, MT6768 Helio G85) con los trees de esta
organizacion.

> La guia del **recovery (OrangeFox)** esta en la rama [`recovery`](../../tree/recovery)
> de este mismo repo.

---

## 1. Requisitos

- Linux x86_64, 16 GB de RAM o mas y **~300 GB** libres
- `repo`, `git`, `git-lfs`, `ccache`, JDK 17, Python 3
- Paciencia: la primera build son un par de horas en una maquina decente

## 2. Sincronizar

```bash
bash scripts/sync.sh ~/pixelos-merlinx
```

Eso hace `repo init` del manifest de PixelOS, coloca
`local_manifests/merlinx.xml` y sincroniza. El manifest apunta a:

| Ruta | Repo | Rama |
|---|---|---|
| `device/xiaomi/merlinx` | `device_xiaomi_merlinx` | `a17` |
| `device/xiaomi/mt6768-common` | `device_xiaomi_mt6768-common` | `a17` |
| `kernel/xiaomi/mt6768` | `android_kernel_xiaomi_mt6768-s` | `a17` |
| `vendor/xiaomi/mt6768-common` | `proprietary_vendor_xiaomi_mt6768-common` | `a17` |
| `device/mediatek/sepolicy_vndr` | `android_device_mediatek_sepolicy_vndr` | `a17` |
| `hardware/mediatek` | `android_hardware_mediatek` | `a17` |

**El kernel es el de vendor S.** El repo antiguo terminado en `-r` era para
vendor R y no sirve aqui.

## 3. Aplicar los parches de AOSP

```bash
bash scripts/apply-patches.sh ~/pixelos-merlinx
```

Tres cambios pequenos que viven en repos de AOSP. No forkeamos AOSP entero
por unas pocas lineas, asi que van como parches. El script detecta si ya
estaban aplicados.

## 4. Compilar

```bash
cd ~/pixelos-merlinx
source build/envsetup.sh
lunch custom_merlinx-cp2a-userdebug
m pixelos -j$(nproc --all)
```

El zip sale en `out/target/product/merlinx/`.

---

## Que hubo que arreglar para Android 17

Cada punto enlaza al commit correspondiente.

### Pantalla en negro al arrancar — ION

Este kernel es 4.19 y **solo expone ION**, sin `/dev/dma_heap`. A partir de
A17 `libdmabufheap` y `libion` descartan la ruta ION salvo que se pida la
implementacion legacy, asi que el gralloc de MediaTek no consigue reservar
**ni un solo buffer grafico** y el telefono arranca a pantalla negra.

Hacen falta **las dos mitades**, no vale solo una:

```makefile
# mt6768.mk
$(call soong_config_set_bool,libion,legacy_impl,true)

# BoardConfigCommon.mk
include device/lineage/sepolicy/libion/sepolicy.mk
```

La segunda concede `/dev/ion` a surfaceflinger, el allocator, el composer,
bootanim, codec2 y la camara. Sin ella el allocator ni siquiera abre el
dispositivo.

### Blobs de MediaTek que chocan con AOSP

`/vendor/lib64/libmnl.so` es la libreria **GPS** de MediaTek y no tiene nada
que ver con la libmnl de netlink de `external/libmnl`; lo mismo con
`libformatter`. Con los nombres de modulo originales, la de AOSP pisa a la de
MediaTek y `mnld` se queda con simbolos `mtk_gps_*` sin resolver.

Se renombran a `libmnl_mtk` / `libformatter_mtk` con un `stem` que conserva el
nombre del fichero instalado, y ademas se desactiva `vendor_available` en
`external/libmnl`.

### ABI de AudioTrack

A17 anadio un parametro `codecProvenance` al constructor de `AudioTrack`, lo
que cambia el simbolo mangleado. `libsink-mtk.so` es un prebuilt que sigue
importando el antiguo y no enlaza. El parche lo quita y pasa una procedencia
vacia internamente.

### Telefonia

Los blobs de MediaTek heredan de clases que upstream marco `final` o
`private`. El parche relaja `RuimFileHandler`, `CsimFileHandler`,
`SIMFileHandler`, `UsimFileHandler`, `GsmMmiCode`, `ImsPhoneMmiCode` y
`GsmSMSDispatcher`, y hace `protected` los estados de `DataNetwork`.

### SELinux

- `domain.te`: la regla del servicio mali nombraba `native_app_zygote`, un
  tipo privado que una politica de vendor no puede referenciar. Se expresa
  con aritmetica de conjuntos sobre `appdomain` / `coredomain`.
- `genfs_contexts`: fuera el `genfscon` de `sysfs /class/typec`, que ahora
  choca con la politica de plataforma.
- `seapp_contexts`: fuera `com.qualcomm.qti.poweroffalarm`, que no existe en
  esta plataforma.

---

## Rendimiento: tirones y congelaciones

Diagnosticado sobre un logcat real de 5 minutos. La cadena era:

1. `nr_free` bajaba a **35 MB** y la presion PSI llegaba al **70%**
2. lmkd mataba **~25 procesos en 22 segundos**
3. los hilos que sostenian los locks de `system_server` se quedaban en
   *direct reclaim*: **53 esperas de mas de 1 segundo, la peor de 4,4 s**, en
   `ActivityManagerService`, `BroadcastController`, `ShortcutService` y
   `PackageManagerService`
4. con esos locks tomados, la UI se congelaba: `Skipped 713 frames` (unos 12
   segundos), 292, 127...
5. las apps muertas se relanzaban, y **las 225 operaciones lentas del log eran
   todas de `startProcess`**, realimentando el bucle

### Causa: lmkd sin ajustar

El arbol no definia **ninguna** propiedad `ro.lmk.*` ni `ro.config.low_ram`.
En `system/memory/lmkd/lmkd.cpp`:

```c
low_ram_device = property_get_bool("ro.config.low_ram", false);   // -> false
thrashing_limit = low_ram_device ? DEF_THRASHING_LOWRAM : DEF_THRASHING;
#define DEF_THRASHING_LOWRAM 30
#define DEF_THRASHING        100
```

Es decir, `thrashing_limit=100`: lmkd no considera que el sistema este
*thrashing* hasta un 100% de refaults, y aguanta segundos de swap machacado
—con la UI ya congelada— antes de matar nada.

```properties
ro.lmk.thrashing_limit=30
ro.lmk.swap_free_low_percentage=20
```

### Causa secundaria: ADPF desactivado

```
E perf_hint: createSessionUsingConfig: PerformanceHint cannot create session.
             PowerHintSessions are not supported!
```

SystemUI, Chrome, Reddit y GMS pedian sesiones de rendimiento y **todas
fallaban**. El HAL de power de Lineage si implementa `PowerHintSession`, pero
el gate es:

```cpp
if (!HintManager::GetInstance()->IsAdpfSupported())
    return EX_UNSUPPORTED_OPERATION;   // IsAdpfSupported() == !adpfs_.empty()
```

y `configs/powerhint.json` solo tenia `Nodes` y `Actions`, sin `AdpfConfig`.
Se anade un perfil con los 20 campos que exige el parser.

Ademas hacia falta el kernel: `CONFIG_UCLAMP_TASK` **ya estaba en el codigo**
de este 4.19 pero nunca se habia activado, y es el mecanismo con el que el HAL
sube la frecuencia minima de los hilos de UI. `CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL=y`
cubre su dependencia.

### Comprobar que esta activo

```bash
adb shell getprop ro.lmk.thrashing_limit             # 30
adb shell cat /proc/sys/kernel/sched_util_clamp_min  # existe = uclamp activo
adb logcat -d | grep perf_hint                       # sin "not supported"
adb shell dumpsys android.hardware.power.IPower/default | grep -A3 "ADPF list"
```

Lo ultimo deberia listar sesiones vivas, por ejemplo de SystemUI.

---

## Nota sobre el zram

El fstab pide `zramsize=50%`. Conviene no subirlo a mano con apps tipo kernel
manager: las paginas comprimidas **siguen ocupando RAM fisica**, asi que un
zram desproporcionado le quita memoria real al conjunto de trabajo y provoca
mas thrashing, justo lo que se intenta evitar. En un 3 GB se vio un zram de
2 GiB (71% de la RAM) puesto a mano.
