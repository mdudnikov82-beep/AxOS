static int cursor_x = 0;
static int cursor_y = 0;

void clear_screen() {
    char* vidmem = (char*) 0xB8000;
    for (int i = 0; i < 80 * 25 * 2; i += 2) {
        vidmem[i] = ' ';
        vidmem[i+1] = 0x0F; // Чёрный фон, белый текст
    }
    cursor_x = 0;
    cursor_y = 0;
}

void print_string(char* str) {
    unsigned char* vidmem = (unsigned char*) 0xB8000;
    int i = 0;
    while (str[i] != '\0') {
        int offset = (cursor_y * 80 + cursor_x) * 2;

        // Защита от выхода за пределы экрана
        if (offset < 80 * 25 * 2) {
            vidmem[offset] = str[i];
            vidmem[offset + 1] = 0x0F;
        }

        cursor_x++;
        if (cursor_x >= 80) { cursor_x = 0; cursor_y++; }
        i++;
    }
}