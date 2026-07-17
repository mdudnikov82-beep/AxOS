#include "axiom.h"

int main(void) {
    ax_print("memtest: shadow + memory tagging\n");

    // 1. Базовый malloc
    char* p = ax_malloc(64);
    if (!p) { ax_print("FAIL: malloc\n"); return 1; }

    // 2. ax_check на живом блоке
    if (!ax_check(p, 64)) { ax_print("FAIL: ax_check live\n"); return 1; }

    // 3. ax_alloc_tag возвращает ненулевой тег
    tag144_t tag = ax_alloc_tag(p);
    if (tag144_is_zero(tag)) { ax_print("FAIL: tag is 0\n"); return 1; }

    // 4. ax_check_tag подтверждает правильное поколение
    if (!ax_check_tag(p, tag, 64)) { ax_print("FAIL: ax_check_tag live\n"); return 1; }

    // 5. Запись и чтение
    for (int i = 0; i < 64; i++) p[i] = (char)i;
    for (int i = 0; i < 64; i++)
        if (p[i] != (char)i) { ax_print("FAIL: rw\n"); return 1; }

    // 6. free → shadow = FREED, тег сбрасывается
    ax_free(p);
    if (ax_check(p, 64))                       { ax_print("FAIL: ax_check freed\n"); return 1; }
    if (!tag144_is_zero(ax_alloc_tag(p)))       { ax_print("FAIL: tag after free\n"); return 1; }
    if (ax_check_tag(p, tag, 64))               { ax_print("FAIL: ax_check_tag freed\n"); return 1; }

    // 7. Переиспользование: тот же адрес, НОВОЕ поколение
    //    Карантин из 8 блоков откладывает возврат; заполняем его,
    //    чтобы гарантировать переиспользование старого адреса.
    char* drain[8];
    for (int i = 0; i < 8; i++) drain[i] = ax_malloc(64);
    for (int i = 0; i < 8; i++) ax_free(drain[i]);

    char* p2 = ax_malloc(64);   // теперь старый блок вышел из карантина
    if (!p2) { ax_print("FAIL: malloc p2\n"); return 1; }

    tag144_t tag2 = ax_alloc_tag(p2);
    if (tag144_is_zero(tag2)) { ax_print("FAIL: tag2 is 0\n"); return 1; }

    // Если p2 == p (тот же адрес), старый тег должен НЕ совпадать
    if (p2 == p && tag144_eq(tag2, tag)) {
        ax_print("NOTE: same address, same tag (1/2^144 probability)\n");
    }
    // ax_check_tag со СТАРЫМ тегом должен вернуть 0 (новое поколение)
    if (p2 == p && !tag144_eq(tag2, tag)) {
        if (ax_check_tag(p, tag, 64)) {
            ax_print("FAIL: stale tag accepted\n"); return 1;
        }
    }

    // 8. Checked handle: resolves while live, fails after free (software TBI stand-in)
    ax_handle_t h = ax_handle(p2);
    if (ax_resolve(h, 64) != p2) { ax_print("FAIL: handle resolve while live\n"); return 1; }
    ax_free(p2);
    if (ax_resolve(h, 64) != 0)  { ax_print("FAIL: handle resolve after free\n"); return 1; }

    ax_print("memtest: ALL PASS\n");
    return 0;
}
