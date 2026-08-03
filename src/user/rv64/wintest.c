#include "syscall.h"

/* SYS_WIN_SET_BASE/SYS_WIN_SET_TOPMOST authorization fix (см. syscall.c,
 * name_is()): раньше ЛЮБОЙ процесс мог зарегистрировать rect на весь
 * экран и вызвать win_set_topmost() - и навсегда перекрыть экран и
 * выигрывать ВСЕ клики раньше настоящего AxTaskbar (Pass 1 в обработчике
 * SYS_MOUSE_STATE безусловно отдаёт клик первому найденному win_is_topmost
 * окну). Эта программа НЕ называется AXTASKB/AXDESK, поэтому обе попытки
 * теперь должны быть отклонены ядром. */
int main(void) {
    puts_rv("wintest: registering a fullscreen rect...\r\n");
    win_set_rect(0, 0, 800, 600);

    puts_rv("wintest: attempting win_set_topmost() (should be denied - not AXTASKB)...\r\n");
    long r = win_set_topmost();
    if (r < 0) {
        puts_rv("wintest: DENIED as expected\r\n");
    } else {
        puts_rv("wintest: BUG - win_set_topmost() succeeded, should have been denied!\r\n");
    }

    puts_rv("wintest: attempting win_set_base() (should be denied - not AXDESK)...\r\n");
    r = win_set_base();
    if (r < 0) {
        puts_rv("wintest: DENIED as expected\r\n");
    } else {
        puts_rv("wintest: BUG - win_set_base() succeeded, should have been denied!\r\n");
    }

    return 0;
}
