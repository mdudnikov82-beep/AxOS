#include "axiom.h"
#include "tcp.h"

// Минимальный TCP-эхо-сервер: принимает ОДНО соединение на порт 8080
// (tcp_accept - пассивное открытие), эхом отвечает на всё, что пришлёт
// клиент (с префиксом "Echo: "), закрывается либо когда клиент сам
// закроет соединение, либо по таймауту бездействия. Портирован с
// RISC-V стороны (src/user/rv64/tcpserve.c) - тот же протокол.

int main(int argc, char** argv) {
    (void)argc; (void)argv;

    unsigned char mac[6];
    if (!ax_net_mac(mac)) {
        ax_print("tcpserve: no NIC found (need -device virtio-net-pci)\n");
        return 1;
    }

    ax_print("tcpserve: listening on port 8080 (up to 15s)...\n");
    static tcp_conn_t conn;
    if (!tcp_accept(&conn, 8080, 15000)) {
        ax_print("tcpserve: no connection within timeout\n");
        return 1;
    }
    ax_print("tcpserve: client connected!\n");

    static unsigned char buf[512];
    static char reply[550];
    for (;;) {
        int n = tcp_recv(&conn, buf, sizeof(buf), 5000);
        if (n > 0) {
            ax_printf("tcpserve: received %d bytes: ", n);
            for (int i = 0; i < n; i++) ax_putchar((char)buf[i]);
            ax_print("\n");

            int rlen = 0;
            const char *prefix = "Echo: ";
            for (const char *p = prefix; *p; p++) reply[rlen++] = *p;
            for (int i = 0; i < n; i++) reply[rlen++] = (char)buf[i];
            tcp_send(&conn, reply, (unsigned int)rlen);
            ax_print("tcpserve: echoed back\n");
        } else if (n == 0) {
            ax_print("tcpserve: no more data (idle timeout), closing\n");
            break;
        } else {
            ax_print("tcpserve: client closed connection\n");
            break;
        }
    }
    tcp_close(&conn);
    ax_print("tcpserve: done\n");
    return 0;
}
