#ifndef SCREEN_H
#define SCREEN_H

#define VIDEO_MEMORY 0xB8000
#define MAX_ROWS 25
#define MAX_COLS 80

#define COLOR_BLACK 0x00
#define COLOR_LIGHT_GRAY 0x07
#define COLOR_LIGHT_GREEN 0x0A
#define COLOR_LIGHT_CYAN 0x0B
#define COLOR_WHITE 0x0F

int cursor_offset = 0;

void clear_screen()
{
    char *vidptr = (char *)VIDEO_MEMORY;
    for (int i = 0; i < MAX_COLS * MAX_ROWS * 2; i += 2)
    {
        vidptr[i] = ' ';
        vidptr[i + 1] = COLOR_LIGHT_GRAY;
    }
    cursor_offset = 0;
}

void scroll_screen()
{
    char *vidptr = (char *)VIDEO_MEMORY;
    for (int i = 0; i < (MAX_ROWS - 1) * MAX_COLS * 2; i++)
    {
        vidptr[i] = vidptr[i + MAX_COLS * 2];
    }
    for (int i = (MAX_ROWS - 1) * MAX_COLS * 2; i < MAX_ROWS * MAX_COLS * 2; i += 2)
    {
        vidptr[i] = ' ';
        vidptr[i + 1] = COLOR_LIGHT_GRAY;
    }
    cursor_offset = (MAX_ROWS - 1) * MAX_COLS * 2;
}

void print_string_color(char *str, char color)
{
    char *vidptr = (char *)VIDEO_MEMORY;
    int i = 0;
    while (str[i] != '\0')
    {
        if (cursor_offset >= MAX_ROWS * MAX_COLS * 2)
            scroll_screen();
        if (str[i] == '\n')
        {
            int current_row = (cursor_offset / 2) / MAX_COLS;
            cursor_offset = (current_row + 1) * MAX_COLS * 2;
        }
        else
        {
            vidptr[cursor_offset] = str[i];
            vidptr[cursor_offset + 1] = color;
            cursor_offset += 2;
        }
        i++;
    }
}

void print_string(char *str)
{
    print_string_color(str, COLOR_WHITE);
}

void print_char(char c, char color)
{
    char *vidptr = (char *)VIDEO_MEMORY;
    if (cursor_offset >= MAX_ROWS * MAX_COLS * 2)
        scroll_screen();

    if (c == '\n')
    {
        int current_row = (cursor_offset / 2) / MAX_COLS;
        cursor_offset = (current_row + 1) * MAX_COLS * 2;
    }
    else
    {
        vidptr[cursor_offset] = c;
        vidptr[cursor_offset + 1] = color;
        cursor_offset += 2;
    }
}

// НОВАЯ ФУНКЦИЯ: Стирает последний символ!
void handle_backspace()
{
    char *vidptr = (char *)VIDEO_MEMORY;

    // Проверяем, чтобы мы не стерли то, чего нет (не ушли выше начала экрана)
    if (cursor_offset > 0)
    {
        cursor_offset -= 2;          // Сдвигаем курсор назад
        vidptr[cursor_offset] = ' '; // Заменяем букву на пробел
    }
}

#endif