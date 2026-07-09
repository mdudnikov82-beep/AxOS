#include "syscall.h"
#include "dns.h"

// Проверка кэша dns.h: резолвит один и тот же хост дважды подряд в ОДНОМ
// процессе (кэш - static-массив в data-сегменте, живёт только пока живёт
// процесс - между отдельными "run"-запусками он не сохраняется) и
// печатает время каждого резолва в тиках gettime() (10МГц CLINT). Второй
// вызов должен быть на порядки быстрее первого - попадание в кэш не шлёт
// ни одного пакета, тогда как первый вызов всегда ждёт настоящий
// сетевой round-trip. Третий вызов - для ДРУГОГО хоста, чтобы показать,
// что кэш не путает разные имена (снова идёт по сети, а не подставляет
// первый попавшийся адрес).

static void print_ip(unsigned int ip) {
    unsigned char o[4] = { (unsigned char)(ip>>24), (unsigned char)(ip>>16),
                           (unsigned char)(ip>>8), (unsigned char)ip };
    for (int i = 0; i < 4; i++) {
        char dec[4]; int di = 0; unsigned int v = o[i];
        if (!v) dec[di++] = '0';
        while (v) { dec[di++] = (char)('0' + v % 10); v /= 10; }
        for (int a = 0, b = di - 1; a < b; a++, b--) { char t = dec[a]; dec[a] = dec[b]; dec[b] = t; }
        write(1, dec, di);
        if (i < 3) write(1, ".", 1);
    }
}

static void print_udec(unsigned long v) {
    char buf[20]; int i = 0;
    if (!v) { write(1, "0", 1); return; }
    while (v) { buf[i++] = '0' + (v % 10); v /= 10; }
    for (int a = 0, b = i - 1; a < b; a++, b--) { char t = buf[a]; buf[a] = buf[b]; buf[b] = t; }
    write(1, buf, i);
}

static int resolve_and_report(const char *hostname) {
    unsigned int ip;
    long t0 = gettime();
    int ok = dns_resolve_a(hostname, IP4(10, 0, 2, 3), 3000, &ip);
    long dt = gettime() - t0;

    puts_rv("dnscache: "); puts_rv(hostname); puts_rv(" -> ");
    if (!ok) { puts_rv("FAILED\r\n"); return 0; }
    print_ip(ip);
    puts_rv(" (");
    print_udec((unsigned long)dt);
    puts_rv(" gettime() ticks)\r\n");
    return 1;
}

int main(void) {
    unsigned char mac[6];
    if (!net_mac(mac)) {
        puts_rv("dnscache: no NIC found (need -device virtio-net-device)\r\n");
        exit(1);
    }

    puts_rv("dnscache: 1st resolve (must hit the network) ---\r\n");
    if (!resolve_and_report("example.com")) exit(1);

    puts_rv("dnscache: 2nd resolve, same host (should hit the cache, near-instant) ---\r\n");
    if (!resolve_and_report("example.com")) exit(1);

    puts_rv("dnscache: 3rd resolve, DIFFERENT host (must hit the network again) ---\r\n");
    if (!resolve_and_report("cloudflare.com")) exit(1);

    puts_rv("dnscache: done\r\n");
    exit(0);
    return 0;
}
