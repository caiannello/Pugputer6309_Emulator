;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 game kit
;    FILE: sk_help.asm
;
; SONGKIT's help screen (F1), an overlay of its own (OV_HELP): its text, and
; the code that draws it, in a page with room to grow.
;------------------------------------------------------------------------------
; KHELP (F1): the help, over the page, until a key.
KHELP       LDA  #3
            STA  MODE
            JSR  TXCLR
            JSR  O_DRAWTITLE
            LDX  #HELPTXT
            JMP  DRAWLAB
; HELPTXT: the help screen (F1): its labels, as DRAWLAB draws them.
HELPTXT
            FCB  2,2,C_LABEL
            FCC  "A song plays its orders in turn, each one a pattern of up to 128 rows; a row"
            FCB  0
            FCB  2,3,C_LABEL
            FCC  "has a cell for each track: note, instrument, volume, effect. The keyboard's"
            FCB  0
            FCB  2,4,C_LABEL
            FCC  "letters are a piano. With Record on, a note goes in at the cursor, which"
            FCB  0
            FCB  2,5,C_LABEL
            FCC  "moves down; as the song plays, the cursor follows it, a note goes in the row"
            FCB  0
            FCB  2,6,C_LABEL
            FCC  "playing, and letting its key go puts in its end. With Record off, the keys"
            FCB  0
            FCB  2,7,C_LABEL
            FCC  "just play."
            FCB  0
            FCB  2,9,C_HEAD
            FCC  "Both pages"
            FCB  0
            FCB  2,10,C_VALUE
            FCC  "Z-M Q-P"
            FCB  0
            FCB  14,10,C_LABEL
            FCC  "the piano's keys"
            FCB  0
            FCB  2,11,C_VALUE
            FCC  "[ ]"
            FCB  0
            FCB  14,11,C_LABEL
            FCC  "octave down, up"
            FCB  0
            FCB  2,12,C_VALUE
            FCC  "Space"
            FCB  0
            FCB  14,12,C_LABEL
            FCC  "play from the order; stop"
            FCB  0
            FCB  2,13,C_VALUE
            FCC  "Bksp"
            FCB  0
            FCB  14,13,C_LABEL
            FCC  "all notes off"
            FCB  0
            FCB  2,14,C_VALUE
            FCC  "Tab"
            FCB  0
            FCB  14,14,C_LABEL
            FCC  "the other page"
            FCB  0
            FCB  2,15,C_VALUE
            FCC  "^O"
            FCB  0
            FCB  14,15,C_LABEL
            FCC  "open a song or instrument"
            FCB  0
            FCB  2,16,C_VALUE
            FCC  "^S ^A"
            FCB  0
            FCB  14,16,C_LABEL
            FCC  "save the song; save as"
            FCB  0
            FCB  2,17,C_VALUE
            FCC  "^W"
            FCB  0
            FCB  14,17,C_LABEL
            FCC  "save the instrument"
            FCB  0
            FCB  2,18,C_VALUE
            FCC  "F1"
            FCB  0
            FCB  14,18,C_LABEL
            FCC  "this help"
            FCB  0
            FCB  2,19,C_VALUE
            FCC  "Esc"
            FCB  0
            FCB  14,19,C_LABEL
            FCC  "back to the shell"
            FCB  0
            FCB  2,21,C_HEAD
            FCC  "The instrument page"
            FCB  0
            FCB  2,22,C_VALUE
            FCC  "arrows"
            FCB  0
            FCB  14,22,C_LABEL
            FCC  "the setting to change"
            FCB  0
            FCB  2,23,C_VALUE
            FCC  "+ -"
            FCB  0
            FCB  14,23,C_LABEL
            FCC  "change it"
            FCB  0
            FCB  2,24,C_VALUE
            FCC  "Enter"
            FCB  0
            FCB  14,24,C_LABEL
            FCC  "on the name: rename it"
            FCB  0
            FCB  2,25,C_VALUE
            FCC  "PgUp PgDn"
            FCB  0
            FCB  14,25,C_LABEL
            FCC  "instrument before, after"
            FCB  0
            FCB  2,26,C_VALUE
            FCC  "^N ^D"
            FCB  0
            FCB  14,26,C_LABEL
            FCC  "new instrument; a copy"
            FCB  0
            FCB  42,9,C_HEAD
            FCC  "The pattern page"
            FCB  0
            FCB  42,10,C_VALUE
            FCC  "arrows"
            FCB  0
            FCB  54,10,C_LABEL
            FCC  "move; row 0 up: settings"
            FCB  0
            FCB  42,11,C_VALUE
            FCC  "PgUp PgDn"
            FCB  0
            FCB  54,11,C_LABEL
            FCC  "16 rows up, down"
            FCB  0
            FCB  42,12,C_VALUE
            FCC  "Home End"
            FCB  0
            FCB  54,12,C_LABEL
            FCC  "the first row, the last"
            FCB  0
            FCB  42,13,C_VALUE
            FCC  "1"
            FCB  0
            FCB  54,13,C_LABEL
            FCC  "the key let go (note off)"
            FCB  0
            FCB  42,14,C_VALUE
            FCC  "0-9 A-F"
            FCB  0
            FCB  54,14,C_LABEL
            FCC  "a digit (effects: 0-9 A-Z)"
            FCB  0
            FCB  42,15,C_VALUE
            FCC  "Del"
            FCB  0
            FCB  54,15,C_LABEL
            FCC  "field (or block) cleared"
            FCB  0
            FCB  42,16,C_VALUE
            FCC  "Ins ^Ins"
            FCB  0
            FCB  54,16,C_LABEL
            FCC  "a row in: this track, all"
            FCB  0
            FCB  42,17,C_VALUE
            FCC  "Sh+Del ^Del"
            FCB  0
            FCB  54,17,C_LABEL
            FCC  "a row out: this track, all"
            FCB  0
            FCB  42,18,C_VALUE
            FCC  "+ -"
            FCB  0
            FCB  54,18,C_LABEL
            FCC  "pattern played; a setting"
            FCB  0
            FCB  42,19,C_VALUE
            FCC  "^Up ^Dn"
            FCB  0
            FCB  54,19,C_LABEL
            FCC  "the order before, after"
            FCB  0
            FCB  42,20,C_VALUE
            FCC  "^N ^D"
            FCB  0
            FCB  54,20,C_LABEL
            FCC  "new pattern; a copy of it"
            FCB  0
            FCB  42,21,C_VALUE
            FCC  "Alt+Ins Del"
            FCB  0
            FCB  54,21,C_LABEL
            FCC  "order again; order out"
            FCB  0
            FCB  42,22,C_VALUE
            FCC  "^Lt ^Rt"
            FCB  0
            FCB  54,22,C_LABEL
            FCC  "the instrument put in"
            FCB  0
            FCB  42,23,C_VALUE
            FCC  "Enter"
            FCB  0
            FCB  54,23,C_LABEL
            FCC  "on title, author: retype"
            FCB  0
            FCB  42,24,C_VALUE
            FCC  "^E ^P ^M"
            FCB  0
            FCB  54,24,C_LABEL
            FCC  "Record; Loop pattern; mute"
            FCB  0
            FCB  42,25,C_VALUE
            FCC  "Sh+arrows"
            FCB  0
            FCB  54,25,C_LABEL
            FCC  "a block (Esc: let go)"
            FCB  0
            FCB  42,26,C_VALUE
            FCC  "^C ^X ^V"
            FCB  0
            FCB  54,26,C_LABEL
            FCC  "copy, cut, paste a block"
            FCB  0
            FCB  2,28,C_LABEL
            FCC  "Mouse: a click picks a field or ticks a box (a head: mute); a drag, a block."
            FCB  0
            FCB  2,29,C_MSG
            FCC  "Any key: back to the page"
            FCB  0
            FCB  $FF,$FF
