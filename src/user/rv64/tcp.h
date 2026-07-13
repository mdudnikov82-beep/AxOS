#pragma once

// Минимальный TCP (RFC 793) поверх udp.h/arp.h - и клиент (активное
// открытие, tcp_connect), и теперь сервер (пассивное открытие, tcp_accept).
// Только "счастливый путь" одного соединения за раз: three-way handshake,
// отправка/приём данных (с ретрансмитом по таймауту - см. TCP_RTO_MS
// ниже), four-way close. Сознательно НЕ реализовано (это уже принципиально
// другой, намного больший объём работы, если вообще понадобится):
// управление окном/congestion control, переупорядочивание сегментов
// (segment out of order), SACK. Локальный порт клиента зафиксирован (как
// xid в dhcp.h) - раз соединение всегда одно, выделять его динамически
// незачем.
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

// Ретрансмит по таймауту: RTO (retransmission timeout) стартует с
// TCP_RTO_MS и УДВАИВАЕТСЯ после каждой неудачной попытки (классический
// exponential backoff), с потолком TCP_RTO_MAX_MS - без потолка на
// действительно плохой сети RTO быстро вырос бы до нескольких минут на
// одну попытку. TCP_MAX_RETRIES - сколько раз повторить ПОСЛЕ первой
// отправки, прежде чем сдаться (для tcp_send() - используется отдельно
// от timeout_ms у tcp_connect()/tcp_accept(), у которых ретрансмит
// происходит ВНУТРИ уже существующего общего окна ожидания, не поверх
// него - число попыток там получается из timeout_ms/RTO само по себе).
#define TCP_RTO_MS       300
#define TCP_RTO_MAX_MS   2000
#define TCP_MAX_RETRIES  5

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
    c->snd_nxt     = net_rand32();   // случайный ISN (RFC 6528) - защита от TCP session hijacking/spoofing
    c->rcv_nxt     = 0;
    c->connected   = 0;
    c->peer_closed = 0;

    unsigned int isn = c->snd_nxt;
    unsigned int rto = TCP_RTO_MS;
    unsigned int elapsed = 0;
    tcp_send_segment(c, TCP_FLAG_SYN, 0, 0);

    while (elapsed < timeout_ms) {
        unsigned int waited = 0;
        while (waited < rto && elapsed < timeout_ms) {
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
            elapsed += 10;
        }
        // RTO истёк, а SYN+ACK не пришёл - возможно, наш SYN потерялся:
        // повторяем его (общий бюджет timeout_ms не расширяется).
        if (elapsed < timeout_ms) {
            tcp_send_segment(c, TCP_FLAG_SYN, 0, 0);
            rto *= 2;
            if (rto > TCP_RTO_MAX_MS) rto = TCP_RTO_MAX_MS;
        }
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
            unsigned int isn = net_rand32();   // случайный server ISN (RFC 6528)
            c->snd_nxt = isn;
            tcp_send_segment(c, TCP_FLAG_SYN | TCP_FLAG_ACK, 0, 0);

            // Ждём финальный ACK клиента отдельным (более коротким) таймаутом -
            // клиент, только что получивший наш SYN-ACK, отвечает почти сразу.
            // Если наш SYN-ACK потерялся, клиент никогда не увидит его и не
            // ответит - повторяем SYN-ACK по RTO, пока не истёк общий w2-бюджет.
            unsigned int rto = TCP_RTO_MS;
            unsigned int w2 = 0;
            while (w2 < 3000) {
                unsigned int inner = 0;
                while (inner < rto && w2 < 3000) {
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
                    inner += 10;
                    w2 += 10;
                }
                if (w2 < 3000) {
                    tcp_send_segment(c, TCP_FLAG_SYN | TCP_FLAG_ACK, 0, 0);
                    rto *= 2;
                    if (rto > TCP_RTO_MAX_MS) rto = TCP_RTO_MAX_MS;
                }
            }
            return 0;   // SYN-ACK ушёл (и был повторён), но клиент не завершил handshake вовремя
        }
        sleep_ms(10);
        waited += 10;
    }
    return 0;
}

// Шлёт данные (PSH+ACK) одним сегментом, макс. 512 байт, и ждёт ACK,
// повторяя отправку (тот же уже собранный tcp_tx, просто ещё раз net_send())
// по RTO с exponential backoff до TCP_MAX_RETRIES раз. 0 - подтверждено,
// -1 - собеседник не подключен/данные слишком длинные/ACK так и не пришёл
// (соединение, скорее всего, мертво - c->snd_nxt НЕ продвигается в этом
// случае, чтобы не расходиться с тем, что реально видел собеседник).
//
// ПРИМЕЧАНИЕ: пока идёт это ожидание, входящие сегменты С ДАННЫМИ (не
// ACK для нас) молча отбрасываются - как и раньше, эта "happy path"
// реализация подразумевает строгий request/response (никто не шлёт нам
// данные, пока мы не получили ответ на свои), это верно для всех
// сегодняшних потребителей (tcptest.c/httpget.c/tcpserve.c).
static int tcp_send(tcp_conn_t *c, const void *data, unsigned int len) {
    if (!c->connected) return -1;
    if (len > 512) return -1;

    unsigned int expect_ack = c->snd_nxt + len;
    unsigned int rto = TCP_RTO_MS;

    for (int attempt = 0; attempt <= TCP_MAX_RETRIES; attempt++) {
        tcp_send_segment(c, TCP_FLAG_PSH | TCP_FLAG_ACK, data, len);

        unsigned int waited = 0;
        while (waited < rto) {
            unsigned int n = net_recv(tcp_rx, sizeof(tcp_rx));
            tcp_seg_t seg;
            if (n > 0 && tcp_parse_segment(n, &seg) &&
                seg.src_ip == c->remote_ip && seg.src_port == c->remote_port &&
                seg.dst_port == c->local_port && (seg.flags & TCP_FLAG_ACK) &&
                (int)(seg.ack - expect_ack) >= 0) {   // seg.ack >= expect_ack, safe через переполнение seq
                c->snd_nxt = expect_ack;
                return 0;
            }
            sleep_ms(10);
            waited += 10;
        }
        rto *= 2;
        if (rto > TCP_RTO_MAX_MS) rto = TCP_RTO_MAX_MS;
    }
    return -1;
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

// Four-way close: шлём FIN+ACK и ждём ACK за него, повторяя отправку по
// RTO с exponential backoff (тот же паттерн, что и у tcp_send()) до
// TCP_MAX_RETRIES раз, вместо одного ретрансмита на середине фиксированного
// окна. Останавливается, как только пришёл ACK, покрывающий наш FIN
// (`seg.ack >= expect_ack`, wrap-safe) - не обязательно ждать ещё и FIN
// собеседника (обычно он и так уже закрыл свою половину раньше, см.
// peer_closed). Если ACK так и не пришёл за все попытки - всё равно
// считаем соединение закрытым локально (happy path, RST не обрабатываем).
static void tcp_close(tcp_conn_t *c) {
    if (!c->connected) return;

    unsigned int expect_ack = c->snd_nxt + 1;   // FIN потребляет один номер последовательности
    tcp_send_segment(c, TCP_FLAG_FIN | TCP_FLAG_ACK, 0, 0);

    unsigned int rto = TCP_RTO_MS;
    int acked = 0;
    for (int attempt = 0; attempt <= TCP_MAX_RETRIES && !acked; attempt++) {
        unsigned int waited = 0;
        while (waited < rto) {
            unsigned int n = net_recv(tcp_rx, sizeof(tcp_rx));
            tcp_seg_t seg;
            if (n > 0 && tcp_parse_segment(n, &seg) &&
                seg.src_ip == c->remote_ip && seg.src_port == c->remote_port &&
                seg.dst_port == c->local_port && (seg.flags & TCP_FLAG_ACK) &&
                (int)(seg.ack - expect_ack) >= 0) {
                acked = 1;
                break;
            }
            sleep_ms(10);
            waited += 10;
        }
        if (!acked && attempt < TCP_MAX_RETRIES) {
            tcp_send_segment(c, TCP_FLAG_FIN | TCP_FLAG_ACK, 0, 0);
            rto *= 2;
            if (rto > TCP_RTO_MAX_MS) rto = TCP_RTO_MAX_MS;
        }
    }
    c->snd_nxt = expect_ack;
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
// tcp_mux_poll() = одна попытка net_recv() (один входящий кадр) плюс
// проверка таймеров ретрансмита ВСЕХ слотов (не только того, кого
// затронул пришедший кадр, если он вообще пришёл) - вызывающий код сам
// гоняет цикл, вызывая poll() снова и снова (как и весь остальной этот
// "стек" - однопоточный, кооперативный, без реальных прерываний на
// уровне TCP). Как и everywhere else в tcp.h - только "счастливый путь":
// handshake ретранслирует SYN-ACK при повторном SYN от клиента (см.
// TCP_SLOT_SYN_RCVD ниже), а данные после установления соединения
// (tcp_mux_send()) идут через собственную НЕБЛОКИРУЮЩУЮ очередь на слот
// (outbuf/out_* поля tcp_slot_t, см. tcp_mux_pump() ниже) с тем же RTO-
// ретрансмитом, что и у однослотового tcp_send() - разница в том, что
// ожидание ACK и повтор происходят МЕЖДУ вызовами tcp_mux_poll(), а не
// внутри одного блокирующего вызова, иначе один медленный/потерянный
// клиент держал бы все остальные слоты. FIN тоже ретранслируется по
// полному RTO-backoff (см. tcp_mux_start_closing() ниже - переиспользует
// те же out_retries/out_rto/out_rto_deadline, что и данные, раз к
// моменту закрытия очередь данных уже пуста). Также нет ни
// переупорядочивания сегментов, ни SYN-flood защиты - только таймаут на
// подвисший SYN_RCVD (`deadline`, фиксированные 3с), чтобы не отъедал
// слот навсегда.
#define TCP_MAX_CONNS 4

// Размер исходящей очереди на слот - с запасом под самый большой
// сегодняшний ответ (httpsrv.c: HTTP-заголовок ~130Б + до 8192Б файла из
// filebuf). Если httpsrv.c когда-нибудь станет отдавать файлы крупнее -
// тут тоже нужно будет вырасти, автоматической синхронизации размеров нет.
#define TCP_MUX_OUT_BUF_SIZE 8320

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

    // Исходящая очередь для неблокирующего tcp_mux_send() - см. коммент
    // выше tcp_mux_pump(). Инвариант: outbuf[0..out_acked) уже подтверждено
    // ACK-ом, outbuf[out_acked..out_acked+out_inflight) - текущий сегмент
    // в полёте (ждёт ACK), outbuf[out_acked+out_inflight..out_len) - ещё
    // не отправлено.
    unsigned char  outbuf[TCP_MUX_OUT_BUF_SIZE];
    unsigned int   out_len;
    unsigned int   out_acked;
    unsigned int   out_inflight;
    unsigned int   out_retries;
    unsigned int   out_rto;
    unsigned long  out_rto_deadline;
    int            close_after;   // 1 = tcp_mux_close() вызван, пока очередь не опустела - FIN отложен
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

// Шлёт FIN и переводит слот в CLOSING с инициализированным RTO-таймером
// для ретрансмита самого FIN (тот же паттерн, что и у tcp_send()/RTO-
// ретрансмита данных выше - переиспользует out_retries/out_rto/
// out_rto_deadline: к этому моменту исходящая очередь данных уже пуста
// (см. вызовы ниже), эти поля больше ничем не заняты).
//
// ВАЖНО: conn.snd_nxt НЕ увеличивается здесь (в отличие от однослотового
// tcp_close(), где инкремент тоже отложен до конца всех попыток) - если
// сдвинуть его сразу, повтор из RTO-свипа в tcp_mux_poll() соберёт
// СЛЕДУЮЩИЙ (seq+1) сегмент вместо настоящего повтора ТОГО ЖЕ FIN
// (реальный баг, пойманный вживую - см. память project_tcp_mux_send_retransmit).
// Слот в любом случае освобождается сразу после подтверждения закрытия
// (см. TCP_SLOT_CLOSING в tcp_mux_poll() ниже) - корректировать snd_nxt
// впрок незачем, новый клиент на этом слоте получит свой ISN заново.
static void tcp_mux_start_closing(tcp_slot_t *s) {
    tcp_send_segment(&s->conn, TCP_FLAG_FIN | TCP_FLAG_ACK, 0, 0);
    s->state            = TCP_SLOT_CLOSING;
    s->out_retries      = 0;
    s->out_rto          = TCP_RTO_MS;
    s->out_rto_deadline = (unsigned long)gettime() + (unsigned long)TCP_RTO_MS * 10000UL;
}

// Пытается протолкнуть следующий кусок исходящей очереди слота idx, если
// сейчас ничего не в полёте. НЕ блокирует - если предыдущий сегмент ещё
// не подтверждён ACK-ом, просто выходит (ретрансмит/следующий кусок
// произойдёт позже через tcp_mux_poll()). Если очередь опустела и было
// запрошено закрытие (tcp_mux_close() при непустой очереди - см. ниже),
// шлёт отложенный FIN и переводит слот в CLOSING. Вызывается и из
// tcp_mux_send() (чтобы первый кусок ушёл сразу же, без задержки до
// следующего poll()), и из tcp_mux_poll() (когда пришёл ACK за текущий
// сегмент - сразу пробуем следующий, не дожидаясь ещё одного poll()).
static void tcp_mux_pump(int idx) {
    tcp_slot_t *s = &tcp_slots[idx];
    if (s->state != TCP_SLOT_ESTABLISHED) return;
    if (s->out_inflight > 0) return;   // уже что-то ждёт ACK - не начинаем новый сегмент

    unsigned int remaining = s->out_len - s->out_acked;
    if (remaining == 0) {
        if (s->close_after) {
            tcp_mux_start_closing(s);
            s->close_after = 0;
        }
        return;
    }

    unsigned int chunk = remaining;
    if (chunk > 512) chunk = 512;
    tcp_send_segment(&s->conn, TCP_FLAG_PSH | TCP_FLAG_ACK, s->outbuf + s->out_acked, chunk);
    s->out_inflight     = chunk;
    s->out_retries      = 0;
    s->out_rto          = TCP_RTO_MS;
    s->out_rto_deadline = (unsigned long)gettime() + (unsigned long)TCP_RTO_MS * 10000UL;
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
        if (tcp_slots[i].state == TCP_SLOT_SYN_RCVD && now >= tcp_slots[i].deadline) {
            tcp_slots[i].state = TCP_SLOT_FREE;
        }
        if (tcp_slots[i].state == TCP_SLOT_CLOSING && now >= tcp_slots[i].out_rto_deadline) {
            if (tcp_slots[i].out_retries >= TCP_MAX_RETRIES) {
                // Собеседник так и не подтвердил закрытие за все попытки -
                // всё равно освобождаем слот (happy path, дальше не ждём).
                tcp_slots[i].state = TCP_SLOT_FREE;
            } else {
                tcp_send_segment(&tcp_slots[i].conn, TCP_FLAG_FIN | TCP_FLAG_ACK, 0, 0);
                tcp_slots[i].out_retries++;
                tcp_slots[i].out_rto *= 2;
                if (tcp_slots[i].out_rto > TCP_RTO_MAX_MS) tcp_slots[i].out_rto = TCP_RTO_MAX_MS;
                tcp_slots[i].out_rto_deadline = now + (unsigned long)tcp_slots[i].out_rto * 10000UL;
            }
        }
        if (tcp_slots[i].state == TCP_SLOT_ESTABLISHED && tcp_slots[i].out_inflight > 0 &&
            now >= tcp_slots[i].out_rto_deadline) {
            if (tcp_slots[i].out_retries >= TCP_MAX_RETRIES) {
                // Собеседник не отвечает на исходящие данные - считаем
                // соединение мёртвым, освобождаем слот для новых клиентов.
                tcp_slots[i].state = TCP_SLOT_FREE;
            } else {
                tcp_send_segment(&tcp_slots[i].conn, TCP_FLAG_PSH | TCP_FLAG_ACK,
                                  tcp_slots[i].outbuf + tcp_slots[i].out_acked, tcp_slots[i].out_inflight);
                tcp_slots[i].out_retries++;
                tcp_slots[i].out_rto *= 2;
                if (tcp_slots[i].out_rto > TCP_RTO_MAX_MS) tcp_slots[i].out_rto = TCP_RTO_MAX_MS;
                tcp_slots[i].out_rto_deadline = now + (unsigned long)tcp_slots[i].out_rto * 10000UL;
            }
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
            s->conn.snd_nxt     = net_rand32();   // случайный ISN (RFC 6528) - независим для каждого слота уже сам по себе
            s->conn.connected   = 0;
            s->conn.peer_closed = 0;
            s->reqlen  = 0;
            s->out_len       = 0;
            s->out_acked     = 0;
            s->out_inflight  = 0;
            s->out_retries   = 0;
            s->close_after   = 0;
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
        } else if ((seg.flags & TCP_FLAG_SYN) && !(seg.flags & TCP_FLAG_ACK)) {
            // Клиент повторил SYN (не увидел наш SYN-ACK, потерянный в
            // одну сторону) - слот для него уже нашёлся выше по
            // remote_ip/port, просто шлём SYN-ACK ещё раз, не заводя
            // новый слот и не трогая deadline (тот же 3с бюджет на весь
            // handshake, включая ретраи).
            tcp_send_segment(&s->conn, TCP_FLAG_SYN | TCP_FLAG_ACK, 0, 0);
        }
        return -1;
    }

    if (s->state == TCP_SLOT_ESTABLISHED) {
        // ACK за наш текущий исходящий сегмент (если есть) - обрабатывается
        // НЕЗАВИСИМО от seg.seq ниже (ack/seq - разные направления одного
        // соединения; устаревший/непорядковый seq входящих данных не
        // должен блокировать зачёт валидного ACK за то, что отправили мы).
        if (s->out_inflight > 0 && (seg.flags & TCP_FLAG_ACK) &&
            (int)(seg.ack - (s->conn.snd_nxt + s->out_inflight)) >= 0) {
            s->conn.snd_nxt += s->out_inflight;
            s->out_acked    += s->out_inflight;
            s->out_inflight  = 0;
            // Компактируем буфер - сдвигаем ещё не отправленный хвост к
            // началу. outbuf НЕ кольцевой, out_len/out_acked иначе росли
            // бы монотонно всю жизнь соединения - без этого сдвига после
            // TCP_MUX_OUT_BUF_SIZE суммарно отправленных+подтверждённых
            // байт ЛЮБОЙ новый tcp_mux_send() отказывал бы НАВСЕГДА, даже
            // если реального свободного места в буфере полно.
            if (s->out_acked > 0) {
                unsigned int remaining_len = s->out_len - s->out_acked;
                for (unsigned int i = 0; i < remaining_len; i++) s->outbuf[i] = s->outbuf[s->out_acked + i];
                s->out_len   = remaining_len;
                s->out_acked = 0;
            }
            tcp_mux_pump(idx);   // сразу пробуем следующий кусок/отложенный FIN
        }

        if (seg.seq != s->conn.rcv_nxt) return -1;   // не тот сегмент - игнорируем (без переупорядочивания входящих)

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
        // Любой пакет от собеседника здесь (их FIN, ACK за наш FIN, или
        // и то и другое сразу) считается подтверждением закрытия - слот
        // освобождается сразу, не дожидаясь оставшихся RTO-попыток сверху.
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

// Ставит данные в очередь на отправку слоту idx (может быть длиннее 512 -
// уйдёт несколькими сегментами). НЕ БЛОКИРУЕТ и не ждёт ACK здесь: данные
// копируются в собственный буфер слота (outbuf) и уходят кусками по мере
// подтверждения предыдущих через tcp_mux_poll() (см. tcp_mux_pump() выше),
// с ретрансмитом по RTO при потере - тот же паттерн, что и у однослотового
// tcp_send(), только растянутый на несколько вызовов poll() вместо одного
// блокирующего ожидания, чтобы не задерживать остальные слоты. Первый
// кусок уходит сразу же (если слот сейчас ничем не занят), остальные - по
// мере продвижения очереди. Возвращает 0, если данные приняты в очередь,
// -1 если слот не в ESTABLISHED или очередь переполнена
// (TCP_MUX_OUT_BUF_SIZE).
static int tcp_mux_send(int idx, const void *data, unsigned int len) {
    tcp_slot_t *s = &tcp_slots[idx];
    if (s->state != TCP_SLOT_ESTABLISHED) return -1;
    if (s->out_len + len > TCP_MUX_OUT_BUF_SIZE) return -1;

    const unsigned char *p = (const unsigned char *)data;
    for (unsigned int i = 0; i < len; i++) s->outbuf[s->out_len + i] = p[i];
    s->out_len += len;

    tcp_mux_pump(idx);
    return 0;
}

// Инициирует закрытие слота idx. Если исходящая очередь уже пуста и
// ничего не ждёт ACK - шлёт FIN сразу же (как раньше). Если ещё остались
// неотправленные/неподтверждённые данные - откладывает FIN до тех пор,
// пока вся очередь не будет доставлена (tcp_mux_pump() отправит его сам,
// когда out_acked догонит out_len) - иначе FIN обогнал бы данные и
// оборвал бы ответ раньше времени.
static void tcp_mux_close(int idx) {
    tcp_slot_t *s = &tcp_slots[idx];
    if (s->state != TCP_SLOT_ESTABLISHED) return;

    if (s->out_inflight > 0 || s->out_acked < s->out_len) {
        s->close_after = 1;
        return;
    }

    tcp_mux_start_closing(s);
}
