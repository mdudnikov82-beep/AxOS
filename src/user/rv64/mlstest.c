#include "syscall.h"

/* MLS self-raise fix (см. SYS_SET_LEVEL, syscall.c): раньше эта демка
 * молча УСПЕШНО поднимала себе уровень - любая изолированная задача
 * могла сама поднять себя до s15 и обойти mls_dominates()'s "no read
 * up" (см. ps/ps_info) целиком. Теперь SYS_SET_LEVEL разрешает только
 * ПОНИЖЕНИЕ; попытка подняться отклоняется ядром (видно в серийной
 * консоли как "avc: denied { setlevel }..."), set_level() возвращает
 * -1, задача остаётся на своём текущем уровне. Демка теперь честно
 * показывает НОВОЕ поведение вместо старого небезопасного. */
int main(void) {
    puts_rv("mlstest: attempting to raise to MLS level 5 (should be denied)...\r\n");
    long r = set_level(5);
    if (r < 0) {
        puts_rv("mlstest: DENIED as expected - self-raise is forbidden now\r\n");
    } else {
        puts_rv("mlstest: BUG - self-raise succeeded, should have been denied!\r\n");
    }

    puts_rv("mlstest: confirming a LOWER level (s0) is still allowed...\r\n");
    r = set_level(0);
    puts_rv(r == 0 ? "mlstest: lowering to s0 OK (allowed direction)\r\n"
                   : "mlstest: BUG - lowering was unexpectedly denied\r\n");
    return 0;
}
