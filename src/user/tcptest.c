#include "axiom.h"
#include "tcp.h"

// Низкоуровневая проверка tcp.h БЕЗ DNS - подключается напрямую к
// захардкоженному IP:порту (10.0.2.99:9000), шлёт короткую строку,
// печатает всё, что придёт в ответ. В реальном SLIRP-окружении по
// умолчанию там никого нет - таймаут ожидаем. Существует для
// целенаправленной проверки через поддельный TCP-сервер на
// `-netdev socket` (см. память проекта про arp_maybe_respond/
// icmp_maybe_respond - тот же метод). Портирован с RISC-V стороны
// (src/user/rv64/tcptest.c) - тот же протокол, тот же тест.

int main(int argc, char** argv) {
    (void)argc; (void)argv;

    unsigned char mac[6];
    if (!ax_net_mac(mac)) {
        ax_print("tcptest: no NIC found (need -device virtio-net-pci)\n");
        return 1;
    }

    unsigned int target_ip = IP4(10, 0, 2, 99);
    unsigned short target_port = 9000;

    ax_print("tcptest: connecting to 10.0.2.99:9000...\n");
    static tcp_conn_t conn;
    if (!tcp_connect(&conn, target_ip, target_port, 3000)) {
        ax_print("tcptest: connect failed (expected if no test peer is listening)\n");
        return 1;
    }
    ax_print("tcptest: connected!\n");

    static const char msg[] = "Hello from AxOS/x86 over real TCP!\n";
    tcp_send(&conn, msg, sizeof(msg) - 1);
    ax_print("tcptest: sent, waiting for response...\n");

    static unsigned char resp[512];
    unsigned int total = 0;
    for (;;) {
        int n = tcp_recv(&conn, resp, sizeof(resp), 3000);
        if (n > 0) {
            total += (unsigned int)n;
            for (int i = 0; i < n; i++) ax_putchar((char)resp[i]);
        } else if (n == 0) {
            ax_print("tcptest: timeout waiting for more data\n");
            break;
        } else {
            ax_print("tcptest: connection closed by peer\n");
            break;
        }
    }
    tcp_close(&conn);

    ax_printf("tcptest: total %u bytes received\n", total);

    return total > 0 ? 0 : 1;
}
