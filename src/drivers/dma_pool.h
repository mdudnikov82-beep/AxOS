#ifndef DMA_POOL_H
#define DMA_POOL_H

// Маленький identity-mapped bump-аллокатор для физической/DMA-памяти
// драйверов (virtqueue-дескрипторы и т.п. - всё, что реальное устройство
// адресует физическим адресом, а не указателем ядра). См. dma_pool.c за
// подробностями, почему это ОТДЕЛЬНО от обычной kmalloc()-кучи.
void* dma_alloc_pages(unsigned int num_pages);

#endif
