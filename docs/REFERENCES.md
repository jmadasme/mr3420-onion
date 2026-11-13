# Referencias · MR3420 Onion

Documentación externa que se usó para entender el hardware, los protocolos y las
libertades del proyecto. No es una bibliografía decorativa: cada enlace apunta a
la fuente que explica una decisión concreta.

## Fuentes técnicas

| Fuente | Para qué se consultó |
|---|---|
| [OpenWrt](https://openwrt.org/docs/start) | Sistema, paquetes y recuperación. |
| [TL-MR3420](https://openwrt.org/toh/tp-link/tl-mr3420) | Página de dispositivo y soporte. |
| [TFTP recovery](https://openwrt.org/docs/guide-user/troubleshooting/tftpserver) | Recuperación por TFTP y dnsmasq. |
| [Tor onion services](https://community.torproject.org/onion-services/) | Publicación de servicios v3. |

## Versiones de este repositorio

`mr3420-onion-server`

Cada carpeta puede tener dependencias y versiones distintas. Cuando el código
depende de una versión específica, esa versión está declarada en el README o en
el archivo de configuración de la carpeta, no en este documento.

## Criterio de preservación

- El código y los documentos se copiaron desde la carpeta original de trabajo.
- Se excluyeron `.git`, dependencias instaladas, compilados, registros y bases
  de datos locales.
- Se redactaron tokens, claves privadas y contraseñas detectadas en texto.
- Las plantillas `.example`, `.sample` y los valores de demostración se
  conservan porque documentan la configuración esperada.

## Limitaciones conocidas

Publicar un servicio desde una red doméstica expone la IP y depende de un port forwarding que casi nadie configura bien.

La documentación de cada versión describe el alcance real. Si una función no
está implementada, se dice; si un hardware no fue probado, también.
