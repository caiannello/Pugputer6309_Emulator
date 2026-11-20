/* pug/input.h -- CC (the Pugputer's C compiler): the keyboard, the mouse and
   the gamepads, on the video card's USB port (LIBPUG.A). */
#ifndef _PUG_INPUT_H
#define _PUG_INPUT_H

/* The keyboard. key_grab(1) takes the keys from the console (give them back,
   key_grab(0), before the program ends). key_get gives each key pressed and
   released: its USB usage code (where it is on the keyboard), and the
   character it types (0x80 added: a release). */
void key_grab(int on);
int key_get(int *ch);           /* -> the code, 0: none waiting */
int key_waiting(void);
int key_mods(void);             /* KM_... held now */
#define KEY_A       0x04        /* ... KEY_A + 25: Z */
#define KEY_1       0x1E        /* ... 0x27: 0 */
#define KEY_ENTER   0x28
#define KEY_ESC     0x29
#define KEY_BKSP    0x2A
#define KEY_TAB     0x2B
#define KEY_SPACE   0x2C
#define KEY_F1      0x3A        /* ... 0x45: F12 */
#define KEY_INSERT  0x49
#define KEY_HOME    0x4A
#define KEY_PGUP    0x4B
#define KEY_DELETE  0x4C
#define KEY_END     0x4D
#define KEY_PGDN    0x4E
#define KEY_RIGHT   0x4F
#define KEY_LEFT    0x50
#define KEY_DOWN    0x51
#define KEY_UP      0x52
#define KEY_RELEASE 0x80        /* in key_get's character */
#define KM_CTRL     0x11
#define KM_SHIFT    0x22
#define KM_ALT      0x44

/* The mouse: where it is in 640x480 (halve it for 320x240), its buttons. */
int mouse_get(int *x, int *y);  /* -> MB_... */
int mouse_wheel(void);          /* clicks since the last call, + away */
void mouse_pointer(int on);     /* sprite 0 follows it (the program draws it) */
#define MB_LEFT     0x01
#define MB_RIGHT    0x02
#define MB_MID      0x04
#define MB_SEEN     0x80        /* there is a mouse */

/* The gamepads, 0-3. */
struct pad {
    unsigned char flags;        /* PAD_CONN, PAD_MAPPED */
    unsigned char dpad;         /* PAD_UP ... */
    unsigned char btn1;         /* BT_SOUTH ... BT_R2 */
    unsigned char btn2;         /* BT_SELECT ... BT_R3 */
    signed char lx, ly;         /* the sticks: -127 to 127; + right, down */
    signed char rx, ry;
};
int pad_get(int n, struct pad *p);      /* -> 1 if it's plugged in */
#define PAD_CONN    0x80
#define PAD_MAPPED  0x40        /* the buttons are as below */
#define PAD_UP      0x01
#define PAD_DOWN    0x02
#define PAD_LEFT    0x04
#define PAD_RIGHT   0x08
#define BT_SOUTH    0x01        /* by where they are, not what's on them */
#define BT_EAST     0x02
#define BT_WEST     0x04
#define BT_NORTH    0x08
#define BT_L        0x10
#define BT_R        0x20
#define BT_L2       0x40
#define BT_R2       0x80
#define BT_SELECT   0x01        /* (btn2) */
#define BT_START    0x02
#define BT_HOME     0x04
#define BT_L3       0x08
#define BT_R3       0x10

#endif
