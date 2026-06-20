#include "axiom.h"

// Частоты нот (Гц), 4-я октава.
#define NOTE_C4 262
#define NOTE_D4 294
#define NOTE_E4 330
#define NOTE_F4 349
#define NOTE_G4 392
#define NOTE_A4 440
#define NOTE_B4 494
#define NOTE_C5 523

int main(int argc, char** argv) {
    (void)argc; (void)argv;

    ax_print("Beep!\n");

    // Простая мелодия ("В лесу родилась ёлочка", первые 8 нот).
    unsigned int notes[] = {
        NOTE_E4, NOTE_D4, NOTE_C4, NOTE_D4,
        NOTE_E4, NOTE_E4, NOTE_E4, 0,
    };
    unsigned int count = sizeof(notes) / sizeof(notes[0]);

    for (unsigned int i = 0; i < count; i++) {
        ax_beep(notes[i], 250);
        ax_beep(0, 30); // короткая пауза между нотами
    }

    ax_print("Done.\n");
    return 0;
}
