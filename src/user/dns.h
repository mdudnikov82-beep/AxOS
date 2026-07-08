#ifndef AXOS_DNS_H
#define AXOS_DNS_H

// Резолв доменного имени -> первый A-адрес (общий случай поверх udp.h;
// dnstest.c делает похожее, но с захардкоженным одноразовым запросом и
// без разбора ответа - тут разбираем ANSWER-секцию по-настоящему, это
// нужно tcp.h/httpget.c, чтобы подключаться к настоящим хостам по имени).
// Портирован с RISC-V стороны (src/user/rv64/dns.h) - тот же протокол,
// та же логика.

#include "udp.h"

#define DNS_PORT 53

static unsigned char dns_tx[300];
static unsigned char dns_rx[512];

// Кодирует hostname в формат DNS QNAME (length-prefixed labels + 0).
// Возвращает длину результата в байтах.
static unsigned int dns_encode_name(const char *hostname, unsigned char *out) {
    unsigned int oi = 0;
    unsigned int label_start = 0;
    unsigned int i = 0;
    while (1) {
        char c = hostname[i];
        if (c == '.' || c == '\0') {
            unsigned int label_len = i - label_start;
            out[oi++] = (unsigned char)label_len;
            for (unsigned int j = label_start; j < i; j++) out[oi++] = (unsigned char)hostname[j];
            label_start = i + 1;
            if (c == '\0') break;
        }
        i++;
    }
    out[oi++] = 0;
    return oi;
}

// Резолвит hostname -> первый A-адрес через dns_server. Понимает сжатие
// имён (указатели 0xC0xx) в ANSWER-секции - реальные серверы почти всегда
// им пользуются вместо повторения полного имени. Возвращает 1/0.
static int dns_resolve_a(const char *hostname, unsigned int dns_server,
                          unsigned int timeout_ms, unsigned int *ip_out) {
    static unsigned short next_id = 0x5AA5;
    unsigned short qid = next_id++;

    dns_tx[0] = (unsigned char)(qid >> 8); dns_tx[1] = (unsigned char)qid;
    dns_tx[2] = 0x01; dns_tx[3] = 0x00;   // flags: стандартный запрос, RD
    dns_tx[4] = 0; dns_tx[5] = 1;          // QDCOUNT = 1
    dns_tx[6] = 0; dns_tx[7] = 0;
    dns_tx[8] = 0; dns_tx[9] = 0;
    dns_tx[10] = 0; dns_tx[11] = 0;

    unsigned int qname_len = dns_encode_name(hostname, dns_tx + 12);
    unsigned int off = 12 + qname_len;
    dns_tx[off++] = 0; dns_tx[off++] = 1;   // QTYPE = A
    dns_tx[off++] = 0; dns_tx[off++] = 1;   // QCLASS = IN

    if (udp_send(dns_server, DNS_PORT, 5354, dns_tx, off) != 0) return 0;

    unsigned int waited = 0;
    while (waited < timeout_ms) {
        unsigned int src_ip; unsigned short src_port, dst_port;
        unsigned int n = udp_recv(&src_ip, &src_port, &dst_port, dns_rx, sizeof(dns_rx));
        if (n >= 12 && dst_port == 5354) {
            unsigned int rid = ((unsigned int)dns_rx[0] << 8) | dns_rx[1];
            unsigned int qdcount = ((unsigned int)dns_rx[4] << 8) | dns_rx[5];
            unsigned int ancount = ((unsigned int)dns_rx[6] << 8) | dns_rx[7];
            if (rid == qid && ancount > 0) {
                unsigned int p = 12;
                for (unsigned int q = 0; q < qdcount && p < n; q++) {
                    if ((dns_rx[p] & 0xC0) == 0xC0) { p += 2; }
                    else { while (p < n && dns_rx[p] != 0) p += dns_rx[p] + 1; p++; }
                    p += 4;   // qtype+qclass
                }
                for (unsigned int a = 0; a < ancount && p + 10 <= n; a++) {
                    if ((dns_rx[p] & 0xC0) == 0xC0) { p += 2; }
                    else { while (p < n && dns_rx[p] != 0) p += dns_rx[p] + 1; p++; }
                    if (p + 10 > n) break;
                    unsigned int rtype = ((unsigned int)dns_rx[p] << 8) | dns_rx[p+1]; p += 2;
                    p += 2;    // class
                    p += 4;    // ttl
                    unsigned int rdlen = ((unsigned int)dns_rx[p] << 8) | dns_rx[p+1]; p += 2;
                    if (rtype == 1 && rdlen == 4 && p + 4 <= n) {
                        *ip_out = ((unsigned int)dns_rx[p] << 24) | ((unsigned int)dns_rx[p+1] << 16) |
                                 ((unsigned int)dns_rx[p+2] << 8)  |  (unsigned int)dns_rx[p+3];
                        return 1;
                    }
                    p += rdlen;
                }
            }
        }
        ax_sleep_ms(10);
        waited += 10;
    }
    return 0;
}

#endif
