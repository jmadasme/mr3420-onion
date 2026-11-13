# BITACORA — mr3420-onion-server

Registro de decisiones, comandos y resultados del despliegue.
Los secretos **no** se escriben aqui: viven en `config` (chmod 600, no versionado).

---

## FASE A — Preparacion (2026-10-20)

### Contexto verificado

| Item | Valor |
|------|-------|
| Router | TP-Link TL-MR3420 **v5.0** |
| SoC | MediaTek MT7628AN (MIPS 24KEc) |
| Firmware actual | Stock TP-Link (web "3G/4G Wireless N Router") |
| LAN stock | `192.168.1.66/24` |
| MAC | `0C:80:63:7D:5D:6C` |
| Puertos stock | 22/tcp (dropbear 2012.55), 23/tcp (telnet), 80/tcp (web) |
| Credenciales stock por SSH | `admin/admin` no funcionaron; no se insistio |
| Notebook (cable) | `enp0s31f6`, perfil temporal `mr3420-disc` (DHCP) |
| Notebook (Wi-Fi) | `wlp58s0`, Starlink `192.168.1.1`, Internet OK |
| Perfil original | `netplan-enp0s31f6` (192.168.2.3/24, gw 192.168.2.1) |
| Herramientas | nmap, dnsmasq (TFTP), sshpass, python3+pexpect, curl, wget, nc, ssh |

### Decisiones

1. **Flasheo por TFTP recovery de U-Boot.** La web stock no se uso para evitar
   bloqueos y porque suele rechazar imagenes de OpenWrt. El recovery no requiere
   credenciales.
2. **Imagen oficial OpenWrt 24.10.8**, target `ramips/mt76x8`,
   device `tplink_tl-mr3420-v5`, variante `squashfs-tftp-recovery.bin`.
   Se verifica SHA256 antes de servirla.
3. **Servidor TFTP con dnsmasq** ya instalado en la notebook. No se instalo
   ninguna herramienta.
4. **Servicio publicado:** pagina estatica en `uhttpd` escuchando solo en
   `127.0.0.1:8080`; Tor la mapea a `onion:80`.
5. **Hidden service persistente** en `/etc/tor/hidden_service` (nunca `/var`,
   que es tmpfs). La clave privada queda en flash.
6. **Wi-Fi AP de gestion** `MR3420-Onion-2G` con WPA2; clave aleatoria de 24
   caracteres guardada en `config`.
7. **Colision de subred:** Starlink usa `192.168.1.0/24`, igual que la LAN por
   defecto de OpenWrt. `03_ssh_setup.sh --lan-ip 192.168.10.1` permite mover la
   LAN del router antes de conectar la WAN. Se decidira en runtime al verificar
   la IP WAN.

### Estructura creada

```
mr3420-onion-server/
├── PLAN.md
├── config                 # real, chmod 600, gitignored (secretos)
├── config.example         # plantilla sin secretos
├── .gitignore
├── docs/BITACORA.md
├── firmware/              # imagenes .bin (gitignored)
├── scripts/
│   ├── 01_download_firmware.sh
│   ├── 02_tftp_flash.sh
│   ├── 03_ssh_setup.sh
│   ├── 04_install_tor.sh
│   ├── 05_deploy_uhttpd.sh
│   ├── 06_wifi_ap.sh
│   ├── 07_verify.sh
│   └── 99_restore_network.sh
├── tor/torrc.example
└── www/index.html
```

### Secretos generados

- `ROOT_PASSWORD`: 24 caracteres alfanumericos, solo en `config`.
- `WIFI_KEY`: 24 caracteres alfanumericos, solo en `config`.
- `config` tiene permisos `600` y esta en `.gitignore`.
- `ONION_ADDRESS` se completara en la fase 04.

### Firmware

- URL: ver `config` (`FIRMWARE_URL`).
- SHA256 esperado: `5c570a0ce44c907e6bdb7715cf54ba09b2c263ec45c28d6e069447e353750a2b`.
- Copia para U-Boot: `firmware/tp_recovery.bin`.
- Resultado: **SHA256 verificado** en ambas copias; tamano `8.126.464` bytes
  (7.936 KiB). Descarga oficial por HTTPS el 2026-10-20 08:50.
- Prueba de servido TFTP local (`curl tftp://192.168.0.225/tp_recovery.bin`):
  hash identico al oficial.

### Preparacion TFTP

- Perfil NM `mr3420-tftp`: IP estatica `192.168.0.225/24` en `enp0s31f6`,
  sin gateway ni DNS, `autoconnect no`.
- dnsmasq: `--port=0 --interface=enp0s31f6 --bind-interfaces
  --listen-address=192.168.0.225 --enable-tftp
  --tftp-root=<PROYECTO_DIR>/firmware --tftp-no-blocksize --user=root`.
- Log: `/tmp/mr3420-tftp.log`.
- PID: `/tmp/mr3420-tftp.pid` (PID actual `18656`).
- Estado: **activo**. `enp0s31f6` con `192.168.0.225/24`; perfil
  `mr3420-tftp` activado y `mr3420-disc` desactivado.
- Escucha confirmada: `192.168.0.225:69/udp` (ademas de loopback `127.0.0.1:69`).
- Log inicial: `TFTP root is .../firmware`; prueba local registrada como
  `sent .../tp_recovery.bin to 192.168.0.225`.
- **READY_FOR_POWER_CYCLE**: falta solo la accion fisica del usuario.

### Lecciones operativas

- `sudo -v` falla en sesion no interactiva aunque haya NOPASSWD; los scripts
  usan `sudo -n` para los comandos concretos.
- `kill -0 <pid>` como usuario normal falla con EPERM sobre un proceso root
  (dnsmasq). La comprobacion de vida usa `ps -p <pid>` y la senal se envia con
  `sudo -n kill`.

### Secuencia recomendada para las fases siguientes

1. Accion fisica de recovery (reset 6-7 s al encender) y esperar el primer boot.
2. Volver la notebook a DHCP temporal para aprovisionar:
   `nmcli con down mr3420-tftp && nmcli con up mr3420-disc`
3. `./scripts/03_ssh_setup.sh --lan-ip 192.168.10.1` para mover la LAN antes de
   conectar la WAN (Starlink usa 192.168.1.0/24). El script actualiza
   `ROUTER_IP` en `config` y revalida SSH en la IP nueva.
4. Conectar el cable LAN de Starlink al puerto WAN del MR3420.
5. `./scripts/04_install_tor.sh`, `05_deploy_uhttpd.sh`, `06_wifi_ap.sh`,
   `07_verify.sh --reboot`.
6. Al terminar todo: `./scripts/99_restore_network.sh` (vuelve a
   `netplan-enp0s31f6`, 192.168.2.3/24). No ejecutarlo antes de aprovisionar,
   porque esa subred no alcanza al router.

### Pendiente

- Accion fisica del usuario para entrar en recovery (reset 6-7 s al encender).
- Verificar que el router responda en `192.168.1.1` con OpenWrt.
- Ejecutar 03 → 07 y la prueba de persistencia con `07_verify.sh --reboot`.
- Restaurar la red de la notebook con `99_restore_network.sh` al final.

---

## Fase B — Aprovisionamiento OpenWrt (2026-10-20)

### Flasheo y primer acceso

- Flasheo TFTP recovery **exitoso**. El router arrancó OpenWrt 24.10.8
  (`r29233-443ec4032a`), target `ramips/mt76x8`, arquitectura `mipsel_24kc`.
- Modelo de CPU: MediaTek MT7628AN, MIPS 24KEc V5.5. Kernel 6.6.144.
- La notebook obtuvo `192.168.1.100` por DHCP en `enp0s31f6` con el perfil
  `mr3420-disc`.
- Se detuvo el servidor TFTP dnsmasq y se eliminó `/tmp/mr3420-tftp.pid`.

### Contraseña root y acceso SSH

- Se generó una nueva `ROOT_PASSWORD` de 24 caracteres y se guardó solo en
  `config` (permisos `600`). La contraseña anterior quedó invalidada.
- Login por contraseña verificado en `192.168.10.1`; la contraseña vacía ya no
  es aceptada.
- Se generó un keypair ed25519 en `ssh/mr3420_ed25519` y se instaló la clave
  pública en `/etc/dropbear/authorized_keys` y `/root/.ssh/authorized_keys`
  (permisos correctos). **El login por clave sigue siendo rechazado**
  (`Permission denied (publickey,password)`); el login por contraseña funciona.
  Queda como incidencia menor, no bloqueante.

### Cambio de LAN

- Se movió la LAN a `192.168.10.1/24` para evitar la colisión con Starlink
  (`192.168.1.0/24`).
- La notebook renovó DHCP y quedó en `192.168.10.165/24`; SSH y ping a
  `192.168.10.1` verificados.
- `config` actualizado: `ROUTER_IP=192.168.10.1`.

### Internet temporal por NAT de la notebook

- Sin cable WAN disponible, se habilitó un NAT temporal:
  - Notebook: `ip_forward=1`, MASQUERADE por `wlp58s0`, FORWARD
    `enp0s31f6 -> wlp58s0` y retorno `RELATED,ESTABLISHED`.
  - Router: default route temporal vía `192.168.10.165` por `br-lan` y
    `nameserver 1.1.1.1` en `/tmp/resolv.conf`.
- Verificado desde el router: `ping 1.1.1.1` y `nslookup openwrt.org` OK.
- **Estado:** configuración temporal retirada al pausar la Fase B. La notebook
  conserva `ip_forward=1` porque Docker lo requiere; no se tocó esa parte.

### Reloj y opkg

- El primer `opkg update` falló con `SSL verify error` porque el reloj estaba en
  julio de 2026. Se ajustó la fecha UTC y `opkg update` verificó todos los feeds.
- No se instaló ningún paquete.

### Bloqueo: Tor no entra en el overlay

- `/overlay`: 2.1 MB totales, ~1.9 MB libres.
- `opkg --noaction install tor-basic`: requiere 2710 KB; `tor`: 3030 KB.
- Dependencias: `libopenssl3` (~1.36 MB ipk), `libevent2-7`, `zlib`, `libcap`,
  `libatomic1`; ninguna estaba instalada.
- El espacio libre no alcanza. LuCI y los paquetes base están en el squashfs
  `/rom`; borrarlos no libera overlay. La compresión JFFS2 no es suficiente.
- No hay dispositivo USB conectado ni módulos `kmod-usb-storage`/`kmod-fs-ext4`,
  por lo que extroot USB no es posible en este momento.
- **No se forzó la instalación** (`--force-space` no se usó). Tor no está
  instalado; no hay hidden service ni dirección `.onion`.

### Estado al pausar

- Router accesible por SSH en `192.168.10.1` con contraseña.
- Wi-Fi todavía deshabilitado (`radio0.disabled=1`, SSID `OpenWrt`).
- Firewall correcto: LAN ACCEPT, WAN input/forward REJECT, masquerade WAN.
- LuCI/uhttpd por defecto en LAN; no se desplegó la instancia onion.
- `mr3420-disc` activo en `enp0s31f6` (`192.168.10.165`), `autoconnect no`.
- Perfil `mr3420-tftp` eliminado. Perfil original `netplan-enp0s31f6` intacto.
- `99_restore_network.sh` **no ejecutado** para no perder el acceso al router.
- `config`: `ROUTER_IP=192.168.10.1`, `ONION_ADDRESS=` vacío, SSID y clave Wi-Fi
  definidos (sin exponer secretos).

### Próximas opciones para Tor

1. **Extroot USB**: requiere un pendrive y módulos `kmod-usb-storage` +
   `kmod-fs-ext4`; para instalarlos hace falta reactivar el NAT temporal o
   conectar el WAN.
2. **Imagen OpenWrt a medida** con Tor incluido en el squashfs (requiere
   toolchain/imagen, no disponible en esta sesión).
3. **Hardware con más flash** o router alternativo.

No se debe forzar `opkg` ni borrar paquetes críticos.

## Fase C — Extroot USB, Tor/onion y recuperación (2026-10-20)

### Extroot y paquetes

- Se instalaron `kmod-usb-storage`, `kmod-usb-storage-uas`, `kmod-fs-ext4`,
  `block-mount`, `e2fsprogs` y `fdisk`.
- El puerto USB del MR3420 v5 comparte GPIO con el LED del puerto LAN 4. El
  fix aplicado es `swconfig dev switch0 port 4 set led 11` +
  `swconfig dev switch0 set apply`, seguido de unbind/bind de
  `101c0000.ehci`. Se creó `/etc/init.d/usbpower` para aplicarlo en cada
  arranque (START=10, espera hasta 15 s a `/dev/sd*1`).
- Extroot en una partición ext4 de 4 GB (label `mr3420overlay`, UUID
  `6437b143-61cc-4205-ad2e-02944f29d291`), con `/etc/config/fstab` apuntando
  a `/overlay`. El arranque desde USB se verificó con `mount` y
  `logread` (`mount_root: switched to extroot`).
- Se instalaron `tor 0.4.9.13-r1` y `zerotier 1.14.1-r3` con sus
  dependencias. El overlay quedó con ~15.6 MB usados de 3.9 GB.

### Servicio onion

- `www/index.html` se copió a `/www/onion/index.html`.
- `/etc/init.d/onionweb` ejecuta `uhttpd -h /www/onion -p 127.0.0.1:8080 -f`,
  sin CGI, Lua ni ubus.
- `/etc/tor/torrc` incluye `HiddenServiceDir /etc/tor/hidden_service`,
  `HiddenServiceVersion 3` y `HiddenServicePort 80 127.0.0.1:8080`.
- Se generó una dirección `.onion` v3. La clave privada se respaldó fuera del
  repositorio; **no se versiona**.

### Incidentes

- Tor fue terminado por OOM durante el bootstrap (RSS ~16 MB) en un equipo de
  64 MB. No hay swap (`swapon` falla: kernel sin `CONFIG_SWAP`) y no se
  confirmó zram. Pendiente liberar RAM (detener/deshabilitar uhttpd principal,
  rpcd y odhcpd) y limitar la memoria de Tor.
- El pendrive se desconectó solo y dejó el router con el userspace colgado.
  Se recuperó la clave `.onion` montando la partición read-only en la notebook.
  El extroot debe migrarse a un disco más confiable (disco duro externo).
- El DHCP de la LAN no entregó lease tras los reinicios; se usó IP estática
  `192.168.10.165/24` en la notebook para administrar el router.

### Estado al retomar

- Router apagado, pendrive retirado y clave `.onion` a salvo.
- Pendiente: conectar el disco duro, crear una partición ext4 para extroot,
  migrar `/overlay`, verificar arranque, liberar RAM, configurar ZeroTier
  (red `233ccaac27bddf60`) y probar el acceso al `.onion`.
