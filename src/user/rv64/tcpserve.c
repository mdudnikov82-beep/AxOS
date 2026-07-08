#include "syscall.h"
#include "tcp.h"

// Минимальный TCP-эхо-сервер: принимает ОДНО соединение на порт 8080
// (tcp_accept - пассивное открытие), эхом отвечает на всё, что пришлёт
// клиент (с префиксом "Echo: "), закрывается либо когда клиент сам
// закроет соединение, либо по таймауту бездействия.

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
        puts_rv("tcpserve: no NIC found (need -device virtio-net-device)\r\n");
        exit(1);
    }

    puts_rv("tcpserve: listening on port 8080 (up to 15s)...\r\n");
    static tcp_conn_t conn;
    if (!tcp_accept(&conn, 8080, 15000)) {
        puts_rv("tcpserve: no connection within timeout\r\n");
        exit(1);
    }
    puts_rv("tcpserve: client connected!\r\n");

    static unsigned char buf[512];
    static char reply[550];
    for (;;) {
        int n = tcp_recv(&conn, buf, sizeof(buf), 5000);
        if (n > 0) {
            puts_rv("tcpserve: received ");
            print_udec((unsigned long)n);
            puts_rv(" bytes: ");
            write(1, buf, (unsigned int)n);
            puts_rv("\r\n");

            int rlen = 0;
            const char *prefix = "Echo: ";
            for (const char *p = prefix; *p; p++) reply[rlen++] = *p;
            for (int i = 0; i < n; i++) reply[rlen++] = (char)buf[i];
            tcp_send(&conn, reply, (unsigned int)rlen);
            puts_rv("tcpserve: echoed back\r\n");
        } else if (n == 0) {
            puts_rv("tcpserve: no more data (idle timeout), closing\r\n");
            break;
        } else {
            puts_rv("tcpserve: client closed connection\r\n");
            break;
        }
    }
    tcp_close(&conn);
    puts_rv("tcpserve: done\r\n");
    exit(0);
    return 0;
}
