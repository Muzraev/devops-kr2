# Контрольная работа 2 Вариант 1

Flask-приложение из [шаблона курса](https://gitverse.ru/dgimatdinov/kr2-template)
развёрнуто с Redis 7 и опубликовано через Nginx по HTTPS.

- Домен: `api.devops.local`.
- Порт приложения на сервере: `127.0.0.1:8001`.
- Redis доступен только в сети Compose `backend`, без публикации порта 6379.
- Счётчик хранится в томе `redis_data`, включён AOF.
- Приложение и Redis работают с UID 999; политика перезапуска `unless-stopped`.
- Ветка решения: `kr2/variant-1`. Pull Request остаётся открытым до защиты.

## Файлы

`Dockerfile` использует точный digest образа Python из практики 7, устанавливает
зависимости отдельным слоем и запускает Gunicorn в exec-форме от пользователя app.
Логика `app.py` и состав `requirements.txt` сохранены. В `app.py` добавлен только
комментарий `# KR2: Muzraev`.

`docker-compose.yml` описывает приложение, Redis, сеть, том, парольную
аутентификацию, healthcheck и ожидание готовности Redis.

`nginx/kr2` — отдельный виртуальный хост. Старый `devops-site` не меняется.
Сертификат имеет SAN `DNS:api.devops.local`, ключ принадлежит root и имеет права 600.

`scripts/audit.sh` сохраняет проверки предыдущих работ и добавляет раздел 6:
готовность Redis, loopback-публикация порта, права `.env`, срок сертификата и
символическая ссылка сайта. Контейнер Redis определяется по имени сервиса.

## Доставка и запуск

На хосте, из каталога проекта:

```bash
rsync -avz --exclude=.env --exclude=.git --chmod=D755,F644 --dry-run ./ devops:kr2/
rsync -avz --exclude=.env --exclude=.git --chmod=D755,F644 ./ devops:kr2/
```

На сервере создаётся новый пароль. `.env` не копируется с хоста и не включается
в Git или контекст сборки. Не выводите его значение и результат `compose config`
или полную конфигурацию Redis через `inspect` в отчёт.

```bash
cd ~/kr2
umask 077
printf 'REDIS_PASSWORD=%s\n' "$(openssl rand -hex 16)" > .env
chmod 600 .env
unset REDIS_PASSWORD
docker compose up -d --build --wait --wait-timeout 120
```

Генерация выполняется один раз: существующий `.env` при последующей доставке
сохраняется. Переменная `REDIS_PASSWORD` не должна быть экспортирована в оболочке:
иначе подстановка `${...}` может разойтись с содержимым `env_file`.

## HTTPS

В Windows hosts имя сопоставлено адресу Host-only `192.168.56.102`.
В среде WSL, откуда выполняются проверки, добавлено то же сопоставление.

```bash
sudo openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
  -keyout /etc/ssl/private/kr2.key -out /etc/ssl/certs/kr2.crt \
  -subj '/CN=api.devops.local' -addext 'subjectAltName=DNS:api.devops.local'
sudo chmod 600 /etc/ssl/private/kr2.key
sudo cp nginx/kr2 /etc/nginx/sites-available/kr2
sudo ln -s /etc/nginx/sites-available/kr2 /etc/nginx/sites-enabled/kr2
sudo nginx -t
sudo systemctl reload nginx
```

Эти команды установки применяются при первом развёртывании; существующие ключи
и конфигурацию перед повторной установкой нужно проверить. Правила UFW не менялись.

## Проверка

```bash
docker compose ps
docker compose top
docker compose exec -T app getent hosts redis
docker compose exec -T redis redis-cli ping  # NOAUTH без пароля
docker compose port app 8001                # 127.0.0.1:8001
docker compose port redis 6379              # :0, порт не опубликован
sudo bash scripts/audit.sh                  # 19 успешно, код 0
```

На хосте:

```bash
scp devops:/etc/ssl/certs/kr2.crt ~/kr2.crt
curl -I http://api.devops.local/                   # 301 на HTTPS
curl -I https://api.devops.local/                  # ошибка проверки сертификата
curl --cacert ~/kr2.crt https://api.devops.local/
curl --cacert ~/kr2.crt https://api.devops.local/whoami
curl --cacert ~/devops.crt -I https://devops.local/
curl --cacert ~/devops.crt https://devops.local/app/
curl -m 3 http://api.devops.local:8001/health       # прямой доступ закрыт
```

В `/whoami` получены `scheme: https`, `client: 192.168.56.1`,
`host: api.devops.local`. Адрес клиента передаёт Nginx в `X-Real-IP`;
TCP-соединение приложения приходит от обратного прокси.

Подтверждено: после `down` без `-v` счётчик продолжился с 4 до 5. После
выключения и ручного включения сервера оба проекта запустились автоматически,
новое приложение вернуло hits 7. Дополнительный аудит вернул коды 0, 1 и 0:
ошибочная публикация `8001:8001` обнаружена, затем восстановлена
`127.0.0.1:8001:8001`. Итог — 19 успешных проверок, правила UFW не изменены.

Созданы снимки `06-before-kr2` и `07-kr2`. Секрет из исходного шаблона остался
только в унаследованной истории; действующий пароль сгенерирован заново на сервере.
