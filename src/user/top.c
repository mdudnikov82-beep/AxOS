#include "axiom.h"

int main(int argc, char** argv) {
    (void)argc; (void)argv;

    struct ps_entry e;

    while (1) {
        ax_clear();

        unsigned int ticks = ax_get_ticks();
        ax_printf("\033[36mAxOS top  --  uptime: %u s\033[0m\n\n", ticks / 100);

        ax_print("\033[36m");
        ax_printf(" %3s  %-12s  %8s  %s\n", "ID", "NAME", "TICKS", "INFO");
        ax_print("----  ------------  --------  ---------------\033[0m\n");

        for (unsigned int i = 0; ; i++) {
            e.index = i;
            ax_ps(&e);
            if (!e.result) break;

            ax_printf(" %3d  %-12s  %8u  ", e.pid, e.name, e.ticks);
            if (e.slot >= 0)
                ax_printf("\033[32muser:%d  heap=0x%x\033[0m\n", e.slot, e.heap_brk);
            else
                ax_print("kernel\n");
        }

        ax_print("\n\033[33mCtrl+C to exit\033[0m\n");
        ax_sleep_ms(1000);
    }
    return 0;
}
