#include "axiom.h"
#include "icmp.h"

// Проверка icmp.h "от и до": 4 ping'а на гейтвей QEMU SLIRP (10.0.2.2),
// как классический `ping -c 4`. Портирован с RISC-V стороны
// (src/user/rv64/pingtest.c) - тот же протокол, тот же тест.

int main(int argc, char** argv) {
    (void)argc; (void)argv;

    unsigned char mac[6];
    if (!ax_net_mac(mac)) {
        ax_print("ping: no NIC found (need -device virtio-net-pci)\n");
        return 1;
    }

    unsigned int target = IP4(10, 0, 2, 2);
    ax_print("PING 10.0.2.2 (gateway):\n");

    int sent = 0, received = 0;
    for (unsigned short seq = 1; seq <= 4; seq++) {
        sent++;
        unsigned long rtt;
        if (icmp_ping(target, seq, 2000, &rtt)) {
            received++;
            ax_printf("  reply seq=%u time=%ums\n", (unsigned int)seq, (unsigned int)rtt);
        } else {
            ax_printf("  seq=%u timeout\n", (unsigned int)seq);
        }
        ax_sleep_ms(200);
    }

    ax_printf("--- statistics: %d sent, %d received\n", sent, received);

    return received > 0 ? 0 : 1;
}
