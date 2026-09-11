# OrangeFox para merlinx — guia de compilacion

Rama `recovery` de la guia de **mt6768-place**. La de la ROM esta en
[`main`](../../tree/main).

Construye **OrangeFox R12.0** (base TWRP 12.1) para Xiaomi **merlinx**,
pensado para convivir con una ROM de **vendor S** (Android 17).

Documentacion detallada de cada problema y su arreglo:
**[recovery-guide](https://github.com/mt6768-place/recovery-guide/wiki)**.

---

## Compilar

```bash
bash scripts/sync.sh ~/fox_12.1            # repo init + sync
bash scripts/apply-patches.sh ~/fox_12.1   # parches sobre TWRP/AOSP/OrangeFox
bash scripts/build.sh ~/fox_12.1           # lunch + mka recoveryimage
```

La imagen y el zip instalable salen en `out/target/product/merlinx/`.

## Repos que intervienen

| Ruta | Origen | Rama |
|---|---|---|
| `device/xiaomi/merlinx` | `mt6768-place/recovery_device_xiaomi_merlinx` | `recovery-12.1` |
| resto del arbol | `gitlab.com/OrangeFox/sync` | `fox_12.1` |

El device tree del recovery es **un repo aparte** del de la ROM: aunque
comparten ruta, no tienen nada que ver.

---

## Parches incluidos

Cuatro cambios en repos que no alojamos. Sin ellos, o la build falla, o el
recovery arranca pero no sirve.

### `0001-vold-fbe-fixes.patch` — descifrado sin contrasena

Dos bugs en `system/vold/Decrypt.cpp`:

**Buffer sin inicializar.** Para el caso "sin credencial":

```c
unsigned char password_token[PASSWORD_TOKEN_SIZE];   // 32 bytes, SIN inicializar
std::string defpassword = "default-password";        // 16 bytes
memcpy(password_token, defpassword.data(), 16);      // los otros 16, basura
```

AOSP hace `Arrays.copyOf(DEFAULT_PASSWORD, STRETCHED_LSKF_LENGTH)`, o sea
`"default-password"` **rellenado con ceros hasta 32**. TWRP escribia solo los
16 primeros y dejaba el resto sin inicializar; con
`-ftrivial-auto-var-init=pattern` esos bytes valen `0xAA...`, contaminaban el
`application_id` y la clave derivada salia mal. Se arregla con `= {0}`.

**El tag GCM no se comprobaba**, lo que ocultaba el fallo anterior: se pasaba
un buffer `tag` sin inicializar y se ignoraba el resultado de
`EVP_DecryptFinal_ex`, asi que con clave incorrecta devolvia basura en
silencio y el error solo aparecia mucho despues, en
`fscrypt_unlock_user_key`. Ahora se extrae el tag real (ultimos 16 bytes) y se
verifica.

### `0002-aidl-uninitialized-pointer.patch` — build que petaba al 99%

```cpp
struct ConstReferenceFinder : AidlVisitor {
  const AidlConstantReference* found;   // sin inicializar
```

Con `-ftrivial-auto-var-init=pattern` vale `0xaaaaaaaaaaaaaaaa`, asi que
`if (!found)` nunca se cumple, `Find()` devuelve un puntero basura y
`AIDL_ERROR()` lo desreferencia: SIGSEGV en **toda anotacion con parametros**.
Un `= nullptr` y listo.

### `0003-twrp-theme-absolute-out.patch` — `twres/` vacio

El tema se copia en tiempo de analisis de Soong, en
`gui/libguitwrp_defaults.go`, usando `ctx.Config().Getenv("OUT")`. Si `OUT`
llega como ruta **relativa** y `soong_build` corre con otro directorio de
trabajo, el destino se resuelve mal, `MkdirAll` falla, **todos los errores se
ignoran** y la build muere al 99% con:

```
sed: .../recovery/root/twres/splash.xml: No such file or directory
```

El parche ancla `OUT` a ruta absoluta.

### `0004-orangefox-isolate-tmp.patch` — builds que se pisan

`vendor/recovery/OrangeFox_A12.sh` usa rutas fijas en `/tmp`
(`/tmp/fox_build_000tmp.txt`, `/tmp/Fox_000_tmp`, `/tmp/oFox00.tmp`...). En una
maquina compartida, **dos usuarios compilando OrangeFox a la vez se leen las
variables el uno al otro**. Sintoma real: la imagen salio a `/OrangeFox-...img`
(con `$OUT` vacio) porque el script cargo el fichero de estado de otro
usuario, que compilaba otro dispositivo. El parche mete todo bajo
`/tmp/ofox_$(id -un)`.

---

## Dos trampas de la build

**`vendorsetup.sh` solo corre al hacer `source build/envsetup.sh`.** Si solo
relanzas `lunch`, las variables `OF_*` / `FOX_*` no se refrescan. Y quitar una
variable del fichero no basta: si ya estaba exportada en el shell, sobrevive.
Hay que ponerla explicitamente a `0`.

**El staging del ramdisk no siempre se reinstala.** En builds incrementales,
la regla que copia por ejemplo `libminuitwrp.so` al ramdisk no vuelve a
ejecutarse: la libreria se re-enlaza pero la imagen sigue llevando la vieja.
Cuesta mucho depurar porque parece que tus cambios no hacen nada. `build.sh`
borra el staging antes de compilar.

---

## Que lleva este recovery

- Descifrado FBE con **PIN, patron o contrasena**, y tambien **sin credencial**
- **MTP y adb a la vez**, y `adb sideload` que cierra bien
- Instalacion de ROMs completas con particiones dinamicas (super)
- Magisk, AromaFM, addon init.d, addon de borrado de **FRP**, lptools, nano y bash
- **Flash Current OrangeFox**, util porque la ROM sobrescribe el recovery en
  cada arranque si `install-recovery` esta activo
