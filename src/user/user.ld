OUTPUT_FORMAT("pe-i386")
OUTPUT_ARCH(i386)
ENTRY(_start)

SECTIONS
{
    /* Адрес загрузки пользовательских программ - см. USER_PROGRAM_ADDR
       в kernel.c. Эта область уже identity-mapped и помечена PRESENT|
       USER|RW в paging.c (init_paging покрывает первые 4 МБ), так что
       никаких изменений в paging для запуска ring3-кода здесь не нужно. */
    . = 0x100000;
    .text : { *(.text) }
    .data : { *(.data) }
    .bss : { *(.bss) }
}
