# AxOS

> **Не путать с AxOS — дистрибутивом Linux на базе Arch.** Этот проект с ним
> никак не связан: здесь нет ни Linux, ни чужого ядра — всё написано с нуля,
> от загрузчика до собственного процессора.

AxOS — мой личный проект: операционная система, которую я пишу с нуля, и
железо, на котором она могла бы работать. Внутри три части:

- **ОС AxOS** (`src/`) — на Assembler и C, с двумя независимыми портами:
  **x86-64** (свой загрузчик проходит весь путь real mode → protected mode →
  long mode) и **RISC-V (rv64)** под OpenSBI/QEMU `virt`. Прерывания,
  многоуровневая страничная память, пользовательский режим, вытесняющий
  планировщик с приоритетами, FAT12, сетевой стек TCP/IP и графический
  интерфейс с окнами — всё это можно проверить вживую в QEMU.
- **AxISA** (`hardware/axisa_core/`) — моя собственная 32-битная архитектура
  набора команд, построенная на квантовой хромодинамике: банки регистров —
  цвета кварков, 8 настоящих глюонов, адроны со своими квантовыми числами,
  асимптотическая свобода, умножение на матрицы SU(3), как в решёточной КХД.
  А ещё аппаратные теги памяти в духе ARM MTE и hardened malloc, написанный
  на её ассемблере. Процессор на Verilog, свой ассемблер, симуляции в CI,
  синтез под sky130 через OpenLane. Спецификация:
  [`hardware/axisa_core/docs/ISA.md`](hardware/axisa_core/docs/ISA.md).
- **RV32I-процессор** (`hardware/rv32i_core/`) — RISC-V ядро на Verilog:
  5-стадийный конвейер, FPU, MMU с TLB и многоядерные сети на кристалле
  (NoC), вплоть до 3D- и 4D-мешей.

Подробно про каждую часть — в [вики проекта](https://github.com/mdudnikov82-beep/AxOS/wiki) (таблица ниже).

## Возможности

**Общее для обеих архитектур:**
- Вытесняющий планировщик с приоритетами (`nice <pid> <1-10>`) — приоритет
  определяет, сколько последовательных тиков таймера задача удерживает CPU
  за один заход по кольцу (weighted round-robin, не строгие уровни)
- Куча с усилением в духе hardened_malloc/ARM MTE: 64-битный tag+redzone
  (детект underflow) + канарейка + карантин из последних `free()`
- FAT12 файловая система (чтение и запись, изменения переживают перезапуск)
- Интерактивный shell с внешними программами, конвейерами и фоновыми задачами

**x86-64:**
- Собственный загрузчик: реальный режим (16 бит) → защищённый режим
  (32 бита) → **long mode** (64 бита): `CR4.PAE` → `EFER.LME` → `CR0.PG`,
  far jump в 64-битный сегмент кода
- GDT с 64-битным TSS, кольцами 0 и 3 (ring3 — 32-битный compatibility mode)
- IDT (64-битные врата, 16 байт на запись): таймер PIT (IRQ0, 100 Гц),
  клавиатура (IRQ1), `#PF`, `int 0x80` (системные вызовы)
- Страничная память: полная 4-уровневая адресация (PML4→PDPT→PD→PT),
  identity-map первых 4 МБ, `NX`/`SMEP`/`SMAP`, постраничный W^X для
  пользовательских программ, `.text` ядра read-only, `CR0.WP`
- GCC `-fstack-protector-strong` для ядра (64-битная канарейка) поверх уже
  имевшегося userspace-стек-протектора
- Пользовательский режим (ring3, 32-битный compat mode): переход через
  `iretq`, обратно в ring0 — через `int 0x80` и TSS
- Куча ядра: 32 МБ (`0x400000`+, 2МБ huge pages), поверх — MTE-style
  усиление (см. выше)
- Preemptive планировщик (IRQ0): задачи ring0 и ring3, у каждой свой стек и
  свой стек ядра (per-task `TSS.RSP0`), с приоритетами (`nice`)
- MAC (Type Enforcement в духе SELinux) + MLS-уровни чувствительности

**RISC-V (rv64):**
- S-mode ядро под OpenSBI (QEMU `virt`), U-mode пользовательские процессы,
  Sv39 страничная адресация с W^X-хардненным ядром и приватными таблицами
  на процесс (изоляция)
- Драйверы virtio: блочное устройство, GPU (framebuffer), input (клавиатура
  и мышь)
- Собственный shell AxSH (`run`/`kill`/`nice`/`ps`/файловые команды) и
  набор пользовательских программ (текстовый редактор, рисовалка, тесты кучи
  и др.) — см. [Порт RISC-V](https://github.com/mdudnikov82-beep/AxOS/wiki/RISC-V-Port) в вики

## Технологии

- Языки: Assembler (NASM для x86, GNU `as`/GAS для RISC-V), C
- Среда: Windows + `w64devkit` (MinGW: gcc/ld/objcopy, x86-64) и отдельный
  `riscv64-unknown-elf`-тулчейн (`riscv-gcc/`, RISC-V)
- Инструменты: NASM (`tools/nasm.exe`), Python (генерация образов FAT12 —
  `tools/make_fat12.py`/`make_fat12_rv64.py`), QEMU
  (`qemu-system-x86_64`/`qemu-system-riscv64`)
- Архитектуры: x86-64 (long mode, ring3 — 32-битный compat mode) и
  RISC-V rv64 (S-mode/U-mode, Sv39)

## Быстрый старт

### x86-64

Сборка (Windows, из корня репозитория):

```bat
build.bat
```

`build.bat` сам подставляет `w64devkit\bin` в `PATH`, собирает все
ассемблерные и C-файлы (ядро — `gcc -m64`, long mode; пользовательские
программы — `gcc -m32`, ring3 compatibility mode), линкует их в
`build\kernel.bin` и склеивает `build\boot.bin` + `build\kernel.bin` в
`build\os-image.bin` (дискета 1.44 МБ). Отдельно генерирует FAT12-образ из
содержимого `fs/` (`tools/make_fat12.py`) и записывает его в первые 256 КБ
`build\disk.img` (10 МБ, физический диск IDE).

Запуск в QEMU:

```bat
run.bat
```

или вручную:

```bat
qemu-system-x86_64 -drive format=raw,file=build\os-image.bin,if=floppy -boot a ^
  -drive format=raw,file=build\disk.img,if=ide,index=0,media=disk -cpu Broadwell
```

**Важно**: нужен именно `qemu-system-x86_64`, а не `qemu-system-i386` — с
переходом ядра на long mode образу требуется `EFER.LME`, которого нет у
`i386`-эмулятора. Флаг `-cpu Broadwell` обязателен: без него QEMU не
подставит SMAP (используется для харднинга страничной памяти, см.
"Архитектура" ниже) — на CPU без SMAP ядро тоже загрузится (детектирует
поддержку через CPUID и просто не включит соответствующий бит CR4), но
часть демонстраций харднинга не будет иметь эффекта.

После загрузки автоматически запускается AxSH (`SH.BIN`, полноценный
Unix-подобный shell с конвейерами и фоновыми задачами — см. "Команды
shell") и появится приглашение `$ ` — наберите `help`, чтобы увидеть
список встроенных команд.

### RISC-V (rv64)

Независимый порт под QEMU `virt`/OpenSBI, живёт в `src/arch/riscv64/` +
`src/user/rv64/`, собирается отдельным скриптом:

```bat
build_riscv.bat
```

Требует отдельный тулчейн `riscv64-unknown-elf`-типа (в этом репозитории —
`riscv-gcc/`, xPack RISC-V GCC). Собирает ядро (`gcc -march=rv64imac_zicsr
-mabi=lp64 -mcmodel=medany`) и ~20 пользовательских ELF-программ, кладёт их
в `rv64build\fs\rv64\` и генерирует `rv64build\disk.img` через
`tools\make_fat12_rv64.py`.

Запуск в QEMU (нужны virtio-блок/GPU/клавиатура/планшет-мышь; сеть
опциональна — без неё `virtio_net_init()` просто не находит устройство и
`SYS_NET_*` безобидно отдают -1/0):

```bat
qemu-system-riscv64 -M virt -bios default -kernel rv64build\out\kernel.elf ^
  -drive file=rv64build\disk.img,if=none,id=hd0,format=raw ^
  -device virtio-blk-device,drive=hd0 -device virtio-gpu-device ^
  -device virtio-keyboard-device -device virtio-tablet-device ^
  -netdev user,id=net0 -device virtio-net-device,netdev=net0
```

После загрузки — приглашение AxSH/RV64 (`src/user/rv64/axsh.c`), команда
`help` печатает список.

## Подробности — в вики

Полное описание того, как всё устроено, живёт в [вики проекта](https://github.com/mdudnikov82-beep/AxOS/wiki):

| Страница | О чём |
|----------|-------|
| [Архитектура x86-64](https://github.com/mdudnikov82-beep/AxOS/wiki/x86-64-Architecture) | загрузка до long mode, GDT/IDT, страничная память, ring3, куча, планировщик, `fork()`, pipes, FAT12, ELF |
| [Карта памяти и KASLR/ASLR](https://github.com/mdudnikov82-beep/AxOS/wiki/Memory-Map-and-KASLR) | адресное пространство и рандомизация на обеих платформах |
| [Shell AxSH](https://github.com/mdudnikov82-beep/AxOS/wiki/Shell) | команды, буфер обмена, цвета |
| [MAC и MLS](https://github.com/mdudnikov82-beep/AxOS/wiki/MAC-and-MLS) | Type Enforcement в духе SELinux и уровни секретности |
| [Сетевой стек](https://github.com/mdudnikov82-beep/AxOS/wiki/Network-Stack) | ARP, IPv4/ICMP, UDP, DHCP, TCP, DNS, HTTP |
| [Порт RISC-V](https://github.com/mdudnikov82-beep/AxOS/wiki/RISC-V-Port) | S-mode ядро, Sv39, virtio, GUI, звук, сеть |
| [AI-демо](https://github.com/mdudnikov82-beep/AxOS/wiki/AI-Demo) | нейросеть внутри ОС |
| [AxISA](https://github.com/mdudnikov82-beep/AxOS/wiki/AxISA) | собственная архитектура процессора на тему КХД |
| [RV32I-процессор](https://github.com/mdudnikov82-beep/AxOS/wiki/RV32I-Core) | RISC-V ядро на Verilog: конвейер, FPU, MMU, NoC |
| [Структура репозитория](https://github.com/mdudnikov82-beep/AxOS/wiki/Repository-Structure) | что где лежит, формат образа |
| [Статус и планы](https://github.com/mdudnikov82-beep/AxOS/wiki/Status-and-Roadmap) | что готово и что дальше |
| [CI](https://github.com/mdudnikov82-beep/AxOS/wiki/CI) | что проверяет GitHub Actions |

## Контрибьюции

Подробное руководство для контрибьюторов доступно в [`CONTRIBUTING.md`](CONTRIBUTING.md).

Кратко:
1. Сделайте форк репозитория.
2. Создайте ветку по шаблону `feature/имя` или `fix/имя`.
3. Добавьте описание изменений и, если меняли ядро, проверьте `build.bat` и
   проверку в QEMU (`run.bat`).

### Стиль и требования

- Assembler: NASM-style, `[bits 32]`/`[bits 16]` явно, комментарии на русском
  для нетривиальных мест (по аналогии с `paging.c`/`heap.c`).
- C: совместимость с `gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx`
  (см. флаги в `build.bat`). Без libc — только то, что реализовано в самом
  ядре.
- Перед PR: убедитесь, что `build.bat` проходит без ошибок и `kernel.bin`
  не превышает 45568 байт (лимит — 89 секторов, которые грузит `boot.asm`).

### PR: оформление и чек-лист ревью

- Описание: кратко что сделано и почему.
- Сборка: `build.bat` проходит локально без ошибок.
- Проверка: загрузка в QEMU (`run.bat`), нет `*** PAGE FAULT ***` и тройных
  сбоев; затронутые команды shell проверены вручную.
- Документация: обновлён `README.md` или добавлены docs в `docs/`, если
  менялась архитектура/карта памяти/список команд.
- Если изменение большое — откройте issue перед реализацией.

## Troubleshooting

### Ошибка "NASM не найден"
- Используйте локальную копию `tools\nasm.exe` (её уже использует
  `build.bat`) или установите NASM и добавьте в `PATH`.

### Ошибка "gcc"/"ld"/"objcopy не найден"
- Установите `w64devkit` в корень репозитория (папка `w64devkit/`) —
  `build.bat` сам добавляет `w64devkit\bin` в `PATH`.

### `kernel.bin` слишком большой / `boot.bin` не грузит ядро целиком
- `boot.asm` читает с диска ровно 89 секторов (45568 байт) под ядро. Если
  `build\kernel.bin` больше — урежьте код/данные или увеличьте число секторов
  в `boot.asm`.

### `build\fat12.bin` не создаётся / `tools\make_fat12.py` падает
- Убедитесь, что установлен Python и доступен в `PATH`.
- Проверьте содержимое каталога `fs/` (`MOTD.TXT`, `STARTUP.CFG`).

### QEMU не запускается (x86-64)
- Установите QEMU для Windows и поправьте путь в `run.bat`
  (`C:\Program Files\qemu\qemu-system-x86_64.exe`) или используйте
  `qemu-system-x86_64`, если он есть в `PATH`.
- **Обязательно `qemu-system-x86_64`, не `qemu-system-i386`** — с переходом
  ядра на long mode образу нужен `EFER.LME`, которого нет у `i386`-эмулятора
  (образ либо не загрузится, либо триплфолтнет сразу после
  `wrmsr`/`CR0.PG`). Реально ловили этот баг вживую в CI — `tools/qemu_test_helpers.py`
  (общий модуль всех 4 headless-тестов) когда-то использовал `qemu-system-i386`,
  несмотря на этот же самый совет здесь; см. "CI" выше за подробностями.
- Нужен флаг `-cpu Broadwell` (или новее) для нативной поддержки SMAP —
  без него ядро всё равно загрузится (детектирует отсутствие SMAP через
  CPUID и просто не включит CR4[21]), но часть харднинга не будет иметь
  эффекта. Haswell поддерживает SMEP, но не SMAP.

### QEMU не запускается (RISC-V)
- Нужен `qemu-system-riscv64` (отдельный от x86-64 бинарник QEMU) и
  прошивка OpenSBI — используйте `-bios default`, QEMU сама подставит
  встроенный OpenSBI для машины `virt`.
- Без `-device virtio-tablet-device` мышь не будет работать в
  `axpaint`/`axdesk` (клавиатура при этом останется рабочей) —
  `virtio_input.c` в этом случае просто печатает предупреждение и
  деградирует, не падает.

### `*** PAGE FAULT at 0x... ***` в QEMU (x86-64)
- Обращение к памяти за пределами замапленных областей (см. [карту
  памяти](https://github.com/mdudnikov82-beep/AxOS/wiki/Memory-Map-and-KASLR)) либо запись в страницу `.text`/данных
  без `RW` (`CR0.WP`, W^X). Отдельно смотрите на подпись фолта: `[SMEP/NX]`
  — ядро попыталось исполнить пользовательскую страницу; `[SMAP]` — ядро
  обратилось к пользовательским данным без `stac`/`smap_allow()`.

---

Лицензия: MIT.
