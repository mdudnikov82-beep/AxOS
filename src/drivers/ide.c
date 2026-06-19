// =================================================================
//  PIO-драйвер ATA/IDE (primary bus, master, LBA28)
// =================================================================
//
// Передача данных - всё ещё PIO через порты 0x1F0-0x1F7 (без DMA), но
// ожидание готовности контроллера идёт через настоящее прерывание IRQ14
// (idt.asm/kernel.c), а не через busy-poll статус-регистра, как было
// раньше. Используется только из disktool.bin (SYS_DISK_*) - встроенный
// в образ FAT12 RAM-диск (fat12.c) тут не задействован, у него своя
// in-memory копия.
//
// ide_wait_ready() (ждём, что контроллер вообще отвечает, до выдачи
// команды) остался поллингом - это проверка "жив ли диск", не связанная
// с конкретной командой, IRQ тут ни при чём.

#define IDE_REG_DATA       0x1F0
#define IDE_REG_SECCOUNT   0x1F2
#define IDE_REG_LBA_LOW    0x1F3
#define IDE_REG_LBA_MID    0x1F4
#define IDE_REG_LBA_HIGH   0x1F5
#define IDE_REG_DRIVE_HEAD 0x1F6
#define IDE_REG_STATUS     0x1F7
#define IDE_REG_COMMAND    0x1F7

#define IDE_STATUS_ERR 0x01
#define IDE_STATUS_DRQ 0x08
#define IDE_STATUS_BSY 0x80

#define IDE_CMD_READ_SECTORS  0x20
#define IDE_CMD_WRITE_SECTORS 0x30
#define IDE_CMD_CACHE_FLUSH   0xE7
#define IDE_CMD_IDENTIFY      0xEC

#define IDE_WAIT_LIMIT 100000

// Тики PIT (kernel.c, 100 Гц) - используются для тайм-аута ide_wait_irq()
// и (через hlt) чтобы реально освобождать CPU другим задачам во время
// ожидания, а не жечь его в busy-spin.
extern volatile unsigned long timer_ticks;
#define IDE_IRQ_TIMEOUT_TICKS 500 // 5 секунд - щедрый запас на одну операцию

// Ставится обработчиком IRQ14 (idt.asm -> ide_irq_handler_main ниже).
// Сбрасывается в 0 непосредственно перед каждой командой, которая должна
// вызвать прерывание - так ide_wait_irq() не примет "эхо" от предыдущей
// операции за готовность текущей.
static volatile int ide_irq_fired = 0;

void ide_irq_handler_main() {
    ide_irq_fired = 1;
}

static unsigned char port_byte_in(unsigned short port) {
    unsigned char result;
    __asm__ volatile("inb %%dx, %%al" : "=a"(result) : "d"(port));
    return result;
}

static void port_byte_out(unsigned short port, unsigned char data) {
    __asm__ volatile("outb %%al, %%dx" : : "a"(data), "d"(port));
}

static unsigned short port_word_in(unsigned short port) {
    unsigned short result;
    __asm__ volatile("inw %%dx, %%ax" : "=a"(result) : "d"(port));
    return result;
}

static void port_word_out(unsigned short port, unsigned short data) {
    __asm__ volatile("outw %%ax, %%dx" : : "a"(data), "d"(port));
}

// Ждёт, пока контроллер очистит BSY. Возвращает 0, если устройство не
// отвечает (статус 0xFF) или BSY не сбросился за IDE_WAIT_LIMIT попыток.
static int ide_wait_ready() {
    unsigned char status = port_byte_in(IDE_REG_STATUS);
    if (status == 0xFF) return 0; // нет контроллера/устройства

    for (unsigned int i = 0; i < IDE_WAIT_LIMIT; i++) {
        status = port_byte_in(IDE_REG_STATUS);
        if (!(status & IDE_STATUS_BSY)) return 1;
    }
    return 0; // таймаут
}

// Ждёт готовности данных (BSY=0, DRQ=1). Возвращает 0 при ERR или таймауте.
// Используется только там, где прерывание по спецификации ATA не
// гарантировано (DRQ для первого блока команды WRITE SECTORS - см.
// ide_write_sector) - во всех остальных случаях ждём IRQ14, не статус-регистр.
static int ide_wait_data() {
    for (unsigned int i = 0; i < IDE_WAIT_LIMIT; i++) {
        unsigned char status = port_byte_in(IDE_REG_STATUS);
        if (status & IDE_STATUS_ERR) return 0;
        if (!(status & IDE_STATUS_BSY) && (status & IDE_STATUS_DRQ)) return 1;
    }
    return 0; // таймаут
}

// Ждёт прерывания от контроллера (вместо опроса статус-регистра) после
// команды, которая по спецификации ATA гарантированно его генерирует.
// Возвращает 0 при ERR-бите или если IRQ не пришёл за отведённое время
// (не должно происходить при включённом IRQ14, но не должно и подвесить
// систему намертво, если что-то пошло не так).
//
// sti() ОБЯЗАТЕЛЕН здесь: эти функции вызываются из syscall'ов (int 0x80),
// а IDT-gate syscall'а - interrupt gate, CPU сам гасит IF при входе (см.
// комментарий у IDT[0x80] в kernel.c - на этом ещё и критические секции
// heap.c держатся). Значит, всё время выполнения syscall'а прерывания
// глобально выключены - IRQ14 физически не сможет быть доставлен без sti
// (PIC и IDT были настроены верно с самого начала, но прерывание просто
// не могло прийти).
//
// hlt вместо busy-spin: задача, ждущая диск, не жжёт CPU впустую. hlt
// останавливает ядро до СЛЕДУЮЩЕГО любого прерывания - а таймерный тик
// (IRQ0, 100 Гц) и так дёргает schedule() из idt.asm при каждом срабатывании,
// так что другие задачи в кольце получают процессор естественным образом,
// без отдельного состояния BLOCKED в планировщике - ровно тот же приём,
// что уже используется в sleep_ms() (kernel.c) для SYS_SLEEP.
static int ide_wait_irq() {
    unsigned long deadline = timer_ticks + IDE_IRQ_TIMEOUT_TICKS;

    __asm__ volatile("sti");
    while (!ide_irq_fired) {
        if (timer_ticks >= deadline) return 0; // таймаут - прерывание не пришло
        __asm__("hlt");
    }
    return !(port_byte_in(IDE_REG_STATUS) & IDE_STATUS_ERR);
}

static void ide_select_lba(unsigned int lba) {
    port_byte_out(IDE_REG_DRIVE_HEAD, 0xE0 | ((lba >> 24) & 0x0F)); // master, LBA mode
    port_byte_out(IDE_REG_SECCOUNT, 1);
    port_byte_out(IDE_REG_LBA_LOW, lba & 0xFF);
    port_byte_out(IDE_REG_LBA_MID, (lba >> 8) & 0xFF);
    port_byte_out(IDE_REG_LBA_HIGH, (lba >> 16) & 0xFF);
}

int ide_read_sector(unsigned int lba, unsigned char* buffer) {
    if (!ide_wait_ready()) return 0;

    ide_select_lba(lba);
    ide_irq_fired = 0; // сбрасываем до команды - иначе примем "эхо" от предыдущей операции
    port_byte_out(IDE_REG_COMMAND, IDE_CMD_READ_SECTORS);

    // READ SECTORS гарантированно генерирует IRQ при готовности данных.
    if (!ide_wait_irq()) return 0;

    for (int i = 0; i < 256; i++) {
        unsigned short word = port_word_in(IDE_REG_DATA);
        buffer[i * 2]     = word & 0xFF;
        buffer[i * 2 + 1] = (word >> 8) & 0xFF;
    }

    return 1;
}

int ide_write_sector(unsigned int lba, unsigned char* buffer) {
    if (!ide_wait_ready()) return 0;

    ide_select_lba(lba);
    port_byte_out(IDE_REG_COMMAND, IDE_CMD_WRITE_SECTORS);

    // Особый случай: по спецификации ATA контроллер НЕ обязан слать IRQ
    // перед первым (тут и единственным, SECCOUNT=1) блоком данных команды
    // WRITE SECTORS - хост должен сам опросить DRQ. IRQ гарантирован только
    // ПОСЛЕ того, как этот блок принят - вот его и ждём ниже через
    // ide_wait_irq(), а не статус-регистр.
    if (!ide_wait_data()) return 0;

    for (int i = 0; i < 256; i++) {
        unsigned short word = buffer[i * 2] | (buffer[i * 2 + 1] << 8);
        port_word_out(IDE_REG_DATA, word);
    }

    ide_irq_fired = 0; // сбрасываем перед ожиданием завершения записи блока
    if (!ide_wait_irq()) return 0;

    ide_irq_fired = 0; // и перед ожиданием завершения CACHE FLUSH
    port_byte_out(IDE_REG_COMMAND, IDE_CMD_CACHE_FLUSH);
    return ide_wait_irq();
}

int ide_identify(char* model) {
    if (!ide_wait_ready()) return 0;

    port_byte_out(IDE_REG_DRIVE_HEAD, 0xE0);
    port_byte_out(IDE_REG_SECCOUNT, 0);
    port_byte_out(IDE_REG_LBA_LOW, 0);
    port_byte_out(IDE_REG_LBA_MID, 0);
    port_byte_out(IDE_REG_LBA_HIGH, 0);
    ide_irq_fired = 0;
    port_byte_out(IDE_REG_COMMAND, IDE_CMD_IDENTIFY);

    if (port_byte_in(IDE_REG_STATUS) == 0) return 0; // нет устройства
    // IDENTIFY DEVICE гарантированно генерирует IRQ при готовности данных,
    // как и READ SECTORS.
    if (!ide_wait_irq()) return 0;

    unsigned short data[256];
    for (int i = 0; i < 256; i++) {
        data[i] = port_word_in(IDE_REG_DATA);
    }

    // Слова 27-46 ответа IDENTIFY - модель устройства (40 символов ASCII,
    // байты в каждом слове в обратном порядке).
    int p = 0;
    for (int i = 27; i <= 46; i++) {
        model[p++] = (char)((data[i] >> 8) & 0xFF);
        model[p++] = (char)(data[i] & 0xFF);
    }
    model[p] = '\0';

    while (p > 0 && model[p - 1] == ' ') {
        model[--p] = '\0';
    }

    return 1;
}
