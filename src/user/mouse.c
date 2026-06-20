#include "axiom.h"

int main(int argc, char** argv) {
    (void)argc; (void)argv;

    ax_print("Move the mouse - press any key to stop (auto-stop after 15s)\n");

    struct mouse_args m, last;
    ax_get_mouse(&m);
    last = m;
    ax_printf("x=%d y=%d buttons=%d\n", m.x, m.y, m.buttons);

    unsigned int start = ax_get_ticks();
    while (ax_get_ticks() - start < 1500) { // 15 секунд при 100 Гц
        if (ax_readkey() != 0) break;

        ax_get_mouse(&m);
        if (m.x != last.x || m.y != last.y || m.buttons != last.buttons) {
            ax_printf("x=%d y=%d buttons=%d\n", m.x, m.y, m.buttons);
            last = m;
        }
        ax_sleep_ms(50);
    }
    return 0;
}
