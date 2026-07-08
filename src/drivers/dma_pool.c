// Маленький identity-mapped bump-аллокатор для физической/DMA-памяти
// драйверов. Появился при переводе кучи ядра (heap.c) на настоящий
// 64-битный KASLR (см. paging.c) - до этого virtio_net.c брал память под
// virtqueue через malloc() и использовал САМ УКАЗАТЕЛЬ как физический
// адрес, пользуясь тем, что вся куча была identity-mapped (VA==PA). Как
// только куча переехала на случайный ВЫСОКИЙ виртуальный адрес,
// развязанный от физического, этот трюк сломался бы - устройство получило
// бы виртуальный адрес вместо физического и писало/читало бы совершенно
// не ту память. Решение: у DMA-буферов свой собственный, всегда
// identity-mapped пул, никогда не движущийся вместе с общей кучей - тот
// же архитектурный приём, что и pmem.c на RISC-V стороне (там он был с
// самого начала, поэтому RISC-V этой проблемы вообще не касалось).
//
// Живёт ВНУТРИ уже промаппированных первых 2МБ (PT0 в paging.c кроет их
// поштранично, обычными RW-kernel-only 4КБ-страницами) - в свободном
// промежутке между концом TTYS (~0x161F90) и USER_PROGRAM_BASE (0x200000,
// см. kernel.c) - никакой новой работы с page table не нужно, память уже
// присутствует и доступна.
//
// Простой bump-указатель без free() - буферы, как и раньше при
// malloc()-подходе, выделяются один раз при инициализации драйвера и
// живут всё время его работы.

#define DMA_POOL_BASE 0x180000u
#define DMA_POOL_SIZE 0x20000u   // 128КБ = 32 страницы - c большим запасом
                                  // (virtio_net.c на оба queue setup + RX-
                                  // буферы + tx_scratch тратит 17 страниц)
#define PAGE_SIZE     4096u

static unsigned int dma_pool_offset = 0;

void* dma_alloc_pages(unsigned int num_pages) {
    unsigned int size = num_pages * PAGE_SIZE;
    if (dma_pool_offset + size > DMA_POOL_SIZE) return 0;   // пул исчерпан

    unsigned char* p = (unsigned char*)(unsigned long long)(DMA_POOL_BASE + dma_pool_offset);
    dma_pool_offset += size;

    for (unsigned int i = 0; i < size; i++) p[i] = 0;
    return p;
}
