#ifndef SPEAKER_H
#define SPEAKER_H

// Включает системный динамик на частоте freq Гц - канал 2 PIT (Programmable
// Interval Timer), отдельный от канала 0 (системный таймер, IRQ0). Звук
// длится, пока не вызван speaker_off() - вызывающий сам решает, сколько
// ждать между ними (см. sys_beep() в kernel.c, использующий sleep_ms()).
void speaker_on(unsigned int freq);

// Выключает динамик (гасит и таймер-гейт, и сам сигнал на порту 0x61).
void speaker_off();

#endif
