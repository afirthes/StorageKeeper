# StorageKeeper iOS

SwiftUI-клиент для StorageKeeper, работающий через backend API.

## Возможности

- Иерархия контейнеров.
- Вещи внутри контейнеров.
- Квадратные фото контейнеров и вещей.
- Обрезка фото перед загрузкой.
- Иерархические теги.
- Поиск через backend API по названию, описанию и тегам.
- Авторизация через backend.
- Раздел настроек для адреса сервера, логина, пароля и проверки подключения.

## Хранение данных

SwiftData больше не используется. Источник данных - backend:

```text
iOS -> API -> backend -> DB/S3
```

Локально сохраняются только:

- адрес сервера и логин в `UserDefaults`;
- пароль, access token и refresh token в Keychain.

## Подключение

Откройте вкладку `Настройки` и укажите адрес сервера, например:

```text
https://your-domain.ru
```

Для временного теста можно использовать HTTP/IP:

```text
http://195.63.144.27
```

В `Info.plist` временно разрешен HTTP через App Transport Security. Для постоянного использования лучше перевести сервер на HTTPS и убрать это разрешение.

## Run

Open `StorageKeeper.xcodeproj` in Xcode, choose the `StorageKeeper` scheme, and run it on an iPhone simulator or device.

The app targets iOS 17.0+.
