# Dzas0wgramm

Минимальный iOS-клиент Telegram (SwiftUI + TDLibKit), собирается
автоматически в облаке через GitHub Actions — свой Mac не нужен.

## Как получить .ipa

1. Создайте новый репозиторий на GitHub (можно приватный) и загрузите
   в него содержимое этой папки целиком (сохранив структуру папок,
   включая `.github/workflows/build-ipa.yml`).
2. Впишите свои `apiId` и `apiHash` в файл
   `Sources/Dzas0wgramm/TelegramApp.swift` (получить на
   https://my.telegram.org -> API development tools).
3. На странице репозитория откройте вкладку **Actions**.
4. Выберите workflow **Build Dzas0wgramm .ipa** и нажмите
   **Run workflow** (или просто сделайте `git push` в ветку `main` —
   сборка запустится сама).
5. Сборка идёт 5-10 минут. Когда она закончится зелёной галочкой,
   откройте её и в разделе **Artifacts** внизу страницы скачайте
   `Dzas0wgramm-ipa.zip`. Внутри — файл `Dzas0wgramm.ipa`.

## Как установить .ipa на iPhone через Windows

`.ipa` из этой сборки не подписан (своего платного Apple Developer
аккаунта не нужно). Установить его можно одним из инструментов,
которые сами подписывают приложение бесплатным Apple ID при заливке
на телефон:

- **Sideloadly** (https://sideloadly.io) — Windows-программа,
  подключаете iPhone по кабелю, указываете `.ipa`, входите с Apple ID.
- **AltStore** (https://altstore.io) — ставите AltServer на Windows,
  через AltStore на телефоне устанавливаете `.ipa`.

Ограничение бесплатного Apple ID: приложение нужно переустанавливать
(или переподписывать через AltServer) раз в 7 дней.

## Если сборка упала с ошибкой

- Чаще всего дело в версии **TDLibKit** в `project.yml`
  (`packages.TDLibKit.from`) — откройте
  https://github.com/Swiftgram/TDLibKit и укажите актуальный тег
  версии.
- Версия Xcode в workflow (`Xcode_15.4.app`) должна быть доступна на
  раннере `macos-14`; список доступных версий — на странице
  https://github.com/actions/runner-images/blob/main/images/macos/macos-14-Readme.md
