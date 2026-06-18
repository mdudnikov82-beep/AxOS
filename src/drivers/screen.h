#ifndef SCREEN_H
#define SCREEN_H

#define VIDEO_MEMORY 0xB8000
#define MAX_ROWS 25
#define MAX_COLS 80

#define COLOR_WHITE 0x0F

void clear_screen();
void print_string(char* str);
void backspace();

#endif
