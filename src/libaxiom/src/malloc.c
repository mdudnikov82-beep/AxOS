#include "../include/axiom.h"

#define ALIGN4(n) (((unsigned int)(n) + 3u) & ~3u)

struct block {
    unsigned int  size;  // payload bytes (not including this header)
    struct block* next;  // free-list link (meaningful only when free==1)
    unsigned int  free;
};

#define HDR sizeof(struct block)

static struct block* free_list = 0;

void* ax_malloc(unsigned int size) {
    if (size == 0) return 0;
    size = ALIGN4(size);

    // First-fit search in the free list
    struct block* prev = 0;
    struct block* b = free_list;
    while (b) {
        if (b->size >= size) {
            if (prev) prev->next = b->next;
            else      free_list  = b->next;
            b->free = 0;
            b->next = 0;
            return (void*)((char*)b + HDR);
        }
        prev = b;
        b = b->next;
    }

    // Extend heap
    b = (struct block*)ax_sbrk((int)(HDR + size));
    if ((unsigned int)b == (unsigned int)-1) return 0;
    b->size = size;
    b->free = 0;
    b->next = 0;
    return (void*)((char*)b + HDR);
}

// free_list - не упорядочен по адресу, поэтому слияние с физически
// соседними блоками требует двух проходов по списку (но он короткий -
// у задачи единицы-десятки блоков в её ~30 КБ окне).
void ax_free(void* ptr) {
    if (!ptr) return;
    struct block* b = (struct block*)((char*)ptr - HDR);
    b->free = 1;

    // 1) Слияние со следующим физическим блоком, если он свободен:
    // ищем в free_list блок, начинающийся ровно там, где кончается b.
    struct block* next_adj = (struct block*)((char*)b + HDR + b->size);
    struct block* prev = 0;
    struct block* cur = free_list;
    while (cur) {
        if (cur == next_adj) {
            b->size += HDR + cur->size;
            if (prev) prev->next = cur->next;
            else      free_list  = cur->next;
            break;
        }
        prev = cur;
        cur = cur->next;
    }

    // 2) Слияние с предыдущим физическим блоком, если он свободен:
    // ищем блок, который кончается ровно там, где начинается b
    // (b уже мог "подрасти" на шаге 1 - это не меняет его адрес начала).
    cur = free_list;
    while (cur) {
        if ((char*)cur + HDR + cur->size == (char*)b) {
            cur->size += HDR + b->size;
            return; // cur уже в free_list, b в него поглощён целиком
        }
        prev = cur;
        cur = cur->next;
    }

    // Соседей не нашли (или нашли только следующего) - добавляем b сам.
    b->next = free_list;
    free_list = b;
}
