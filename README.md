# images-srv-test
Image tools microservice:

## Настройки:

```
# .env
PUBLIC_DIR=/var/www/public	# общедоступная папка для хранения картинок
BACK_HOST=http://localhost:3000	# URL бэкенда с аутентификацией
DAEMON=yes	# run as daemon
PORT=3333	# tcp/ip port binding
```
```
# config/app.rb
set :resources, [ 'models', 'vehicles' ]	# ресурсы для которых будут храниться картинки
```
## Загрузка картинок (role: admin):

POST запросом отправлять форму с action:
```
http://<hostname>/images/<resource>/<id>/upload
```
Так же есть простенькая форма для тестов через GET запрос

## Список всех картинок на сервере (role: admin):

GET запрос:
```
http://<hostname>/images
```
Выведет список всех картинок на сервере в JSON формате.
