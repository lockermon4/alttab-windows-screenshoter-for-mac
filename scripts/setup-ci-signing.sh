#!/usr/bin/env bash
# Один раз, для владельца репозитория.
# Делает ОДИН постоянный сертификат «QuickTab Dev» и для твоих локальных сборок, и для сборок на GitHub.
# Тогда у всех, кто скачивает QuickTab из Releases, разрешения не слетают при обновлении.
#
#   1. создаёт новый сертификат и ставит его в связку ключей (старый «QuickTab Dev» заменяется);
#   2. сохраняет его копию в ~/.quicktab-signing/ (повторный запуск возьмёт её, а не создаст новый);
#   3. кладёт его в секреты репозитория QUICKTAB_P12_BASE64 и QUICKTAB_P12_PASSWORD
#      (через `gh`, если он установлен и выполнен `gh auth login`; иначе подскажет, куда вставить руками).
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="QuickTab Dev"
REPO="${REPO:-lockermon4/alttab-windows-screenshoter-for-mac}"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"
DIR="${HOME}/.quicktab-signing"
P12="${DIR}/QuickTab-Dev.p12"
PASSFILE="${DIR}/password"

mkdir -p "${DIR}"
chmod 700 "${DIR}"

if [ -f "${P12}" ] && [ -f "${PASSFILE}" ]; then
    echo "Сертификат уже сохранён в ${DIR}, использую его."
    PASS=$(cat "${PASSFILE}")
else
    echo "Создаю новый сертификат «${NAME}»…"
    PASS=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32 || true)
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
    # Системный openssl (LibreSSL): его p12 гарантированно понимает `security import`.
    /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 7300 \
        -keyout "${TMP}/key.pem" -out "${TMP}/cert.pem" -config "${TMP}/cfg" 2>/dev/null
    /usr/bin/openssl pkcs12 -export -inkey "${TMP}/key.pem" -in "${TMP}/cert.pem" \
        -out "${P12}" -passout "pass:${PASS}" -name "${NAME}"
    cp "${TMP}/cert.pem" "${DIR}/cert.pem"
    printf '%s' "${PASS}" > "${PASSFILE}"
    chmod 600 "${P12}" "${PASSFILE}" "${DIR}/cert.pem"

    # Убираем старый «QuickTab Dev» (его ключ нигде не сохранён, поэтому его нельзя отдать GitHub).
    for _ in 1 2 3 4 5; do
        security find-certificate -c "${NAME}" "${KEYCHAIN}" >/dev/null 2>&1 || break
        security delete-identity -c "${NAME}" "${KEYCHAIN}" >/dev/null 2>&1 \
            || security delete-certificate -c "${NAME}" "${KEYCHAIN}" >/dev/null 2>&1 || break
    done

    security import "${P12}" -k "${KEYCHAIN}" -P "${PASS}" -T /usr/bin/codesign
    echo "Сейчас macOS спросит пароль, чтобы доверять сертификату для подписи кода."
    security add-trusted-cert -r trustRoot -p codeSign -k "${KEYCHAIN}" "${DIR}/cert.pem"

    # Подпись поменялась: старые записи о разрешениях больше не действуют.
    tccutil reset Accessibility local.quicktab >/dev/null 2>&1 || true
    tccutil reset ScreenCapture local.quicktab >/dev/null 2>&1 || true
    echo "Сертификат установлен."
fi

B64=$(base64 < "${P12}" | tr -d '\n')

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    printf '%s' "${B64}" | gh secret set QUICKTAB_P12_BASE64 -R "${REPO}"
    printf '%s' "${PASS}" | gh secret set QUICKTAB_P12_PASSWORD -R "${REPO}"
    echo "✅ Секреты QUICKTAB_P12_BASE64 и QUICKTAB_P12_PASSWORD загружены в ${REPO}."
else
    URL="https://github.com/${REPO}/settings/secrets/actions/new"
    echo
    echo "gh не найден или не выполнен вход (gh auth login), поэтому добавим секреты руками."
    echo "Откроется страница: ${URL}"
    printf '%s' "${B64}" | pbcopy
    open "${URL}" 2>/dev/null || true
    echo
    echo "1) Name: QUICKTAB_P12_BASE64"
    echo "   Secret: уже в буфере обмена — просто нажми ⌘V, затем «Add secret»."
    read -r -p "   Нажми Enter, когда добавишь первый секрет… " _
    printf '%s' "${PASS}" | pbcopy
    open "${URL}" 2>/dev/null || true
    echo "2) Name: QUICKTAB_P12_PASSWORD"
    echo "   Secret: уже в буфере обмена — ⌘V, затем «Add secret»."
    read -r -p "   Нажми Enter, когда добавишь второй секрет… " _
    printf '' | pbcopy
    echo "✅ Готово."
fi

echo
echo "Дальше:"
echo "  ./scripts/build-app.sh --install   — пересобрать у себя с новым сертификатом"
echo "  и один раз заново выдать QuickTab «Универсальный доступ» и «Запись экрана»."
