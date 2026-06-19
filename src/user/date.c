#include "axiom.h"

int main(int argc, char** argv) {
    (void)argc; (void)argv;

    struct datetime_args dt;
    ax_get_datetime(&dt);
    ax_printf("%04d-%02d-%02d %02d:%02d:%02d\n",
              2000 + dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second);
    return 0;
}
