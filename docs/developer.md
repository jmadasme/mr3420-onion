# Guía de desarrollador · MR3420 Onion

## 1. Mapa del repositorio

```
mr3420-onion/
├── README.md
├── LICENSE
├── docs/
│   ├── datasheet.md
│   ├── developer.md
│   ├── REFERENCES.md
│   └── index.html
└── versions/
    └── mr3420-onion-server/
        ├── config.example
        ├── docs/BITACORA.md
        ├── scripts/
        │   ├── 01_download_firmware.sh
        │   ├── 02_tftp_flash.sh
        │   ├── 03_ssh_setup.sh
        │   ├── 04_install_tor.sh
        │   ├── 05_deploy_uhttpd.sh
        │   ├── 06_wifi_ap.sh
        │   ├── 07_verify.sh
        │   ├── 99_restore_network.sh
        │   └── usbpower
        ├── ssh/
        │   └── mr3420_ed25519.pub
        ├── tor/
        │   ├── torrc.example
        │   └── hidden_service/
        │       ├── hostname
        │       └── hs_ed25519_public_key
        └── www/
            └── index.html
```

La clave privada del hidden service y el archivo `config` real no se versionan.

## 2. Arquitectura

```
┌─────────────────────────────────────────────┐
│ TL-MR3420 v5 · OpenWrt 24.10.8              │
│                                             │
│  dnsmasq ── DHCP local                      │
│  tor     ── hidden service v3               │
│  uhttpd  ── 127.0.0.1:8080 ──► www/         │
│  wifi    ── AP MR3420-Onion-2G              │
└─────────────────────────────────────────────┘
              ▲
              │ conexión saliente
              ▼
        red Tor · dirección .onion
```

uhttpd no escucha en la interfaz WAN. Tor es el único camino de entrada. Esa es la
decisión central del diseño: reducir la superficie en vez de confiar en un firewall
bien configurado.

## 3. Convenciones de los scripts

- **Numerados:** el orden es el procedimiento. No se saltean pasos.
- **Idempotentes cuando es posible:** volver a ejecutar no debería duplicar reglas.
- **Con verificación:** cada script comprueba lo que hizo antes de seguir.
- **Con salida legible:** los mensajes indican qué se está por cambiar.
- **Con reversión:** `99_restore_network.sh` vuelve la red al estado anterior.

Los scripts leen `config` con `source`. Por eso los valores no deben tener espacios
ni comillas. Si agregás una variable, documentala en `config.example` y en este
archivo.

## 4. Flujo de instalación

1. **Descarga y hash.** `01` no flashea: solo obtiene y verifica.
2. **TFTP.** `02` prepara dnsmasq y el servidor TFTP. Es el mismo camino de
   recuperación si el equipo queda sin arranque.
3. **Acceso.** `03` configura SSH con clave y revisa el firewall.
4. **Tor.** `04` instala, configura y persiste el hidden service.
5. **Web.** `05` apunta uhttpd a `www/` y a loopback.
6. **WiFi.** `06` crea el AP de administración.
7. **Verificación.** `07` comprueba el servicio y la página.
8. **Reversión.** `99` restaura la red.

## 5. Cómo agregar una página o un servicio

La página es estática: reemplazá `www/index.html` y listo. Si agregás assets,
mantené rutas relativas y evitá dependencias externas, porque el servicio onion no
debería necesitar CDNs.

Para un servicio nuevo, la regla es la misma: escuchar en loopback y publicarlo por
Tor. No agregues un puerto a la WAN. Si el servicio necesita estado, evaluá si el
router tiene recursos suficientes antes de instalar una base de datos.

## 6. Pruebas y verificación

No hay una suite automatizada. La verificación es de integración:

- El router arranca OpenWrt y responde por Ethernet.
- `tor` está activo y el hidden service tiene clave y hostname.
- uhttpd responde en `127.0.0.1:8080`.
- La página se ve desde la dirección `.onion`.
- El AP local entrega direcciones y permite administrar.
- `99` devuelve la red al estado inicial.

La bitácora `docs/BITACORA.md` registra decisiones y problemas reales. Si cambiás el
procedimiento, actualizala.

## 7. Riesgos conocidos

- **Flashear el modelo equivocado:** riesgo de ladrillo. Verificá v5 y arquitectura.
- **Perder la clave del hidden service:** cambia la dirección `.onion`.
- **Abrir uhttpd a la WAN:** anula el beneficio del diseño.
- **Contraseña débil:** el router es un punto de entrada a la red local.
- **Firmware sin actualizar:** Tor y OpenWrt reciben parches de seguridad.

## 8. Roadmap posible

- Agregar un script de respaldo del hidden service.
- Documentar la restauración completa desde cero.
- Incluir una página de estado que no dependa de Internet.

Nada de esto está implementado. El repositorio refleja el estado probado.

## 9. Licencia

MIT © 2026 jmadasme. OpenWrt, Tor y el firmware de TP-Link conservan sus licencias.
