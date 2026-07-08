#include "axiom.h"
#include "dns.h"
#include "tcp.h"

// Проверка tcp.h "от и до" на настоящем внешнем сервере: резолвит
// example.com через DNS, поднимает TCP-соединение на порт 80 (SYN/SYN-ACK/
// ACK), шлёт настоящий HTTP/1.0 GET и печатает всё, что придёт в ответ, до
// закрытия соединения сервером (FIN). Использует SLIRP-DNS напрямую
// (10.0.2.3), не через dhcp_dns_ip - этот тест про TCP, DNS уже отдельно
// проверен в dnstest.c. Портирован с RISC-V стороны
// (src/user/rv64/httpget.c) - тот же протокол, тот же тест.

static void print_ip(unsigned int ip) {
    ax_printf("%u.%u.%u.%u", (ip >> 24) & 0xFF, (ip >> 16) & 0xFF,
              (ip >> 8) & 0xFF, ip & 0xFF);
}

int main(int argc, char** argv) {
    (void)argc; (void)argv;

    unsigned char mac[6];
    if (!ax_net_mac(mac)) {
        ax_print("http: no NIC found (need -device virtio-net-pci)\n");
        return 1;
    }

    ax_print("http: resolving example.com via DNS (10.0.2.3)...\n");
    unsigned int target_ip;
    if (!dns_resolve_a("example.com", IP4(10, 0, 2, 3), 3000, &target_ip)) {
        ax_print("http: DNS resolve failed\n");
        return 1;
    }
    ax_print("http: resolved to ");
    print_ip(target_ip);
    ax_print("\n");

    static tcp_conn_t conn;
    ax_print("http: connecting on port 80 (SYN/SYN-ACK/ACK)...\n");
    if (!tcp_connect(&conn, target_ip, 80, 3000)) {
        ax_print("http: TCP connect failed\n");
        return 1;
    }
    ax_print("http: connected!\n");

    static const char req[] =
        "GET / HTTP/1.0\r\n"
        "Host: example.com\r\n"
        "Connection: close\r\n"
        "\r\n";
    if (tcp_send(&conn, req, sizeof(req) - 1) != 0) {
        ax_print("http: send failed\n");
        tcp_close(&conn);
        return 1;
    }
    ax_print("http: request sent, reading response:\n");
    ax_print("---------------------------------------------\n");

    static unsigned char resp[1024];
    unsigned int total = 0;
    for (;;) {
        int n = tcp_recv(&conn, resp, sizeof(resp), 3000);
        if (n > 0) {
            total += (unsigned int)n;
            for (int i = 0; i < n; i++) ax_putchar((char)resp[i]);
        } else if (n == 0) {
            ax_print("\n---------------------------------------------\n");
            ax_print("http: timeout waiting for more data\n");
            break;
        } else {
            ax_print("\n---------------------------------------------\n");
            ax_print("http: connection closed by server\n");
            break;
        }
    }
    tcp_close(&conn);

    ax_printf("http: total %u bytes received\n", total);

    return total > 0 ? 0 : 1;
}
