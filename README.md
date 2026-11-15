# MR3420 Onion · OpenWrt · Tor

![Estado](https://img.shields.io/badge/estado-preservado-2A9D8F?style=flat-square)
![Versiones](https://img.shields.io/badge/versiones-1-457B9D?style=flat-square)
![Sección](https://img.shields.io/badge/sección-iot-5B7C99?style=flat-square)
![Licencia](https://img.shields.io/badge/licencia-MIT-06141b?style=flat-square)

> Recuperación por TFTP, OpenWrt y un hidden service v3 persistente en un TL-MR3420 v5.

Este repositorio reúne **1 versión** de MR3420 Onion en `versions/`.
Cada carpeta conserva el contenido original de su etapa, sin `.git`, dependencias
instaladas ni binarios pesados. La documentación de operación y de código está en
[`docs/`](docs/), y el sitio del proyecto en [`docs/index.html`](docs/index.html).

## Índice de versiones

| Versión | Qué aporta | Archivos |
|---|---|---:|
| [`mr3420-onion-server`](versions/mr3420-onion-server/) | Siete scripts numerados, configuración de Tor y uhttpd, página estática y guía de reversión. | 18 |

La versión de referencia de esta familia es **`mr3420-onion-server`**: es la que se usa
para el README base y para los documentos canónicos. Las demás se mantienen
completas para que se pueda reconstruir la evolución y comparar decisiones.

## Arranque rápido

```bash
git clone https://github.com/jmadasme/mr3420-onion.git
cd mr3420-onion/versions/mr3420-onion-server
ls scripts/
# leé docs/datasheet.md antes de ejecutar cualquier script
```

Flashear un router puede dejarlo inutilizable. Los scripts asumen el modelo exacto y una conexión por Ethernet. No se incluyen claves ni firmware.

<!-- ficha -->
## Ficha de evaluación

**Madurez global: 3.3/5**

| Criterio | Nota | Evidencia |
|---|---:|---|
| Madurez | 2/5 | Siete scripts y flujo verificado hasta la dirección onion; el arranque estable quedó pendiente por RAM y almacenamiento. |
| Reproducibilidad | 3/5 | Versión de OpenWrt, SHA256 y comandos están fijados; el resultado depende de un pendrive y del estado físico del router. |
| Documentación | 4/5 | Bitácora por fases, datasheet, guía de desarrollador y script de reversión; falta un cierre con el servicio probado. |
| Honestidad de límites | 5/5 | Registra el OOM, la desconexión del USB y el keypair SSH rechazado sin presentar el despliegue como terminado. |
| Valor demostrativo | 4/5 | Muestra el ciclo completo de recuperación, flasheo, extroot y publicación onion sobre hardware muy limitado. |
| Facilidad de despliegue | 2/5 | Exige recovery físico, cable Ethernet, pendrive y paciencia con un equipo de 64 MB de RAM. |

Guía seria y bien instrumentada para publicar un onion desde un router viejo. El procedimiento llega hasta Tor, pero la estabilidad del equipo queda por resolver.

## Lo que no funcionó

### mr3420-onion-server — Tor no entraba en el overlay

El overlay del MR3420 tiene 2,1 MB y Tor con sus dependencias pedía entre 2710 y 3030 KB. No se forzó opkg con --force-space: se agregaron módulos USB y se armó un extroot ext4 de 4 GB, con lo que Tor y ZeroTier quedaron instalados.

### mr3420-onion-server — Puerto USB compartido con el LED de LAN 4

El pendrive no se detectaba porque el puerto USB comparte GPIO con el LED del puerto LAN 4. Se aplicó swconfig sobre el puerto 4, se rehizo el bind de ehci y se creó /etc/init.d/usbpower para repetir la operación en cada arranque.

### mr3420-onion-server — Tor terminado por falta de memoria

Con 64 MB de RAM y sin swap, el bootstrap de Tor murió por OOM con un RSS de 16 MB. Quedó pendiente liberar memoria deteniendo uhttpd principal, rpcd y odhcpd, y limitar el consumo del proceso; esa corrección no se llegó a validar.

### mr3420-onion-server — Pendrive desconectado y userspace colgado

Una desconexión del pendrive dejó el router con el userspace inoperable. La clave onion se recuperó montando la partición en modo lectura desde la notebook, y la bitácora concluye que el extroot debe migrarse a un disco más confiable antes de retomar el despliegue.

<!-- /ficha -->

## Documentación

- [`docs/datasheet.md`](docs/datasheet.md) — instalación, operación y límites.
- [`docs/developer.md`](docs/developer.md) — arquitectura, módulos y extensión.
- [`docs/REFERENCES.md`](docs/REFERENCES.md) — estándares, librerías y fuentes.
- [`docs/index.html`](docs/index.html) — página del proyecto (GitHub Pages).

## El proyecto en detalle


## Qué es este repositorio

Un conjunto de scripts y documentación para convertir un router **TP-Link TL-MR3420
v5** en un servidor de una página estática accesible como **servicio onion v3** sobre
OpenWrt. La idea es simple: un equipo de bajo consumo, sin exposición directa de la IP
doméstica, publicando una página propia a través de Tor.

No es un tutorial para cualquier router. El modelo, la versión de hardware y el firmware
están fijados a propósito porque flashear el archivo equivocado deja el equipo
inutilizable. El repositorio incluye el camino de recuperación antes que el de
instalación.

## Hardware y firmware

| Componente | Detalle |
|---|---|
| Router | TP-Link TL-MR3420 v5 |
| SoC | MediaTek MT7628AN |
| Arquitectura OpenWrt | `ramips/mt76x8` |
| Imagen | OpenWrt 24.10.8, squashfs |
| Recuperación | TFTP + dnsmasq |
| Servicio | Tor hidden service v3 |
| Servidor web | uhttpd en `127.0.0.1:8080` |
| Red local | AP `MR3420-Onion-2G` |

El TL-MR3420 v5 tiene una particularidad conocida: la recuperación por TFTP requiere
un servidor en una dirección concreta y un cliente en el momento exacto del arranque.
Por eso el primer script no instala nada: descarga la imagen y verifica su SHA256.

## El problema

Publicar un servicio desde una red doméstica normalmente implica abrir un puerto en el
router, depender de una IP dinámica y aceptar que cualquier escaneo encuentre el
servicio. Para una página personal o un panel de laboratorio, esa exposición es
desproporcionada.

Tor invierte el modelo: el router establece una conexión saliente, publica un servicio
onion y no necesita un puerto abierto hacia Internet. La dirección `.onion` es larga,
pero no depende de la IP ni del proveedor.

## Arquitectura

```
Internet
   │  (sin port forwarding)
   ▼
Router TL-MR3420 v5 · OpenWrt 24.10.8
   ├── tor  ──► hidden service v3 (clave persistente)
   ├── uhttpd 127.0.0.1:8080  ◄── solo accesible desde Tor
   ├── dnsmasq (DHCP local)
   └── wifi MR3420-Onion-2G
```

La página se sirve desde `www/index.html`. uhttpd escucha únicamente en loopback, de
modo que la página no queda publicada en la LAN ni en la WAN. Tor es el único camino
de entrada.

## Los scripts

El flujo está numerado para que cada paso se pueda revisar y repetir:

| Script | Función |
|---|---|
| `01` | Descargar la imagen de OpenWrt y verificar su SHA256 |
| `02` | Preparar TFTP y dnsmasq para la recuperación |
| `03` | Configurar SSH y endurecer el acceso |
| `04` | Instalar y persistir el hidden service v3 |
| `05` | Publicar uhttpd en `127.0.0.1:8080` |
| `06` | Configurar el AP `MR3420-Onion-2G` |
| `07` | Verificar servicio, claves y página |
| `99` | Revertir la configuración al estado anterior |

Los scripts asumen una conexión por Ethernet y el modelo exacto. No están pensados para
ejecutarse a ciegas: leerlos antes es parte del procedimiento.

## Puesta en marcha, en orden

1. **Descargá y verificá.** El script `01` obtiene la imagen y comprueba el hash. Si el
   hash no coincide, se detiene.
2. **Recuperá o instalá.** El script `02` levanta el entorno TFTP. Es el mismo camino
   que se usa para recuperar un equipo que ya no arranca.
3. **Asegurá el acceso.** El script `03` configura SSH con clave y revisa el firewall.
   Cambiar la contraseña por defecto es obligatorio.
4. **Publicá el onion.** El script `04` crea el hidden service v3 y deja la clave en
   `/etc/tor/hidden_service`, con permisos restringidos.
5. **Serví la página.** El script `05` apunta uhttpd a loopback y al directorio `www`.
6. **Configurá la WiFi.** El script `06` crea el AP local para administración.
7. **Verificá.** El script `07` comprueba que Tor publica el servicio y que la página
   responde.
8. **Revertí si hace falta.** El script `99` restaura la configuración previa.

## Seguridad

- **La clave del hidden service no se publica.** Tor la genera en el equipo. Si se
  pierde, la dirección `.onion` cambia.
- **uhttpd no escucha en la WAN.** El servicio solo es alcanzable por Tor.
- **SSH con clave.** El script de hardening desactiva el acceso por contraseña cuando
  la clave ya funciona.
- **Sin firmware en el repositorio.** La imagen se descarga desde el origen y se
  verifica.
- **Sin credenciales.** La configuración real de red y las claves quedan fuera del
  repositorio.

Un servicio onion no hace que una aplicación insegura sea segura. Reduce la exposición,
pero no reemplaza el hardening, las actualizaciones ni la revisión de la página.

## Qué se verificó y qué no

**Verificado:** la instalación de OpenWrt 24.10.8 en el TL-MR3420 v5, la recuperación
por TFTP, la publicación del hidden service v3, uhttpd en loopback y el AP local.

**No verificado:** otros modelos de la familia MR3420, otras versiones de OpenWrt y el
comportamiento del servicio bajo carga. Es un router de laboratorio, no un servidor de
producción.

## Estructura del repositorio

```
versions/mr3420-onion-server/
├── docs/
│   └── BITACORA.md
├── scripts/
│   ├── 01_*.sh ... 07_*.sh
│   └── 99_restore.sh
├── tor/
│   └── (configuración de ejemplo, sin claves)
└── www/
    └── index.html
```

La página `www/index.html` es estática y de tema oscuro. No tiene backend, base de datos
ni formularios. Es una presencia mínima, no una aplicación.

## Preguntas frecuentes

**¿Puedo usar otro router?** Los conceptos sí; los scripts y la imagen no. Cada modelo
tiene su arquitectura y su procedimiento de recuperación.

**¿Necesito abrir puertos?** No. Tor establece la conexión saliente.

**¿Dónde está la dirección .onion?** Se genera en el equipo y se consulta en el archivo
de hostname del hidden service. No se versiona porque depende de la clave privada.

**¿Qué pasa si pierdo la clave?** Se genera un servicio nuevo y cambia la dirección.

**¿Es anónimo?** Tor protege la ubicación de la red, pero el contenido y el uso pueden
revelar información. No prometas anonimato por usar una página onion.

**¿Puedo volver al firmware original?** Sí, con el script de reversión y el firmware de
TP-Link correspondiente al v5.

## Licencia

MIT © 2026 jmadasme. OpenWrt, Tor y el firmware de TP-Link conservan sus propias
licencias. Flashear hardware fuera de garantía es responsabilidad de quien lo hace.


---

Licencia MIT © 2026 jmadasme. Las versiones se publican como material de
referencia; los nombres de hardware y marcas pertenecen a sus respectivos dueños.
