#include "axiom.h"
#include "arp.h"

// Проверка arp.h "от и до": резолвит два реальных адреса QEMU SLIRP
// (гейтвей 10.0.2.2 и DNS 10.0.2.3), затем резолвит гейтвей ПОВТОРНО,
// чтобы показать попадание в кэш (второй вызов не должен слать новый
// запрос). Портирована с RISC-V стороны (src/user/rv64/arptest.c) - тот
// же тест, тот же протокол.

static int resolve_and_print(char* label, unsigned int ip) {
    unsigned char mac[6];
    unsigned int t0 = ax_get_ticks();
    int ok = arp_resolve(ip, mac, 3000);
    unsigned int t1 = ax_get_ticks();
    unsigned int ms = (t1 - t0) * 10;   // тики PIT - 100 Гц, 10мс каждый

    ax_print(label);
    if (!ok) { ax_print(" -- FAIL (no reply in 3s)\n"); return 0; }

    ax_printf(" -> %02x:%02x:%02x:%02x:%02x:%02x (%ums)\n",
              mac[0], mac[1], mac[2], mac[3], mac[4], mac[5], ms);
    return 1;
}

int main(int argc, char** argv) {
    (void)argc; (void)argv;

    unsigned char mac[6];
    if (!ax_net_mac(mac)) {
        ax_print("arp: no NIC found (need -device virtio-net-pci)\n");
        return 1;
    }

    int ok1 = resolve_and_print("arp: resolve 10.0.2.2 (gateway)", IP4(10, 0, 2, 2));
    int ok2 = resolve_and_print("arp: resolve 10.0.2.3 (dns)    ", IP4(10, 0, 2, 3));
    int ok3 = resolve_and_print("arp: resolve 10.0.2.2 (cached) ", IP4(10, 0, 2, 2));

    if (ok1 && ok2 && ok3) {
        ax_print("arp: ALL OK\n");
        return 0;
    }
    ax_print("arp: FAILED\n");
    return 1;
}
