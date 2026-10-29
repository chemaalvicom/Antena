# Antena — reproductor IPTV propio para iPhone y iPad

App propia en SwiftUI para ver listas IPTV (M3U/M3U8 y Xtream Codes). Sin publicidad, sin Facebook/Adjust ni ningún rastreo. Todo se guarda en el propio iPhone.

## Qué hace (v1.0)

- **Listas**: añadir por URL M3U, por cuenta **Xtream Codes** (servidor + usuario + contraseña) o importando un archivo `.m3u`. Varias listas, renombrar, reordenar, actualizar (deslizar o tirar hacia abajo).
- **Navegación**: Lista → Grupos (con nº de canales) → Canales, con logos. Búsqueda en toda la lista o dentro de un grupo.
- **Favoritos** (deslizar el canal) y **Recientes** (últimos 40).
- **Doble motor de reproducción**:
  - **Apple (AVPlayer)** para HLS `.m3u8`: AirPlay nativo, Picture in Picture, audio en segundo plano.
  - **VLC (MobileVLCKit)** para todo lo demás (MPEG-TS, MKV, RTMP…).
  - Modo automático, o forzar uno en Ajustes. Desde el menú ⋯ del reproductor se cambia de motor al vuelo si un canal no arranca.
- Respeta `#EXTVLCOPT:http-user-agent`, `http-referrer` y la sintaxis Kodi `url|User-Agent=…`.
- **Ajustes**: User-Agent global con predefinidos (VLC, Safari, Kodi), búfer de VLC, tema (oscuro/claro/sistema) y color de acento.
- Rotación libre, iPhone e iPad, iOS 17+.

## Compilar sin Mac (igual que AutomationCenter)

1. Crea un repositorio **privado** en GitHub (por ejemplo `Antena`) y sube el contenido de esta carpeta:
   ```bash
   git init && git add . && git commit -m "Antena 1.0"
   git branch -M main
   git remote add origin https://github.com/<tu-usuario>/Antena.git
   git push -u origin main
   ```
2. El workflow **Compilar IPA** arranca solo (o desde *Actions → Compilar IPA → Run workflow*). Tarda unos 10–15 min la primera vez (descarga VLC).
3. Descarga el artefacto `Antena-ipa`, descomprime y obtendrás `Antena.ipa` **sin firmar**.
4. Fírmala e instálala con **ESign** usando tu certificado de Apple Developer.

## Personalizar

| Qué | Dónde |
|---|---|
| Nombre bajo el icono | `project.yml` → `CFBundleDisplayName` |
| Bundle ID | `project.yml` → `PRODUCT_BUNDLE_IDENTIFIER` (y `bundleIdPrefix`) |
| Versión | `project.yml` → `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` |
| Icono | sustituye `Antena/Resources/Assets.xcassets/AppIcon.appiconset/icon.png` (1024×1024, sin transparencia) |
| Colores de acento | `Antena/Core/Models.swift` → `enum Accent` |
| User-Agent por defecto | `Antena/Core/Models.swift` → `Defaults.userAgent` |
| Motor automático (qué va a VLC) | `Antena/Player/Player.swift` → `useVLC` |

## Estructura

```
project.yml                  Proyecto XcodeGen (Info.plist incluido)
Podfile                      MobileVLCKit 3.6
.github/workflows/           CI que genera la IPA sin firmar
Antena/App/                  Punto de entrada y pestañas
Antena/Core/                 Modelos, lector M3U y almacenamiento
Antena/Views/                Listas, grupos, canales, favoritos, recientes, ajustes
Antena/Player/               Reproductor Apple + VLC + AirPlay
```

## Ideas para siguientes versiones

- Guía de programación (EPG XMLTV) con "ahora / a continuación".
- Chromecast (Google Cast SDK).
- Películas y series de Xtream (VOD) con carátulas.
- Widget de canales favoritos y CarPlay (audio).
