#include "syscall.h"
#include "tcp.h"

// Низкоуровневая проверка tcp.h БЕЗ DNS - подключается напрямую к
// захардкоженному IP:порту (10.0.2.99:9000), шлёт короткую строку, печатает
// всё, что придёт в ответ. В реальном SLIRP-окружении по умолчанию там
// никого нет - таймаут ожидаем. Существует для целенаправленной проверки
// через поддельный TCP-сервер на `-netdev socket` (см. память проекта про
// arp_maybe_respond/icmp_maybe_respond - тот же метод).

static void print_udec(unsigned long v) {
    char buf[20]; int i = 0;
    if (!v) { write(1, "0", 1); return; }
    while (v) { buf[i++] = '0' + (v % 10); v /= 10; }
    for (int a = 0, b = i - 1; a < b; a++, b--) { char t = buf[a]; buf[a] = buf[b]; buf[b] = t; }
    write(1, buf, i);
}

int main(void) {
    unsigned char mac[6];
    if (!net_mac(mac)) {
        puts_rv("tcptest: no NIC found (need -device virtio-net-device)\r\n");
        exit(1);
    }

    unsigned int target_ip = IP4(10, 0, 2, 99);
    unsigned short target_port = 9000;

    puts_rv("tcptest: connecting to 10.0.2.99:9000...\r\n");
    static tcp_conn_t conn;
    if (!tcp_connect(&conn, target_ip, target_port, 3000)) {
        puts_rv("tcptest: connect failed (expected if no test peer is listening)\r\n");
        exit(1);
    }
    puts_rv("tcptest: connected!\r\n");

    static const char msg[] = "Hello from AxOS/RV64 over real TCP!\n";
    tcp_send(&conn, msg, sizeof(msg) - 1);
    puts_rv("tcptest: sent, waiting for response...\r\n");

    static unsigned char resp[512];
    unsigned long total = 0;
    for (;;) {
        int n = tcp_recv(&conn, resp, sizeof(resp), 3000);
        if (n > 0) {
            total += (unsigned long)n;
            write(1, resp, (unsigned int)n);
        } else if (n == 0) {
            puts_rv("tcptest: timeout waiting for more data\r\n");
            break;
        } else {
            puts_rv("tcptest: connection closed by peer\r\n");
            break;
        }
    }
    tcp_close(&conn);

    puts_rv("tcptest: total ");
    print_udec(total);
    puts_rv(" bytes received\r\n");

    exit(total > 0 ? 0 : 1);
    return 0;
}
