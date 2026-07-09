#include "axiom.h"
#include "dns.h"

// Проверка кэша dns.h: резолвит один и тот же хост дважды подряд в ОДНОМ
// процессе (кэш - static-массив в data-сегменте, между отдельными
// запусками не сохраняется) и печатает время каждого резолва в тиках
// ax_get_ticks() (100Гц PIT). Второй вызов должен быть на порядки быстрее
// первого - попадание в кэш не шлёт ни одного пакета. Третий вызов - для
// ДРУГОГО хоста, чтобы показать, что кэш не путает разные имена.
// Портирован с RISC-V стороны (src/user/rv64/dnscachet.c).

static void print_ip(unsigned int ip) {
    ax_printf("%u.%u.%u.%u", (ip >> 24) & 0xFF, (ip >> 16) & 0xFF,
              (ip >> 8) & 0xFF, ip & 0xFF);
}

static int resolve_and_report(const char *hostname) {
    unsigned int ip;
    unsigned int t0 = ax_get_ticks();
    int ok = dns_resolve_a(hostname, IP4(10, 0, 2, 3), 3000, &ip);
    unsigned int dt = ax_get_ticks() - t0;

    ax_printf("dnscache: %s -> ", hostname);
    if (!ok) { ax_print("FAILED\n"); return 0; }
    print_ip(ip);
    ax_printf(" (%u ax_get_ticks() ticks)\n", dt);
    return 1;
}

int main(int argc, char** argv) {
    (void)argc; (void)argv;

    unsigned char mac[6];
    if (!ax_net_mac(mac)) {
        ax_print("dnscache: no NIC found (need -device virtio-net-pci)\n");
        return 1;
    }

    ax_print("dnscache: 1st resolve (must hit the network) ---\n");
    if (!resolve_and_report("example.com")) return 1;

    ax_print("dnscache: 2nd resolve, same host (should hit the cache, near-instant) ---\n");
    if (!resolve_and_report("example.com")) return 1;

    ax_print("dnscache: 3rd resolve, DIFFERENT host (must hit the network again) ---\n");
    if (!resolve_and_report("cloudflare.com")) return 1;

    ax_print("dnscache: done\n");
    return 0;
}
