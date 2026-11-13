# Datasheet · MR3420 Onion

## 1. Qué es

Procedimiento y scripts para publicar una página estática desde un router
**TP-Link TL-MR3420 v5** como **servicio onion v3** sobre OpenWrt. El router no
expone puertos hacia Internet: Tor establece una conexión saliente y publica el
servicio.

## 2. Hardware compatible

| Componente | Detalle |
|---|---|
| Router | TP-Link TL-MR3420 v5 |
| SoC | MediaTek MT7628AN |
| Arquitectura | `ramips/mt76x8` |
| Imagen | OpenWrt 24.10.8, squashfs |
| RAM/Flash | La de fábrica del v5; suficiente para OpenWrt y Tor |
| Red | 1 WAN, 1 LAN, WiFi 2.4 GHz |

No usar imágenes de otros modelos ni de otras versiones de hardware. Un firmware
incorrecto puede dejar el equipo sin arranque.

## 3. Requisitos

- Router TL-MR3420 v5 con acceso físico.
- Cable Ethernet y un equipo con servidor TFTP para la recuperación.
- Imagen oficial de OpenWrt para `ramips/mt76x8`.
- Conexión a Internet durante la descarga.
- Conocimientos básicos de OpenWrt, SSH y Tor.

## 4. Instalación

El orden importa. Cada paso tiene un script numerado en `scripts/`:

1. `01_download_firmware.sh` descarga la imagen y verifica su SHA256.
2. `02_tftp_flash.sh` prepara TFTP y dnsmasq para flashear o recuperar.
3. `03_ssh_setup.sh` configura SSH y endurece el acceso.
4. `04_install_tor.sh` instala Tor y persiste el hidden service v3.
5. `05_deploy_uhttpd.sh` publica uhttpd en `127.0.0.1:8080`.
6. `06_wifi_ap.sh` configura el AP `MR3420-Onion-2G`.
7. `07_verify.sh` comprueba servicio, claves y página.
8. `99_restore_network.sh` revierte la configuración de red.

Antes de ejecutar cualquier script, leelo. Asumen el modelo exacto, una conexión por
Ethernet y que el equipo está en el estado esperado.

## 5. Configuración

La plantilla es `config.example`. Copiala a `config`, completá los valores y limitá
los permisos:

```bash
cp config.example config
chmod 600 config
```

Variables principales:

| Variable | Uso |
|---|---|
| `ROUTER_IP` | Dirección del router durante la instalación |
| `ROUTER_USER` | Usuario de administración |
| `ROOT_PASSWORD` | Contraseña de root, definida en runtime |
| `WAN_IFACE` / `LAN_IFACE` | Interfaces de red |
| `LOCAL_SERVICE_IP` | Debe ser `127.0.0.1` |
| `LOCAL_SERVICE_PORT` | Puerto de uhttpd, por defecto `8080` |
| `ONION_PORT` | Puerto publicado por Tor, por defecto `80` |
| `HIDDEN_SERVICE_DIR` | `/etc/tor/hidden_service` |
| `WIFI_SSID` / `WIFI_KEY` | AP local de administración |
| `NOTEBOOK_IFACE` / `NOTEBOOK_TFTP_IP` | Interfaz y IP del equipo que sirve TFTP |

`config` no se versiona. No publiques contraseñas ni claves.

## 6. Operación

- La página se sirve desde `www/index.html`.
- uhttpd escucha solo en loopback; no se publica en la LAN ni en la WAN.
- Tor publica el servicio onion v3 y guarda la clave en `/etc/tor/hidden_service`.
- La dirección `.onion` se lee del archivo `hostname` del hidden service.
- El AP `MR3420-Onion-2G` queda para administración local.

## 7. Troubleshooting

**El router no arranca después del flash.** Entrá en modo recuperación por TFTP y
volvé a la imagen oficial. El script `02` documenta el entorno.

**Tor no publica el servicio.** Revisá el estado de `tor`, la ruta
`/etc/tor/hidden_service` y los permisos. La clave debe ser legible solo por Tor.

**La página no responde.** Confirmá que uhttpd escucha en `127.0.0.1:8080` y que el
archivo `www/index.html` existe. Desde fuera del router no debe ser accesible.

**La dirección `.onion` cambió.** Se perdió o se regeneró la clave. Restaurá el
respaldo del hidden service si lo tenías.

**No hay WiFi.** El script `06` debe ejecutarse después de que la red base funcione.
Revisá el canal y la regulación de tu país.

## 8. Seguridad

- Cambiá la contraseña de root antes de conectar el router a cualquier red.
- No abras puertos hacia la WAN: Tor no los necesita.
- Mantené OpenWrt actualizado y revisá los paquetes instalados.
- Guardá la clave del hidden service fuera del repositorio.
- Un servicio onion reduce la exposición, pero no corrige una aplicación insegura.

## 9. Alcance y límites

**Verificado:** OpenWrt 24.10.8 en el TL-MR3420 v5, recuperación TFTP, hidden service
v3, uhttpd en loopback y AP local.

**No verificado:** otros modelos, otras versiones de OpenWrt y carga concurrente.
Es un router de laboratorio, no un servidor de producción.
