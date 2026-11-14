#!/usr/bin/env bash
# Один раз создаёт личный сертификат подписи «QuickTab Dev» в связке ключей.
# С ним подпись приложения не меняется между сборками, и macOS
# не сбрасывает «Универсальный доступ» / «Запись экрана» после каждой пересборки.
set -euo pipefail
NAME="QuickTab Dev"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

if security find-certificate -c "${NAME}" "${KEYCHAIN}" >/dev/null 2>&1; then
    echo "Сертификат «${NAME}» уже есть."
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
cat > "${TMP}/cfg" <<CFG
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = ${NAME}
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CFG

# Системный openssl (LibreSSL) — его p12 гарантированно понимает `security import`.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "${TMP}/key.pem" -out "${TMP}/cert.pem" -config "${TMP}/cfg" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "${TMP}/key.pem" -in "${TMP}/cert.pem" \
    -out "${TMP}/id.p12" -passout pass:quicktab -name "${NAME}"

security import "${TMP}/id.p12" -k "${KEYCHAIN}" -P quicktab -T /usr/bin/codesign
echo "Сейчас macOS спросит пароль, чтобы доверять сертификату для подписи кода."
security add-trusted-cert -r trustRoot -p codeSign -k "${KEYCHAIN}" "${TMP}/cert.pem"

# Убираем старые записи от ad-hoc сборок, чтобы они не мешали.
tccutil reset Accessibility local.quicktab >/dev/null 2>&1 || true
tccutil reset ScreenCapture local.quicktab >/dev/null 2>&1 || true

echo "Готово. Теперь собирай как обычно: ./scripts/build-app.sh --install"
