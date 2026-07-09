#pragma once

// Резолв доменного имени -> первый A-адрес (общий случай поверх udp.h;
// dnstest.c раньше делал похожее, но с захардкоженным одноразовым
// запросом и без разбора ответа - тут разбираем ANSWER-секцию по-настоящему,
// это нужно tcp.h/httpget.c, чтобы подключаться к настоящим хостам по имени).
//
// Кэш ответов (по TTL из самого DNS-ответа) + ретрансмит запроса по
// таймауту (тот же RTO/exponential-backoff паттерн, что и у TCP - см.
// [[project_riscv_tcp_retransmit]]/README) - раньше запрос уходил один
// раз и просто ждал полный timeout_ms без повторной отправки, а любой
// повторный dns_resolve_a() с тем же именем всегда бил по сети заново,
// даже секунду спустя.

#include "udp.h"

#define DNS_PORT 53

#define DNS_RTO_MS       300
#define DNS_RTO_MAX_MS   2000
#define DNS_MAX_RETRIES  5

// Кэш - маленькая фиксированная таблица, хватает с запасом для "одна
// программа резолвит один-два хоста". Вытеснение: сперва свободный слот,
// иначе round-robin по dns_cache_next (не LRU - не нужна точность ради
// такого маленького кэша).
#define DNS_CACHE_SIZE        8
#define DNS_HOSTNAME_MAX      64
#define DNS_CACHE_MAX_TTL_SEC 3600   // потолок TTL - не кэшировать навечно по прихоти чужого сервера
#define DNS_TICKS_PER_SEC     10000000L   // gettime() - 10МГц CLINT, тот же счётчик, что и в tcp.h/sleep_ms

static unsigned char dns_tx[300];
static unsigned char dns_rx[512];

typedef struct {
    char          hostname[DNS_HOSTNAME_MAX];
    unsigned int  ip;
    long          expiry;   // gettime() тик, после которого запись протухает
    int           used;
} dns_cache_entry_t;

static dns_cache_entry_t dns_cache[DNS_CACHE_SIZE];
static unsigned int      dns_cache_next = 0;

static int dns_streq(const char *a, const char *b) {
    unsigned int i = 0;
    while (a[i] && b[i]) {
        if (a[i] != b[i]) return 0;
        i++;
    }
    return a[i] == b[i];
}

static void dns_strcpy(char *dst, const char *src, unsigned int max) {
    unsigned int i = 0;
    while (src[i] && i + 1 < max) { dst[i] = src[i]; i++; }
    dst[i] = 0;
}

// Ищет живую (непротухшую) запись. Возвращает 1 и заполняет *ip_out при
// попадании; протухшую запись при этом сразу освобождает (не ждёт
// вытеснения по кругу).
static int dns_cache_lookup(const char *hostname, unsigned int *ip_out) {
    long now = gettime();
    for (int i = 0; i < DNS_CACHE_SIZE; i++) {
        if (dns_cache[i].used && dns_streq(dns_cache[i].hostname, hostname)) {
            if (now < dns_cache[i].expiry) {
                *ip_out = dns_cache[i].ip;
                return 1;
            }
            dns_cache[i].used = 0;
            return 0;
        }
    }
    return 0;
}

static void dns_cache_store(const char *hostname, unsigned int ip, unsigned int ttl_sec) {
    if (ttl_sec == 0) return;   // TTL=0 по RFC значит "не кэшировать"
    if (ttl_sec > DNS_CACHE_MAX_TTL_SEC) ttl_sec = DNS_CACHE_MAX_TTL_SEC;

    int slot = -1;
    for (int i = 0; i < DNS_CACHE_SIZE; i++) {
        if (dns_cache[i].used && dns_streq(dns_cache[i].hostname, hostname)) { slot = i; break; }
    }
    if (slot < 0) {
        for (int i = 0; i < DNS_CACHE_SIZE; i++) {
            if (!dns_cache[i].used) { slot = i; break; }
        }
    }
    if (slot < 0) {
        slot = (int)dns_cache_next;
        dns_cache_next = (dns_cache_next + 1) % DNS_CACHE_SIZE;
    }

    dns_strcpy(dns_cache[slot].hostname, hostname, DNS_HOSTNAME_MAX);
    dns_cache[slot].ip     = ip;
    dns_cache[slot].expiry = gettime() + (long)ttl_sec * DNS_TICKS_PER_SEC;
    dns_cache[slot].used   = 1;
}

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

// Резолвит hostname -> первый A-адрес через dns_server. Сперва смотрит в
// кэш (dns_cache_lookup) - попадание возвращает мгновенно, без единого
// пакета. При промахе шлёт запрос и повторяет его по RTO (exponential
// backoff, тот же паттерн что и у TCP) в пределах общего timeout_ms -
// UDP-запрос или ответ могли потеряться в любую сторону. Понимает сжатие
// имён (указатели 0xC0xx) в ANSWER-секции - реальные серверы почти всегда
// им пользуются вместо повторения полного имени. При успехе кэширует
// результат на TTL из самого ответа. Возвращает 1/0.
static int dns_resolve_a(const char *hostname, unsigned int dns_server,
                          unsigned int timeout_ms, unsigned int *ip_out) {
    if (dns_cache_lookup(hostname, ip_out)) return 1;

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

    unsigned int rto = DNS_RTO_MS;
    unsigned int elapsed = 0;

    for (int attempt = 0; attempt <= DNS_MAX_RETRIES; attempt++) {
        unsigned int waited = 0;
        while (waited < rto && elapsed < timeout_ms) {
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
                        unsigned int ttl = ((unsigned int)dns_rx[p] << 24) | ((unsigned int)dns_rx[p+1] << 16) |
                                           ((unsigned int)dns_rx[p+2] << 8)  |  (unsigned int)dns_rx[p+3];
                        p += 4;
                        unsigned int rdlen = ((unsigned int)dns_rx[p] << 8) | dns_rx[p+1]; p += 2;
                        if (rtype == 1 && rdlen == 4 && p + 4 <= n) {
                            *ip_out = ((unsigned int)dns_rx[p] << 24) | ((unsigned int)dns_rx[p+1] << 16) |
                                     ((unsigned int)dns_rx[p+2] << 8)  |  (unsigned int)dns_rx[p+3];
                            dns_cache_store(hostname, *ip_out, ttl);
                            return 1;
                        }
                        p += rdlen;
                    }
                }
            }
            sleep_ms(10);
            waited += 10;
            elapsed += 10;
        }
        if (elapsed >= timeout_ms) break;
        // RTO истёк без ответа - возможно, запрос или ответ потерялся:
        // повторяем тот же уже собранный запрос (тот же qid).
        udp_send(dns_server, DNS_PORT, 5354, dns_tx, off);
        rto *= 2;
        if (rto > DNS_RTO_MAX_MS) rto = DNS_RTO_MAX_MS;
    }
    return 0;
}
