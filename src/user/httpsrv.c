#include "axiom.h"
#include "tcp.h"

// Минимальный HTTP/1.0-сервер поверх tcp_accept(): слушает порт 80,
// разбирает первую строку запроса ("GET /путь HTTP/1.x"), отдаёт
// соответствующий файл из FAT12 (пустой путь/"/" -> INDEX.HTM) через
// ax_open()/ax_fread()/ax_close(), либо 404. Одно соединение за раз (как
// и весь tcp.h) - обслужив клиента, снова слушает следующего, бесконечно.
// Портирован с RISC-V стороны (src/user/rv64/httpsrv.c) - тот же
// протокол, та же логика.

static void print_ip(unsigned int ip) {
    ax_printf("%u.%u.%u.%u", (ip >> 24) & 0xFF, (ip >> 16) & 0xFF,
              (ip >> 8) & 0xFF, ip & 0xFF);
}

// Разбирает "GET /путь HTTP/1.x\r\n..." - интересует только путь из первой
// строки, остальные заголовки для отдачи статического файла не нужны.
static int parse_request_path(const unsigned char *req, unsigned int len,
                               char *path_out, unsigned int max_path) {
    if (len < 5 || req[0] != 'G' || req[1] != 'E' || req[2] != 'T' || req[3] != ' ') return 0;
    unsigned int i = 4, pi = 0;
    while (i < len && req[i] != ' ' && req[i] != '\r' && req[i] != '\n' && pi < max_path - 1) {
        path_out[pi++] = (char)req[i];
        i++;
    }
    path_out[pi] = 0;
    return 1;
}

int main(int argc, char** argv) {
    (void)argc; (void)argv;

    unsigned char mac[6];
    if (!ax_net_mac(mac)) {
        ax_print("httpsrv: no NIC found (need -device virtio-net-pci)\n");
        return 1;
    }

    ax_print("httpsrv: serving FAT12 files on port 80 (\"/\" -> INDEX.HTM)\n");

    for (;;) {
        static tcp_conn_t conn;
        if (!tcp_accept(&conn, 80, 30000)) continue;   // никто не подключился за 30с - слушаем дальше

        ax_print("httpsrv: client connected from ");
        print_ip(conn.remote_ip);
        ax_print("\n");

        static unsigned char req[512];
        int n = tcp_recv(&conn, req, sizeof(req) - 1, 3000);
        if (n > 0) {
            static char path[64];
            if (parse_request_path(req, (unsigned int)n, path, sizeof(path))) {
                ax_printf("httpsrv: GET %s\n", path);

                const char *fname = (path[0] == '\0' || (path[0] == '/' && path[1] == '\0'))
                                     ? "INDEX.HTM" : path + 1;

                int fd = ax_open((char*)fname, 0);
                if (fd >= 0) {
                    static unsigned char filebuf[8192];
                    int flen = 0, r;
                    while (flen < (int)sizeof(filebuf) &&
                           (r = ax_fread(fd, filebuf + flen, sizeof(filebuf) - (unsigned int)flen)) > 0) {
                        flen += r;
                    }
                    ax_close(fd);

                    static char header[128];
                    int hlen = 0;
                    const char *h1 = "HTTP/1.0 200 OK\r\nContent-Type: text/html\r\nContent-Length: ";
                    for (const char *p = h1; *p; p++) header[hlen++] = *p;
                    {
                        char dec[12]; int di = 0; unsigned int v = (unsigned int)flen;
                        if (!v) dec[di++] = '0';
                        while (v) { dec[di++] = (char)('0' + v % 10); v /= 10; }
                        for (int a = 0, b = di - 1; a < b; a++, b--) { char t = dec[a]; dec[a] = dec[b]; dec[b] = t; }
                        for (int i = 0; i < di; i++) header[hlen++] = dec[i];
                    }
                    const char *h2 = "\r\nConnection: close\r\n\r\n";
                    for (const char *p = h2; *p; p++) header[hlen++] = *p;

                    tcp_send(&conn, header, (unsigned int)hlen);
                    int sent = 0;
                    while (sent < flen) {
                        int chunk = flen - sent;
                        if (chunk > 512) chunk = 512;
                        tcp_send(&conn, filebuf + sent, (unsigned int)chunk);
                        sent += chunk;
                    }
                    ax_printf("httpsrv: 200 OK, sent %d bytes\n", flen);
                } else {
                    static const char not_found[] =
                        "HTTP/1.0 404 Not Found\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\nNot Found\n";
                    tcp_send(&conn, not_found, sizeof(not_found) - 1);
                    ax_print("httpsrv: 404 Not Found\n");
                }
            }
        }
        tcp_close(&conn);
        ax_print("httpsrv: connection closed\n\n");
    }
    return 0;
}
