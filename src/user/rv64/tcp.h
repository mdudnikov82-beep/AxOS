#pragma once

// Минимальный TCP-КЛИЕНТ (RFC 793) поверх udp.h/arp.h. Только "счастливый
// путь" одного исходящего соединения за раз: three-way handshake, отправка/
// приём данных, four-way close. Сознательно НЕ реализовано (это уже
// принципиально другой, намного больший объём работы, если вообще
// понадобится): ретрансмит по таймауту, управление окном/congestion
// control, одновременные соединения, приём ВХОДЯЩИХ соединений (TCP-сервер).
// Раз соединение всегда одно, локальный порт зафиксирован, а не выделяется
// динамически - как xid в dhcp.h.
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

#define TCP_LOCAL_PORT 40000   // одно соединение за раз - фиксированный порт
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

// Three-way handshake: SYN -> ждём SYN+ACK -> ACK. При успехе c->connected=1.
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
        if (n >= 14 + 20 + 20 && tcp_rx[12] == 0x08 && tcp_rx[13] == 0x00) {
            unsigned char *iph = tcp_rx + 14;
            if (iph[9] == IP_PROTO_TCP) {
                unsigned int ihl = (unsigned int)(iph[0] & 0x0F) * 4;
                unsigned char *tcph = iph + ihl;
                unsigned int src_port = ((unsigned int)tcph[0] << 8) | tcph[1];
                unsigned int dst_port = ((unsigned int)tcph[2] << 8) | tcph[3];
                unsigned int seq = ((unsigned int)tcph[4] << 24) | ((unsigned int)tcph[5] << 16) |
                                   ((unsigned int)tcph[6] << 8)  |  (unsigned int)tcph[7];
                unsigned char flags = tcph[13];
                unsigned int src_ip = ((unsigned int)iph[12] << 24) | ((unsigned int)iph[13] << 16) |
                                      ((unsigned int)iph[14] << 8)  |  (unsigned int)iph[15];

                if (src_ip == c->remote_ip && src_port == c->remote_port && dst_port == c->local_port &&
                    (flags & TCP_FLAG_SYN) && (flags & TCP_FLAG_ACK)) {
                    c->rcv_nxt = seq + 1;      // SYN потребляет один номер последовательности
                    c->snd_nxt = isn + 1;
                    tcp_send_segment(c, TCP_FLAG_ACK, 0, 0);
                    c->connected = 1;
                    return 1;
                }
            }
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
        if (n >= 14 + 20 + 20 && tcp_rx[12] == 0x08 && tcp_rx[13] == 0x00) {
            unsigned char *iph = tcp_rx + 14;
            if (iph[9] == IP_PROTO_TCP) {
                unsigned int ihl = (unsigned int)(iph[0] & 0x0F) * 4;
                unsigned char *tcph = iph + ihl;
                unsigned int src_port = ((unsigned int)tcph[0] << 8) | tcph[1];
                unsigned int dst_port = ((unsigned int)tcph[2] << 8) | tcph[3];
                unsigned int seq = ((unsigned int)tcph[4] << 24) | ((unsigned int)tcph[5] << 16) |
                                   ((unsigned int)tcph[6] << 8)  |  (unsigned int)tcph[7];
                unsigned char flags = tcph[13];
                unsigned int src_ip = ((unsigned int)iph[12] << 24) | ((unsigned int)iph[13] << 16) |
                                      ((unsigned int)iph[14] << 8)  |  (unsigned int)iph[15];
                unsigned int ip_total = ((unsigned int)iph[2] << 8) | iph[3];
                unsigned int tcp_hlen = (unsigned int)((tcph[12] >> 4) & 0x0F) * 4;

                if (src_ip == c->remote_ip && src_port == c->remote_port &&
                    dst_port == c->local_port && seq == c->rcv_nxt) {
                    unsigned int seg_len  = (ip_total > ihl) ? (ip_total - ihl) : 0;
                    unsigned int data_len = (seg_len > tcp_hlen) ? (seg_len - tcp_hlen) : 0;
                    unsigned int avail = (n > 14 + ihl + tcp_hlen) ? (n - (14 + ihl + tcp_hlen)) : 0;
                    if (data_len > avail) data_len = avail;
                    if (data_len > max_len) data_len = max_len;

                    unsigned char *data = tcph + tcp_hlen;
                    unsigned char *dst = (unsigned char *)buf;
                    for (unsigned int i = 0; i < data_len; i++) dst[i] = data[i];

                    c->rcv_nxt += data_len;
                    if (flags & TCP_FLAG_FIN) { c->rcv_nxt += 1; c->peer_closed = 1; }

                    if (data_len > 0 || (flags & TCP_FLAG_FIN)) {
                        tcp_send_segment(c, TCP_FLAG_ACK, 0, 0);
                    }

                    if (data_len > 0) return (int)data_len;
                    if (c->peer_closed) return -1;   // connected остаётся true - tcp_close() ещё должен отправить наш FIN
                    // чистый ACK без данных - продолжаем ждать
                }
            }
        }
        sleep_ms(10);
        waited += 10;
    }
    return 0;
}

// Four-way close: шлём FIN+ACK, недолго слушаем финальный ACK/FIN
// собеседника (без повторной отправки при таймауте - минимальное
// упрощение, обычно сервер и так уже закрыл свою половину к этому моменту).
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
