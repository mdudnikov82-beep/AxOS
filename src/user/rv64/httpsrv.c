#include "syscall.h"
#include "tcp.h"

// Минимальный HTTP/1.0-сервер поверх tcp_mux_* (tcp.h): слушает порт 80,
// обслуживает до TCP_MAX_CONNS клиентов ОДНОВРЕМЕННО (не по одному, как
// раньше через tcp_accept()), разбирает первую строку запроса
// ("GET /путь HTTP/1.x"), отдаёт соответствующий файл из FAT12 (пустой
// путь/"/" -> INDEX.HTM) через open()/read()/close(), либо 404. Портирован
// с x86-стороны (src/user/httpsrv.c) - логика та же, только вместо
// блокирующего "принять одного -> обслужить -> закрыть -> принять
// следующего" тут кооперативный цикл tcp_mux_poll(), способный вести
// несколько рукопожатий/запросов вперемешку.

static void print_udec(unsigned long v) {
    char buf[20]; int i = 0;
    if (!v) { write(1, "0", 1); return; }
    while (v) { buf[i++] = '0' + (v % 10); v /= 10; }
    for (int a = 0, b = i - 1; a < b; a++, b--) { char t = buf[a]; buf[a] = buf[b]; buf[b] = t; }
    write(1, buf, i);
}

static void print_ip(unsigned int ip) {
    unsigned char o[4] = { (unsigned char)(ip>>24), (unsigned char)(ip>>16),
                           (unsigned char)(ip>>8), (unsigned char)ip };
    for (int i = 0; i < 4; i++) {
        print_udec(o[i]);
        if (i < 3) write(1, ".", 1);
    }
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

// Разбирает запрос слота idx и шлёт ответ (файл из FAT12 или 404),
// затем инициирует закрытие. Вынесено в отдельную функцию, потому что
// каждый вызов tcp_mux_poll() может вернуть готовность ЛЮБОГО из
// TCP_MAX_CONNS слотов - обработка одного не должна знать о других.
static void handle_request(int idx) {
    tcp_slot_t *s = &tcp_slots[idx];

    static char path[64];
    if (!parse_request_path(s->reqbuf, s->reqlen, path, sizeof(path))) {
        tcp_mux_close(idx);
        return;
    }
    puts_rv("httpsrv: GET ");
    puts_rv(path);
    puts_rv("\r\n");

    const char *fname = (path[0] == '\0' || (path[0] == '/' && path[1] == '\0'))
                         ? "INDEX.HTM" : path + 1;

    int fd = open(fname, 0);
    if (fd >= 0) {
        static unsigned char filebuf[8192];
        int flen = 0, r;
        while (flen < (int)sizeof(filebuf) &&
               (r = (int)read(fd, (char *)filebuf + flen, sizeof(filebuf) - (unsigned int)flen)) > 0) {
            flen += r;
        }
        close(fd);

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

        tcp_mux_send(idx, header, (unsigned int)hlen);
        int sent = 0;
        while (sent < flen) {
            int chunk = flen - sent;
            if (chunk > 512) chunk = 512;
            tcp_mux_send(idx, filebuf + sent, (unsigned int)chunk);
            sent += chunk;
        }
        puts_rv("httpsrv: 200 OK, sent ");
        print_udec((unsigned long)flen);
        puts_rv(" bytes\r\n");
    } else {
        static const char not_found[] =
            "HTTP/1.0 404 Not Found\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\nNot Found\n";
        tcp_mux_send(idx, not_found, sizeof(not_found) - 1);
        puts_rv("httpsrv: 404 Not Found\r\n");
    }
    tcp_mux_close(idx);
}

int main(void) {
    unsigned char mac[6];
    if (!net_mac(mac)) {
        puts_rv("httpsrv: no NIC found (need -device virtio-net-device)\r\n");
        exit(1);
    }

    puts_rv("httpsrv: serving FAT12 files on port 80 (\"/\" -> INDEX.HTM), up to ");
    print_udec(TCP_MAX_CONNS);
    puts_rv(" concurrent connections\r\n");
    tcp_mux_listen(80);

    for (;;) {
        int idx = tcp_mux_poll();
        if (idx < 0) { sleep_ms(5); continue; }   // ничего не готово в этот раз - короткая пауза

        puts_rv("httpsrv: client connected from ");
        print_ip(tcp_slots[idx].conn.remote_ip);
        puts_rv("\r\n");

        handle_request(idx);
        puts_rv("httpsrv: connection closing\r\n\r\n");
    }
    return 0;
}
