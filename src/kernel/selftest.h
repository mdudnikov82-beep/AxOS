#ifndef SELFTEST_H
#define SELFTEST_H

// Прогоняет регрессионные тесты heap/paging/FAT12 (команда shell
// "selftest"). Печатает подробный вывод каждого теста и итоговую строку
// "SELFTEST: ALL PASS" или "SELFTEST: FAILED".
void run_self_tests();

#endif
