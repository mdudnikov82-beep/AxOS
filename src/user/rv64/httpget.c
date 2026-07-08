#include "syscall.h"
#include "dns.h"
#include "tcp.h"

// Проверка tcp.h "от и до" на настоящем внешнем сервере: резолвит
// example.com через DNS, поднимает TCP-соединение на порт 80 (SYN/SYN-ACK/
// ACK), шлёт настоящий HTTP/1.0 GET и печатает всё, что придёт в ответ, до
// закрытия соединения сервером (FIN). Использует SLIRP-DNS напрямую
// (10.0.2.3), не через dhcp_dns_ip - этот тест про TCP, DNS уже отдельно
// проверен в dnstest.c.

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

int main(void) {
    unsigned char mac[6];
    if (!net_mac(mac)) {
        puts_rv("http: no NIC found (need -device virtio-net-device)\r\n");
        exit(1);
    }

    puts_rv("http: resolving example.com via DNS (10.0.2.3)...\r\n");
    unsigned int target_ip;
    if (!dns_resolve_a("example.com", IP4(10, 0, 2, 3), 3000, &target_ip)) {
        puts_rv("http: DNS resolve failed\r\n");
        exit(1);
    }
    puts_rv("http: resolved to ");
    print_ip(target_ip);
    puts_rv("\r\n");

    static tcp_conn_t conn;
    puts_rv("http: connecting on port 80 (SYN/SYN-ACK/ACK)...\r\n");
    if (!tcp_connect(&conn, target_ip, 80, 3000)) {
        puts_rv("http: TCP connect failed\r\n");
        exit(1);
    }
    puts_rv("http: connected!\r\n");

    static const char req[] =
        "GET / HTTP/1.0\r\n"
        "Host: example.com\r\n"
        "Connection: close\r\n"
        "\r\n";
    if (tcp_send(&conn, req, sizeof(req) - 1) != 0) {
        puts_rv("http: send failed\r\n");
        tcp_close(&conn);
        exit(1);
    }
    puts_rv("http: request sent, reading response:\r\n");
    puts_rv("---------------------------------------------\r\n");

    static unsigned char resp[1024];
    unsigned long total = 0;
    for (;;) {
        int n = tcp_recv(&conn, resp, sizeof(resp), 3000);
        if (n > 0) {
            total += (unsigned long)n;
            write(1, resp, (unsigned int)n);
        } else if (n == 0) {
            puts_rv("\r\n---------------------------------------------\r\n");
            puts_rv("http: timeout waiting for more data\r\n");
            break;
        } else {
            puts_rv("\r\n---------------------------------------------\r\n");
            puts_rv("http: connection closed by server\r\n");
            break;
        }
    }
    tcp_close(&conn);

    puts_rv("http: total ");
    print_udec(total);
    puts_rv(" bytes received\r\n");

    exit(total > 0 ? 0 : 1);
    return 0;
}
