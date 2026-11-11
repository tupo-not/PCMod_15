# AI_CONTEXT.md — контекст для будущих сессий (можно удалить перед публикацией; не входит в аддон, addon.txt собирает только lua/materials/models)

## Что это за проект

**PCMod** — аддон для Garry's Mod: компьютеры (tower/laptop/monitor и др. энтити `pcmod_*`),
свои ОС и программы (в т.ч. AlarmZ), 3D2D-экраны, сеть (роутеры/switch, IPv4+эмулированный IPv6),
wire-подобный тулган (`pcwire` и др.), install-диск. Lua в GLua-стиле (`//` комментарии, `!`, `!=`, `&&`, `||`, табы) — тесты прогоняют через транслятор в Lua 5.1.

## Где что лежит

- Рабочий репозиторий: **`D:\Programs\addons\PCmod_release\PCMod_15_main`**, ветка **`main`** (HEAD смотри `git log -1`).
- `D:\Programs\addons\PCmod_release\PCMod_15` — **ПУСТАЯ** папка (старая копия потеряна вместе с веткой `nemotron_dev`; не использовать).
- Задеплоенный аддон в игре: `D:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons\PCmod` — туда файлы копирует **пользователь**, сам не трогай без разрешения.
- Wiremod для справки: `D:\Programs\addons\Wiremod` (не менять!).

## Тесты

- `cd tests && ./run_tests.sh` (или через Git Bash: `%TEMP%\run_bg.sh` пишет лог в `%TEMP%\final_tests.log`).
- Нужны `lua5.1`/`luac5.1` в PATH: если `%TEMP%\luabin` исчез (Temp чистится), восстановить из `C:\Program Files (x86)\Lua\5.1\`: скопировать `lua.exe`→`lua5.1.exe`, `luac.exe`→`luac5.1.exe`, **и** extensionless-копии `lua5.1`/`luac5.1` (Python ищет точное имя), плюс `lua5.1.dll`/`lua51.dll`. Перед запуском: `$env:PATH = "$env:TEMP\luabin;" + $env:PATH`.
- Фикстуры транслируются в `tests/.build/` (не править руками); новые исходники добавлять в `tests/lib/build_fixtures.py` (FIXTURES = dofile, CHECK_ONLY = только синтаксис); новые suite — в список TESTS в `tests/run_tests.sh`.
- Текущие suite: `mock_alarmz` (окно Alarmz), `mock_alarmzlink` (сервер связей/паролей + клиент оверлея + stool + DrawLabel), остальные 40.

## Что сделано в этой сессии (ветка main)

- **Alarmz = монитор Wiremod RT-камер** (`gmod_wire_rt_camera`): `pr_alarmz.lua` (команды alarm + `selectcam`), `dev_win_alarmz.lua` (список только linked-камер, видео через материал `pcmod_alarmz_cam` + `cam.RenderTarget`, `SetIsObserved` lifecycle, PVS-grace, алерты, drag-safe панели, авто-выбор, восстановление выбора из `SelCam`).
- **Ручное подключение камер**: `sv_alarmz.lua` (реестр связей camera→PC, пароли камер = salted `util.SHA256`, owner = первый коннектор, authed-сессии, server-валидация дистанции/класса/VGA, очистка при удалении), `cl_alarmz.lua` (оверлей только с инструментом в руках, радиус `cfg.AlarmzOverlayRange = 200` (~5 м), E=connect (multi-PC), RMB=disconnect, окна паролей), stool `pc_camlink.lua` (вкладка «PCmod», LMB/RMB = E/RMB).
- **Clipboard/Quick Type**: кнопка «Clipboard» в lock-фрейме → текстовое окно, текст хранится на сервере per-SteamID (`pcmod_quicktype_save`), prefill из буфера если API есть (`GetClipboardText` guarded).
- **Lock-фрейм** = тёмное device-меню (шапка «PCMod», X, drag-**включен**, ряды Clipboard/Toggle Power, футер), шрифты `PCModMenu*`.
- **Фиксы**: `cl_gui.lua` DrawLabel больше не падает/не варнит на невалидном шрифте (реестр `PCMod.Gui.Fonts`); вкладка тулгана «PCmod».

## Правила работы

- Коммит после каждого логического изменения, маленькими частями, на `main` в `PCMod_15_main`. **Push — только с разрешения.**
- GMod **не запускать** самому; игру не тестировал — только mock-тесты + синтаксис.
- Не менять файлы Wiremod и папку игры; не публиковать в Workshop.
- Не переписывать системы целиком; расширять существующее. Вопросы к пользователю — когда неоднозначно.
