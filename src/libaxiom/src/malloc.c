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

void ax_free(void* ptr) {
    if (!ptr) return;
    struct block* b = (struct block*)((char*)ptr - HDR);
    b->free = 1;
    b->next = free_list;
    free_list = b;
}
