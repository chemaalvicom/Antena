# ANTENA PRO · firma en GitHub Actions y puesta en marcha

ANTENA PRO lleva una extensión de VPN (Packet Tunnel). iOS solo deja activarla si la app
y la extensión están firmadas con perfiles que incluyen el permiso **Network Extensions**,
cada una con su Bundle ID. ESign firma todo con un único perfil, así que **esta IPA se
firma en GitHub Actions** y se instala tal cual.

Todo lo de abajo se hace una sola vez. Nada de esto se sube al repositorio: el certificado
y los perfiles van como *secrets* cifrados de GitHub.

## 1. Portal de Apple Developer (developer.apple.com › Certificates, IDs & Profiles)

### 1.1 App Group
*Identifiers* › **+** › **App Groups** › Continue
- Description: `ANTENA PRO`
- Identifier: `group.com.chemablanco.antenapro`

### 1.2 App ID de la app
*Identifiers* › **+** › **App IDs** › **App**
- Description: `ANTENA PRO`
- Bundle ID (Explicit): `com.chemablanco.antenapro`
- Capabilities: marca **App Groups** y **Network Extensions**
- Guarda, vuelve a entrar en el App ID › *App Groups* › **Configure** › marca `group.com.chemablanco.antenapro` › Save

### 1.3 App ID de la extensión
Igual que el anterior:
- Description: `ANTENA PRO Tunnel`
- Bundle ID (Explicit): `com.chemablanco.antenapro.tunnel`
- Capabilities: **App Groups** (el mismo grupo) y **Network Extensions**

### 1.4 Tu iPhone
*Devices* › **+** › nombre y **UDID** del iPhone.
En Windows: conecta el iPhone, abre iTunes › icono del iPhone › *Resumen* y pulsa sobre
*Número de serie* hasta que aparezca el UDID (clic derecho para copiarlo).

### 1.5 Certificado de distribución
Si ya tienes un `.p12` de tipo **Apple Distribution** (por ejemplo el que usas con ESign) y
su contraseña, sáltate este paso. Si no, en Git Bash:

```bash
openssl genrsa -out distribucion.key 2048
openssl req -new -key distribucion.key -out distribucion.csr -subj "/CN=Chema Blanco/C=ES"
```

*Certificates* › **+** › **Apple Distribution** › sube `distribucion.csr` › descarga
`distribution.cer` y conviértelo a `.p12`:

```bash
openssl x509 -in distribution.cer -inform DER -out distribution.pem -outform PEM
openssl pkcs12 -export -legacy -inkey distribucion.key -in distribution.pem \
  -out distribucion.p12 -passout pass:PON_AQUI_UNA_CONTRASEÑA
```

(Si `-legacy` da error, tu OpenSSL es antiguo: quítalo.) Guarda `distribucion.key` y el
`.p12` en un sitio seguro y **fuera del repo**.

### 1.6 Perfiles Ad Hoc (dos)
*Profiles* › **+** › **Ad Hoc** (en *Distribution*):
1. App ID `com.chemablanco.antenapro` › tu certificado › tu iPhone › nombre `ANTENA PRO AdHoc`
2. App ID `com.chemablanco.antenapro.tunnel` › tu certificado › tu iPhone › nombre `ANTENA PRO Tunnel AdHoc`

Descarga los dos `.mobileprovision`.

## 2. Secrets en GitHub

Repositorio › *Settings* › *Secrets and variables* › *Actions* › **New repository secret**.
Para pasar un archivo a base64 en PowerShell (queda copiado en el portapapeles):

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\ruta\archivo")) | Set-Clipboard
```

| Secret | Contenido |
|---|---|
| `CERT_P12_BASE64` | el `.p12` en base64 |
| `CERT_PASSWORD` | la contraseña del `.p12` |
| `APP_PROFILE_BASE64` | `ANTENA PRO AdHoc` en base64 |
| `TUNNEL_PROFILE_BASE64` | `ANTENA PRO Tunnel AdHoc` en base64 |

El equipo (Team ID) y los nombres de los perfiles los lee el workflow de los propios perfiles.

## 3. Compilar e instalar

*Actions* › **Compilar ANTENA PRO** › *Run workflow* (rama `antena-pro`). Tarda 15–20 min la
primera vez. La IPA firmada sale en *Releases* como `AntenaPro.ipa`.

Instálala **sin volver a firmarla** (por ejemplo con 3uTools desde Windows). Si la firmas
con ESign, la VPN dejará de funcionar.

Sin los secrets, el workflow compila igualmente pero **sin firmar**: sirve para comprobar
que el código compila, no para usar la VPN.

## 4. Servidor: configuración nueva para ANTENA PRO

La configuración de prueba (`iphone.conf`) apareció en una captura, así que ANTENA PRO usa
claves nuevas y la antigua se revoca. En la VM (`ssh opc@129.151.242.203`):

```bash
sudo bash -c '
set -e
cd /etc/wireguard && umask 077
wg genkey | tee antenapro.key | wg pubkey > antenapro.pub
wg set wg0 peer "$(cat antenapro.pub)" allowed-ips 10.66.66.3/32
wg set wg0 peer "$(cat iphone.pub)" remove
wg-quick save wg0
cat > antenapro.conf <<EOF
[Interface]
PrivateKey = $(cat antenapro.key)
Address = 10.66.66.3/32
DNS = 1.1.1.1, 9.9.9.9
MTU = 1380

[Peer]
PublicKey = $(cat server.pub)
Endpoint = 129.151.242.203:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
wg show
'
sudo qrencode -t ansiutf8 < /etc/wireguard/antenapro.conf
```

Abre ANTENA PRO, pulsa **Configurar VPN** y escanea ese QR (sin hacerle capturas). iOS
pedirá permiso para *Añadir configuraciones VPN*: acéptalo. A partir de ahí la VPN se
levanta sola cada vez que abras la app.

Después de esto la configuración de la app oficial de WireGuard deja de funcionar
(su clave se ha revocado): puedes borrarla.

## 5. TestFlight: sin QR, sin archivos, sin PC

Con perfiles **App Store** (en lugar de Ad Hoc) el workflow sube cada versión a TestFlight y
mete dentro de la app la configuración de la VPN. Al abrirla la primera vez solo hay que
aceptar el aviso de iOS «Añadir configuraciones VPN».

Secrets adicionales:

| Secret | Contenido |
|---|---|
| `WG_CONFIG` | el texto completo de `/etc/wireguard/antenapro.conf` del servidor |
| `ASC_KEY_ID` | Key ID de la clave de API de App Store Connect |
| `ASC_ISSUER_ID` | Issuer ID (arriba de la lista de claves) |
| `ASC_KEY_P8` | el contenido del archivo `AuthKey_XXXX.p8` (texto, desde `-----BEGIN` hasta `END-----`) |

Y `APP_PROFILE_BASE64` / `TUNNEL_PROFILE_BASE64` pasan a ser los perfiles de tipo **App Store**.

Seguridad: el workflow **solo** incluye `WG_CONFIG` en builds de TestFlight (privadas de tu
cuenta) y en ese caso no publica ninguna IPA en *Releases* ni como artefacto.

Para cambiar las claves de la VPN basta con actualizar `WG_CONFIG` y lanzar el workflow: la
versión nueva sustituye la configuración guardada en el iPhone al abrirse.
