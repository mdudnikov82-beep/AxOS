#pragma once

// Минимальный TCP (RFC 793) поверх udp.h/arp.h - и клиент (активное
// открытие, tcp_connect), и теперь сервер (пассивное открытие, tcp_accept).
// Только "счастливый путь" одного соединения за раз: three-way handshake,
// отправка/приём данных, four-way close. Сознательно НЕ реализовано (это
// уже принципиально другой, намного больший объём работы, если вообще
// понадобится): ретрансмит по таймауту, управление окном/congestion
// control, несколько ОДНОВРЕМЕННЫХ соединений/полноценный accept-backlog.
// Локальный порт клиента зафиксирован (как xid в dhcp.h) - раз соединение
// всегда одно, выделять его динамически незачем.
//
// В отличие от UDP, TCP-чексумма ОБЯЗАТЕЛЬНА (RFC 793) - настоящий стек на
// другом конце молча дропнет сегмент с неверной суммой. Считается по
// псевдозаголовку (src/dst IP, protocol, TCP-длина) + сам сегмент.

#include "udp.h"

#define TCP_FLAG_FIN 0x01
#define TCP_FLAG_SYN 0x02
#define TCP_FLAG_RST 0x04
#define TCP_FLAG_PSH 0x08
#define TCP_FLAG_ACK 0x10

#define TCP_LOCAL_PORT 40000   // клиент: одно соединение за раз - фиксированный порт
#define IP_PROTO_TCP   6

typedef struct {
    unsigned int   remote_ip;
    unsigned short remote_port;
    unsigned short local_port;
    unsigned char  remote_mac[6];
    unsigned char  my_mac[6];
    unsigned int   snd_nxt;      // следующий наш seq
    unsigned int   rcv_nxt;      // следующий ожидаемый seq от собеседника (= ack, который шлём)
    int            connected;    // true с успешного handshake до НАШЕГО tcp_close()
    int            peer_closed;  // true после того, как увидели и подтвердили FIN собеседника -
                                  // означает "новых данных больше не будет", НЕ "соединение мертво":
                                  // tcp_close() всё ещё должен отправить наш собственный FIN
} tcp_conn_t;

// Разобранный входящий сегмент - общий формат для tcp_connect/tcp_accept/
// tcp_recv, чтобы разбор IP+TCP заголовков (с учётом переменного IHL/data
// offset) не дублировался трижды с риском разъехаться в деталях, как уже
// однажды случилось с ARP-офсетами в arp.h.
typedef struct {
    unsigned int   src_ip;
    unsigned int   src_port;
    unsigned int   dst_port;
    unsigned int   seq;
    unsigned int   ack;
    unsigned char  flags;
    unsigned char *data;
    unsigned int   data_len;
} tcp_seg_t;

static unsigned char tcp_tx[14 + 20 + 20 + 512];
static unsigned char tcp_rx[1500];

// Псевдозаголовок (12Б) + сегмент во временный буфер - тот же ip_checksum(),
// что и у IP/ICMP, просто над другими данными.
static unsigned short tcp_checksum(unsigned int src_ip, unsigned int dst_ip,
                                    const unsigned char *seg, unsigned int seg_len) {
    static unsigned char buf[12 + 20 + 512];
    unsigned char *p = buf;
    p[0] = (unsigned char)(src_ip >> 24); p[1] = (unsigned char)(src_ip >> 16);
    p[2] = (unsigned char)(src_ip >> 8);  p[3] = (unsigned char)src_ip;
    p[4] = (unsigned char)(dst_ip >> 24); p[5] = (unsigned char)(dst_ip >> 16);
    p[6] = (unsigned char)(dst_ip >> 8);  p[7] = (unsigned char)dst_ip;
    p[8] = 0; p[9] = IP_PROTO_TCP;
    p[10] = (unsigned char)(seg_len >> 8); p[11] = (unsigned char)seg_len;
    for (unsigned int i = 0; i < seg_len; i++) p[12 + i] = seg[i];
    return ip_checksum(buf, 12 + seg_len);
}

// Разбирает tcp_rx[0..n) в *seg. Возвращает 1, если это валидный IPv4/TCP
// кадр (с учётом реального IHL заголовка IP и data offset заголовка TCP -
// оба могут в теории нести опции, хотя мы сами их не отправляем).
// data_len уже обрезан по факту реально принятых байт (n), а не только по
// тому, что заявляют заголовки - как и в udp.h/icmp.h, не доверяем длине
// из самого пакета сверх того, что действительно пришло.
static int tcp_parse_segment(unsigned int n, tcp_seg_t *seg) {
    if (n < 14 + 20 + 20) return 0;
    if (tcp_rx[12] != 0x08 || tcp_rx[13] != 0x00) return 0;   // ethertype != IPv4

    unsigned char *iph = tcp_rx + 14;
    if (iph[9] != IP_PROTO_TCP) return 0;
    unsigned int ihl = (unsigned int)(iph[0] & 0x0F) * 4;
    if (n < 14 + ihl + 20) return 0;

    unsigned char *tcph = iph + ihl;
    unsigned int tcp_hlen = (unsigned int)((tcph[12] >> 4) & 0x0F) * 4;
    if (n < 14 + ihl + tcp_hlen) return 0;

    seg->src_ip = ((unsigned int)iph[12] << 24) | ((unsigned int)iph[13] << 16) |
                 ((unsigned int)iph[14] << 8)  |  (unsigned int)iph[15];
    seg->src_port = ((unsigned int)tcph[0] << 8) | tcph[1];
    seg->dst_port = ((unsigned int)tcph[2] << 8) | tcph[3];
    seg->seq = ((unsigned int)tcph[4] << 24) | ((unsigned int)tcph[5] << 16) |
              ((unsigned int)tcph[6] << 8)  |  (unsigned int)tcph[7];
    seg->ack = ((unsigned int)tcph[8] << 24) | ((unsigned int)tcph[9] << 16) |
              ((unsigned int)tcph[10] << 8) |  (unsigned int)tcph[11];
    seg->flags = tcph[13];

    unsigned int ip_total = ((unsigned int)iph[2] << 8) | iph[3];
    unsigned int seg_len  = (ip_total > ihl) ? (ip_total - ihl) : 0;
    unsigned int data_len = (seg_len > tcp_hlen) ? (seg_len - tcp_hlen) : 0;
    unsigned int avail    = (n > 14 + ihl + tcp_hlen) ? (n - (14 + ihl + tcp_hlen)) : 0;
    if (data_len > avail) data_len = avail;

    seg->data     = tcph + tcp_hlen;
    seg->data_len = data_len;
    return 1;
}

// Собирает и шлёт один TCP-сегмент (Ethernet+IP+TCP, без опций - data
// offset всегда 5/20 байт).
static void tcp_send_segment(tcp_conn_t *c, unsigned char flags,
                              const void *payload, unsigned int len) {
    unsigned char *eth = tcp_tx;
    for (int i = 0; i < 6; i++) eth[i]     = c->remote_mac[i];
    for (int i = 0; i < 6; i++) eth[6 + i] = c->my_mac[i];
    arp__put16be(eth + 12, 0x0800);

    unsigned char *ip  = eth + 14;
    unsigned char *tcp = ip + 20;

    arp__put16be(tcp + 0, c->local_port);
    arp__put16be(tcp + 2, c->remote_port);
    tcp[4] = (unsigned char)(c->snd_nxt >> 24); tcp[5] = (unsigned char)(c->snd_nxt >> 16);
    tcp[6] = (unsigned char)(c->snd_nxt >> 8);  tcp[7] = (unsigned char)c->snd_nxt;
    tcp[8] = (unsigned char)(c->rcv_nxt >> 24); tcp[9] = (unsigned char)(c->rcv_nxt >> 16);
    tcp[10] = (unsigned char)(c->rcv_nxt >> 8); tcp[11] = (unsigned char)c->rcv_nxt;
    tcp[12] = (5 << 4);          // data offset = 5 (20Б, без опций), reserved = 0
    tcp[13] = flags;
    arp__put16be(tcp + 14, 8192);   // window
    tcp[16] = 0; tcp[17] = 0;       // checksum - заполняется ниже
    tcp[18] = 0; tcp[19] = 0;       // urgent pointer

    unsigned char *data = tcp + 20;
    const unsigned char *src = (const unsigned char *)payload;
    for (unsigned int i = 0; i < len; i++) data[i] = src[i];

    unsigned int tcp_len = 20 + len;
    unsigned short csum = tcp_checksum(MY_IP, c->remote_ip, tcp, tcp_len);
    tcp[16] = (unsigned char)(csum >> 8); tcp[17] = (unsigned char)csum;

    unsigned int ip_total = 20 + tcp_len;
    ip[0] = 0x45; ip[1] = 0;
    arp__put16be(ip + 2, ip_total);
    arp__put16be(ip + 4, 0);
    arp__put16be(ip + 6, 0);
    ip[8] = 64; ip[9] = IP_PROTO_TCP;
    ip[10] = 0; ip[11] = 0;
    unsigned int my_ip = MY_IP;
    ip[12] = (unsigned char)(my_ip >> 24); ip[13] = (unsigned char)(my_ip >> 16);
    ip[14] = (unsigned char)(my_ip >> 8);  ip[15] = (unsigned char)my_ip;
    ip[16] = (unsigned char)(c->remote_ip >> 24); ip[17] = (unsigned char)(c->remote_ip >> 16);
    ip[18] = (unsigned char)(c->remote_ip >> 8);  ip[19] = (unsigned char)c->remote_ip;
    arp__put16be(ip + 10, ip_checksum(ip, 20));

    net_send(tcp_tx, 14 + ip_total);
}

// Активное открытие (клиент): SYN -> ждём SYN+ACK -> ACK. При успехе
// c->connected=1.
static int tcp_connect(tcp_conn_t *c, unsigned int ip, unsigned short port,
                        unsigned int timeout_ms) {
    if (!net_mac(c->my_mac)) return 0;
    if (!arp_resolve_next_hop(ip, c->remote_mac, 2000)) return 0;

    c->remote_ip   = ip;
    c->remote_port = port;
    c->local_port  = TCP_LOCAL_PORT;
    c->snd_nxt     = 0x12345678;   // фиксированный ISN - одно соединение за раз, случайность тут не нужна
    c->rcv_nxt     = 0;
    c->connected   = 0;
    c->peer_closed = 0;

    unsigned int isn = c->snd_nxt;
    tcp_send_segment(c, TCP_FLAG_SYN, 0, 0);

    unsigned int waited = 0;
    while (waited < timeout_ms) {
        unsigned int n = net_recv(tcp_rx, sizeof(tcp_rx));
        tcp_seg_t seg;
        if (n > 0 && tcp_parse_segment(n, &seg)) {
            if (seg.src_ip == ip && seg.src_port == port && seg.dst_port == c->local_port &&
                (seg.flags & TCP_FLAG_SYN) && (seg.flags & TCP_FLAG_ACK)) {
                c->rcv_nxt = seg.seq + 1;   // SYN потребляет один номер последовательности
                c->snd_nxt = isn + 1;
                tcp_send_segment(c, TCP_FLAG_ACK, 0, 0);
                c->connected = 1;
                return 1;
            }
        }
        sleep_ms(10);
        waited += 10;
    }
    return 0;
}

// Пассивное открытие (сервер): ждёт ОДИН входящий SYN на local_port,
// отвечает SYN+ACK, ждёт финальный ACK клиента. При успехе c->connected=1,
// c->remote_ip/remote_port/remote_mac - данные подключившегося клиента
// (учатся прямо из его SYN, никакого ARP тут не нужно - мы отвечаем туда
// же, откуда пришёл запрос).
static int tcp_accept(tcp_conn_t *c, unsigned short local_port, unsigned int timeout_ms) {
    if (!net_mac(c->my_mac)) return 0;
    c->local_port  = local_port;
    c->connected   = 0;
    c->peer_closed = 0;

    unsigned int waited = 0;
    while (waited < timeout_ms) {
        unsigned int n = net_recv(tcp_rx, sizeof(tcp_rx));
        if (n == 0) { sleep_ms(10); waited += 10; continue; }

        // Пока сидим тут в ожидании - тоже отвечаем на ARP-запросы нашего
        // MY_IP. Без этого, например, QEMU SLIRP не смог бы доставить
        // hostfwd-переброшенное соединение: прежде чем переслать SYN нам,
        // SLIRP должен узнать наш MAC через ARP - а мы до этого его просто
        // никогда не отправляли (сервер только слушает, никуда не стучится
        // первым), так что SLIRP ещё не успел его "подсмотреть" пассивно,
        // как для клиентских исходящих соединений.
        arp_maybe_respond(tcp_rx, n);

        tcp_seg_t seg;
        if (tcp_parse_segment(n, &seg) &&
            seg.dst_port == local_port &&
            (seg.flags & TCP_FLAG_SYN) && !(seg.flags & TCP_FLAG_ACK)) {

            c->remote_ip   = seg.src_ip;
            c->remote_port = (unsigned short)seg.src_port;
            for (int i = 0; i < 6; i++) c->remote_mac[i] = tcp_rx[6 + i];   // src MAC кадра с SYN
            c->rcv_nxt = seg.seq + 1;
            unsigned int isn = 0x77AA0011;   // фиксированный server ISN - одно соединение за раз
            c->snd_nxt = isn;
            tcp_send_segment(c, TCP_FLAG_SYN | TCP_FLAG_ACK, 0, 0);

            // Ждём финальный ACK клиента отдельным (более коротким) таймаутом -
            // клиент, только что получивший наш SYN-ACK, отвечает почти сразу.
            unsigned int w2 = 0;
            while (w2 < 3000) {
                unsigned int n2 = net_recv(tcp_rx, sizeof(tcp_rx));
                if (n2 > 0) {
                    arp_maybe_respond(tcp_rx, n2);
                    tcp_seg_t seg2;
                    if (tcp_parse_segment(n2, &seg2) &&
                        seg2.src_ip == c->remote_ip && seg2.src_port == c->remote_port &&
                        seg2.dst_port == local_port &&
                        (seg2.flags & TCP_FLAG_ACK) && seg2.ack == isn + 1) {
                        c->snd_nxt = isn + 1;
                        c->connected = 1;
                        return 1;
                    }
                }
                sleep_ms(10);
                w2 += 10;
            }
            return 0;   // SYN-ACK ушёл, но клиент не завершил handshake вовремя
        }
        sleep_ms(10);
        waited += 10;
    }
    return 0;
}

// Шлёт данные (PSH+ACK) одним сегментом, макс. 512 байт. 0/-1.
static int tcp_send(tcp_conn_t *c, const void *data, unsigned int len) {
    if (!c->connected) return -1;
    if (len > 512) return -1;
    tcp_send_segment(c, TCP_FLAG_PSH | TCP_FLAG_ACK, data, len);
    c->snd_nxt += len;
    return 0;
}

// Поллит до timeout_ms. >0 - байт скопировано в buf; 0 - таймаут (ничего в
// этот раз, соединение ещё живо); -1 - собеседник закрыл соединение (FIN
// получен и подтверждён, дальше вызывать не нужно).
static int tcp_recv(tcp_conn_t *c, void *buf, unsigned int max_len, unsigned int timeout_ms) {
    if (c->peer_closed) return -1;   // FIN уже видели раньше - новых данных не будет
    if (!c->connected) return -1;

    unsigned int waited = 0;
    while (waited < timeout_ms) {
        unsigned int n = net_recv(tcp_rx, sizeof(tcp_rx));
        tcp_seg_t seg;
        if (n > 0 && tcp_parse_segment(n, &seg) &&
            seg.src_ip == c->remote_ip && seg.src_port == c->remote_port &&
            seg.dst_port == c->local_port && seg.seq == c->rcv_nxt) {

            unsigned int data_len = seg.data_len;
            if (data_len > max_len) data_len = max_len;
            unsigned char *dst = (unsigned char *)buf;
            for (unsigned int i = 0; i < data_len; i++) dst[i] = seg.data[i];

            c->rcv_nxt += data_len;
            if (seg.flags & TCP_FLAG_FIN) { c->rcv_nxt += 1; c->peer_closed = 1; }

            if (data_len > 0 || (seg.flags & TCP_FLAG_FIN)) {
                tcp_send_segment(c, TCP_FLAG_ACK, 0, 0);
            }

            if (data_len > 0) return (int)data_len;
            if (c->peer_closed) return -1;   // connected остаётся true - tcp_close() ещё должен отправить наш FIN
            // чистый ACK без данных - продолжаем ждать
        }
        sleep_ms(10);
        waited += 10;
    }
    return 0;
}

// Four-way close: шлём FIN+ACK, недолго слушаем финальный ACK/FIN
// собеседника (без повторной отправки при таймауте - минимальное
// упрощение, обычно собеседник и так уже закрыл свою половину к этому
// моменту).
static void tcp_close(tcp_conn_t *c) {
    if (!c->connected) return;
    tcp_send_segment(c, TCP_FLAG_FIN | TCP_FLAG_ACK, 0, 0);
    c->snd_nxt += 1;   // FIN потребляет один номер последовательности

    unsigned int waited = 0;
    while (waited < 500) {
        net_recv(tcp_rx, sizeof(tcp_rx));   // дренируем эфир недолго, не разбираем детально
        sleep_ms(10);
        waited += 10;
    }
    c->connected = 0;
    c->peer_closed = 0;
}

// ---------------------------------------------------------------------
// Многосоединённый сервер (tcp_mux_*) - НЕСКОЛЬКО одновременных клиентов
// на одном слушающем порту, поверх тех же низкоуровневых помощников
// (tcp_send_segment/tcp_parse_segment/ip_checksum/tcp_checksum), что и
// tcp_connect/tcp_accept выше. Те функции ОДНО соединение за раз
// (единственный глобальный tcp_conn_t) остаются как есть, не трогались -
// это отдельный, ДОПОЛНИТЕЛЬНЫЙ API для случая, когда одному серверу
// (например httpsrv.c) нужно обслуживать несколько клиентов сразу, не
// блокируясь на каждом по очереди.
//
// Модель: TCP_MAX_CONNS слотов, каждый - свой tcp_conn_t + маленький
// стейт-машин (SYN_RCVD -> ESTABLISHED -> CLOSING -> FREE). Один вызов
// tcp_mux_poll() = одна попытка net_recv() (один входящий кадр) -
// вызывающий код сам гоняет цикл, вызывая poll() снова и снова (как и
// весь остальной этот "стек" - однопоточный, кооперативный, без реальных
// прерываний на уровне TCP). Как и everywhere else в tcp.h - только
// "счастливый путь": ни ретрансмита, ни переупорядочивания сегментов,
// ни SYN-flood защиты - только таймаут на подвисшие полуоткрытые/
// закрывающиеся слоты, чтобы они не отъедали слот навсегда.
#define TCP_MAX_CONNS 4

typedef enum {
    TCP_SLOT_FREE = 0,
    TCP_SLOT_SYN_RCVD,
    TCP_SLOT_ESTABLISHED,
    TCP_SLOT_CLOSING
} tcp_slot_state_t;

typedef struct {
    tcp_slot_state_t state;
    tcp_conn_t       conn;
    unsigned char    reqbuf[512];
    unsigned int     reqlen;
    unsigned long    deadline;   // gettime() (10МГц CLINT) - для SYN_RCVD/CLOSING, тайм-аут очистки
} tcp_slot_t;

static tcp_slot_t     tcp_slots[TCP_MAX_CONNS];
static unsigned short tcp_mux_local_port;

// Начинает слушать local_port; сбрасывает все слоты (на случай повторного
// вызова - хотя обычно вызывается один раз за всю жизнь программы).
static void tcp_mux_listen(unsigned short local_port) {
    tcp_mux_local_port = local_port;
    for (int i = 0; i < TCP_MAX_CONNS; i++) tcp_slots[i].state = TCP_SLOT_FREE;
}

static int tcp_mux_find(unsigned int remote_ip, unsigned short remote_port) {
    for (int i = 0; i < TCP_MAX_CONNS; i++) {
        if (tcp_slots[i].state != TCP_SLOT_FREE &&
            tcp_slots[i].conn.remote_ip == remote_ip &&
            tcp_slots[i].conn.remote_port == remote_port) {
            return i;
        }
    }
    return -1;
}

static int tcp_mux_find_free(void) {
    for (int i = 0; i < TCP_MAX_CONNS; i++) if (tcp_slots[i].state == TCP_SLOT_FREE) return i;
    return -1;
}

// Один шаг обслуживания: один net_recv(), разбор и продвижение стейт-
// машины ОДНОГО затронутого слота. Возвращает индекс слота, для которого
// только что стал готов ПОЛНЫЙ запрос (reqbuf[0..reqlen) можно разбирать -
// тот же "один tcp_recv() = весь запрос" допущение, что и в исходном
// однослотовом httpsrv.c), иначе -1 (ничего не пришло / кадр не по нашей
// части / это было только рукопожатие или входящий FIN хвоста закрытия).
static int tcp_mux_poll(void) {
    unsigned long now = (unsigned long)gettime();
    for (int i = 0; i < TCP_MAX_CONNS; i++) {
        if ((tcp_slots[i].state == TCP_SLOT_SYN_RCVD || tcp_slots[i].state == TCP_SLOT_CLOSING) &&
            now >= tcp_slots[i].deadline) {
            tcp_slots[i].state = TCP_SLOT_FREE;
        }
    }

    unsigned int n = net_recv(tcp_rx, sizeof(tcp_rx));
    if (n == 0) return -1;

    arp_maybe_respond(tcp_rx, n);   // тот же приём, что и в tcp_accept()

    tcp_seg_t seg;
    if (!tcp_parse_segment(n, &seg)) return -1;
    if (seg.dst_port != tcp_mux_local_port) return -1;

    int idx = tcp_mux_find(seg.src_ip, (unsigned short)seg.src_port);

    if (idx < 0) {
        // Новый клиент - принимаем, только если это чистый SYN и есть
        // свободный слот (иначе молча игнорируем - настоящий клиент
        // повторит SYN, у нас просто нет ретрансмита/backlog).
        if ((seg.flags & TCP_FLAG_SYN) && !(seg.flags & TCP_FLAG_ACK)) {
            int fi = tcp_mux_find_free();
            if (fi < 0) return -1;
            tcp_slot_t *s = &tcp_slots[fi];
            if (!net_mac(s->conn.my_mac)) return -1;
            for (int i = 0; i < 6; i++) s->conn.remote_mac[i] = tcp_rx[6 + i];
            s->conn.remote_ip   = seg.src_ip;
            s->conn.remote_port = (unsigned short)seg.src_port;
            s->conn.local_port  = tcp_mux_local_port;
            s->conn.rcv_nxt     = seg.seq + 1;
            s->conn.snd_nxt     = 0x77AA0011u + (unsigned int)fi * 0x1000u;   // разный ISN на слот
            s->conn.connected   = 0;
            s->conn.peer_closed = 0;
            s->reqlen  = 0;
            s->state   = TCP_SLOT_SYN_RCVD;
            s->deadline = now + 30000000UL;   // 3с (10МГц CLINT) на завершение handshake
            tcp_send_segment(&s->conn, TCP_FLAG_SYN | TCP_FLAG_ACK, 0, 0);
        }
        return -1;
    }

    tcp_slot_t *s = &tcp_slots[idx];

    if (s->state == TCP_SLOT_SYN_RCVD) {
        if ((seg.flags & TCP_FLAG_ACK) && seg.ack == s->conn.snd_nxt + 1) {
            s->conn.snd_nxt  += 1;
            s->conn.connected = 1;
            s->state = TCP_SLOT_ESTABLISHED;
        }
        return -1;
    }

    if (s->state == TCP_SLOT_ESTABLISHED) {
        if (seg.seq != s->conn.rcv_nxt) return -1;   // не тот сегмент - игнорируем (без ретрансмита/переупорядочивания)

        unsigned int room = sizeof(s->reqbuf) - s->reqlen;
        unsigned int copy_len = (seg.data_len > room) ? room : seg.data_len;
        for (unsigned int i = 0; i < copy_len; i++) s->reqbuf[s->reqlen + i] = seg.data[i];
        s->reqlen += copy_len;
        s->conn.rcv_nxt += seg.data_len;
        if (seg.flags & TCP_FLAG_FIN) s->conn.rcv_nxt += 1;

        if (seg.data_len > 0 || (seg.flags & TCP_FLAG_FIN)) {
            tcp_send_segment(&s->conn, TCP_FLAG_ACK, 0, 0);
        }
        if (seg.data_len > 0) return idx;   // запрос готов к разбору
        return -1;
    }

    if (s->state == TCP_SLOT_CLOSING) {
        // Дренируем хвост закрытия (их FIN и/или запоздавший ACK) - тот же
        // смысл, что и у 500мс-дренажа в tcp_close(), только не блокируясь.
        if (seg.data_len > 0 || (seg.flags & TCP_FLAG_FIN)) {
            s->conn.rcv_nxt += seg.data_len;
            if (seg.flags & TCP_FLAG_FIN) s->conn.rcv_nxt += 1;
            tcp_send_segment(&s->conn, TCP_FLAG_ACK, 0, 0);
        }
        s->state = TCP_SLOT_FREE;
        return -1;
    }

    return -1;
}

// Шлёт данные клиенту слота idx (может быть длиннее 512 - разобьётся на
// несколько сегментов сама, как и обычный tcp_send() в цикле вручную).
static int tcp_mux_send(int idx, const void *data, unsigned int len) {
    tcp_slot_t *s = &tcp_slots[idx];
    if (s->state != TCP_SLOT_ESTABLISHED) return -1;
    const unsigned char *p = (const unsigned char *)data;
    unsigned int sent = 0;
    while (sent < len) {
        unsigned int chunk = len - sent;
        if (chunk > 512) chunk = 512;
        tcp_send_segment(&s->conn, TCP_FLAG_PSH | TCP_FLAG_ACK, p + sent, chunk);
        s->conn.snd_nxt += chunk;
        sent += chunk;
    }
    return 0;
}

// Инициирует закрытие слота idx (шлёт FIN, переводит в CLOSING - слот
// освободится либо когда придёт ACK/FIN клиента через tcp_mux_poll(),
// либо по тайм-ауту в 500мс, как и однослотовый tcp_close()).
static void tcp_mux_close(int idx) {
    tcp_slot_t *s = &tcp_slots[idx];
    if (s->state != TCP_SLOT_ESTABLISHED) return;
    tcp_send_segment(&s->conn, TCP_FLAG_FIN | TCP_FLAG_ACK, 0, 0);
    s->conn.snd_nxt += 1;
    s->state    = TCP_SLOT_CLOSING;
    s->deadline = (unsigned long)gettime() + 5000000UL;   // 500мс (10МГц CLINT)
}
