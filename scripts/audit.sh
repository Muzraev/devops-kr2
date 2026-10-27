#!/usr/bin/env bash

set -uo pipefail

PASS=0
FAIL=0

check() {
    local desc="$1"
    local expected="$2"
    local actual="$3"

    if [[ "$actual" == "$expected" ]]; then
        echo " [OK] $desc"
        ((PASS++))
    else
        echo " [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"
        ((FAIL++))
    fi
}

echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

echo
echo "[1] Служба SSH"

check \
    "Вход от имени root запрещён" \
    "no" \
    "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"

check \
    "Парольная аутентификация отключена" \
    "no" \
    "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"

SSH_PORT="$(sudo sshd -T | awk '/^port/{print $2}')"

if [[ "$SSH_PORT" != "22" ]]; then
    echo " [OK] Порт SSH отличается от 22"
    ((PASS++))
else
    echo " [FAIL] Порт SSH не должен быть 22"
    ((FAIL++))
fi

check \
    "MaxAuthTries равен 3" \
    "3" \
    "$(sudo sshd -T | awk '/^maxauthtries/{print $2}')"

echo
echo "[2] Межсетевой экран"

check \
    "Межсетевой экран активен" \
    "active" \
    "$(sudo ufw status | awk '/^Status:/{print $2}')"

INCOMING_POLICY="$(sudo ufw status verbose | awk '/^Default:/{print $2}')"

check \
    "Политика входящего трафика deny" \
    "deny" \
    "$INCOMING_POLICY"

echo
echo "[3] Учётные записи"

awk -F: '$3>=1000 && $3<65534 {
    printf " %s (uid=%s)\n", $1, $3
}' /etc/passwd

echo
echo "[4] Веб-сервер"

check \
    "Служба nginx активна" \
    "active" \
    "$(systemctl is-active nginx 2>/dev/null)"

NGINX_CONFIG="$(
    if sudo nginx -t >/dev/null 2>&1; then
        echo "ok"
    else
        echo "fail"
    fi
)"

check \
    "Конфигурация nginx синтаксически корректна" \
    "ok" \
    "$NGINX_CONFIG"

CERT_CHECKEND_SECONDS="${CERT_CHECKEND_SECONDS:-2592000}"

CERT_STATUS="$(
    if openssl x509 \
        -checkend "$CERT_CHECKEND_SECONDS" \
        -noout \
        -in /etc/ssl/certs/devops.crt >/dev/null 2>&1; then
        echo "ok"
    else
        echo "fail"
    fi
)"

check \
    "Сертификат действителен ещё минимум 30 дней" \
    "ok" \
    "$CERT_STATUS"

WRITABLE="$(
    find /var/www/devops-site -perm -o+w -print -quit 2>/dev/null
)"

KEY_MODE="$(
    sudo stat -c '%a' /etc/ssl/private/devops.key 2>/dev/null
)"

WEB_RIGHTS="$(
    if [[ -z "$WRITABLE" && "$KEY_MODE" == "600" ]]; then
        echo "safe"
    else
        echo "unsafe"
    fi
)"

check \
    "Права веб-ресурса и TLS-ключа безопасны" \
    "safe" \
    "$WEB_RIGHTS"

echo
echo "[5] Контейнеризация"

check \
    "Служба docker активна" \
    "active" \
    "$(systemctl is-active docker 2>/dev/null)"

check \
    "Контейнер СУБД находится в состоянии healthy" \
    "healthy" \
    "$(docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null)"

PORT_STATUS="$(
    ss -H -tln | awk '
        $4 ~ /:(5000|5432)$/ && $4 !~ /^127\.0\.0\.1:/ { bad = 1 }
        END { print bad ? "unsafe" : "safe" }
    '
)"

check \
    "Порты 5000 и 5432 не опубликованы вне 127.0.0.1" \
    "safe" \
    "$PORT_STATUS"

check \
    "Права файла /home/devops/app/.env равны 600" \
    "600" \
    "$(stat -c '%a' /home/devops/app/.env 2>/dev/null)"

echo
echo "[6] Контрольная работа № 2"

KR2_DIR="/home/devops/kr2"
REDIS_CONTAINER="$(docker compose --project-directory "$KR2_DIR" ps -q redis 2>/dev/null)"
REDIS_HEALTH="$(
    if [[ -n "$REDIS_CONTAINER" ]]; then
        docker inspect -f '{{.State.Health.Status}}' "$REDIS_CONTAINER" 2>/dev/null
    fi
)"
check "Redis находится в состоянии healthy" "healthy" "$REDIS_HEALTH"

KR2_PORT="$(docker compose --project-directory "$KR2_DIR" port app 8001 2>/dev/null)"
check "Порт 8001 опубликован только на 127.0.0.1" "127.0.0.1:8001" "$KR2_PORT"

check "Права файла /home/devops/kr2/.env равны 600" "600" \
    "$(stat -c '%a' "$KR2_DIR/.env" 2>/dev/null)"

KR2_CERT_STATUS="$(
    if openssl x509 -checkend 2592000 -noout -in /etc/ssl/certs/kr2.crt >/dev/null 2>&1; then
        echo ok
    else
        echo fail
    fi
)"
check "Сертификат kr2 действителен ещё минимум 30 дней" "ok" "$KR2_CERT_STATUS"

KR2_SITE_STATUS="$(
    if [[ -L /etc/nginx/sites-enabled/kr2 && -e /etc/nginx/sites-enabled/kr2 && "$(readlink -f /etc/nginx/sites-enabled/kr2)" == /etc/nginx/sites-available/kr2 ]]; then
        echo enabled
    else
        echo disabled
    fi
)"
check "Ресурс kr2 активирован символической ссылкой" "enabled" "$KR2_SITE_STATUS"

echo

echo "Пройдено: $PASS, не пройдено: $FAIL"

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
