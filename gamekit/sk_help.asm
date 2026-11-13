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
            LDX  #HELPTXT       ; (the bank page's own, there)
            LDA  PAGE
            CMPA #2
            BNE  KH1
            LDX  #HELPBK
KH1         JMP  DRAWLAB
; HELPTXT: the help screen (F1): its labels, as DRAWLAB draws them.
HELPTXT
            FCB  2,2,C_LABEL
            FCC  "A song plays its orders in turn, each a pattern of up to 128 rows; a row has"
            FCB  0
            FCB  2,3,C_LABEL
            FCC  "a cell for each track: note, instrument, volume, effect. With Record on, a"
            FCB  0
            FCB  2,4,C_LABEL
            FCC  "note goes in at the cursor (which moves down) or, as the song plays, in the"
            FCB  0
            FCB  2,5,C_LABEL
            FCC  "row playing; its key let go puts in its end. Record off, the keys just play."
            FCB  0
            FCB  2,7,C_HEAD
            FCC  "Both pages"
            FCB  0
            FCB  2,8,C_VALUE
            FCC  "Z-M Q-P"
            FCB  0
            FCB  14,8,C_LABEL
            FCC  "the piano's keys"
            FCB  0
            FCB  2,9,C_VALUE
            FCC  "[ ]"
            FCB  0
            FCB  14,9,C_LABEL
            FCC  "octave down, up"
            FCB  0
            FCB  2,10,C_VALUE
            FCC  "Space"
            FCB  0
            FCB  14,10,C_LABEL
            FCC  "play from the order; stop"
            FCB  0
            FCB  2,11,C_VALUE
            FCC  "Bksp"
            FCB  0
            FCB  14,11,C_LABEL
            FCC  "all notes off"
            FCB  0
            FCB  2,12,C_VALUE
            FCC  "Tab"
            FCB  0
            FCB  14,12,C_LABEL
            FCC  "the other page"
            FCB  0
            FCB  2,13,C_VALUE
            FCC  "^O"
            FCB  0
            FCB  14,13,C_LABEL
            FCC  "open a song or instrument"
            FCB  0
            FCB  2,14,C_VALUE
            FCC  "^S ^A ^W"
            FCB  0
            FCB  14,14,C_LABEL
            FCC  "save song; as; instrument"
            FCB  0
            FCB  2,15,C_VALUE
            FCC  "^B"
            FCB  0
            FCB  14,15,C_LABEL
            FCC  "instrument banks"
            FCB  0
            FCB  2,16,C_VALUE
            FCC  "F1"
            FCB  0
            FCB  14,16,C_LABEL
            FCC  "this help"
            FCB  0
            FCB  2,17,C_VALUE
            FCC  "Esc"
            FCB  0
            FCB  14,17,C_LABEL
            FCC  "back to the shell"
            FCB  0
            FCB  2,19,C_HEAD
            FCC  "The instrument page"
            FCB  0
            FCB  2,20,C_VALUE
            FCC  "arrows"
            FCB  0
            FCB  14,20,C_LABEL
            FCC  "the setting to change"
            FCB  0
            FCB  2,21,C_VALUE
            FCC  "+ -"
            FCB  0
            FCB  14,21,C_LABEL
            FCC  "change it"
            FCB  0
            FCB  2,22,C_VALUE
            FCC  "Enter"
            FCB  0
            FCB  14,22,C_LABEL
            FCC  "on the name: rename it"
            FCB  0
            FCB  2,23,C_VALUE
            FCC  "PgUp PgDn"
            FCB  0
            FCB  14,23,C_LABEL
            FCC  "instrument before, after"
            FCB  0
            FCB  2,24,C_VALUE
            FCC  "^N ^D"
            FCB  0
            FCB  14,24,C_LABEL
            FCC  "new instrument; a copy"
            FCB  0
            FCB  42,7,C_HEAD
            FCC  "The pattern page"
            FCB  0
            FCB  42,8,C_VALUE
            FCC  "arrows"
            FCB  0
            FCB  54,8,C_LABEL
            FCC  "move; row 0 up: settings"
            FCB  0
            FCB  42,9,C_VALUE
            FCC  "PgUp PgDn"
            FCB  0
            FCB  54,9,C_LABEL
            FCC  "16 rows up, down"
            FCB  0
            FCB  42,10,C_VALUE
            FCC  "Home End"
            FCB  0
            FCB  54,10,C_LABEL
            FCC  "the first row, the last"
            FCB  0
            FCB  42,11,C_VALUE
            FCC  "1"
            FCB  0
            FCB  54,11,C_LABEL
            FCC  "the key let go (note off)"
            FCB  0
            FCB  42,12,C_VALUE
            FCC  "0-9 A-F"
            FCB  0
            FCB  54,12,C_LABEL
            FCC  "a digit (effects: 0-9 A-Z)"
            FCB  0
            FCB  42,13,C_VALUE
            FCC  "Del"
            FCB  0
            FCB  54,13,C_LABEL
            FCC  "field (or block) cleared"
            FCB  0
            FCB  42,14,C_VALUE
            FCC  "Ins ^Ins"
            FCB  0
            FCB  54,14,C_LABEL
            FCC  "a row in: this track, all"
            FCB  0
            FCB  42,15,C_VALUE
            FCC  "Sh+Del ^Del"
            FCB  0
            FCB  54,15,C_LABEL
            FCC  "a row out: this track, all"
            FCB  0
            FCB  42,16,C_VALUE
            FCC  "+ -"
            FCB  0
            FCB  54,16,C_LABEL
            FCC  "pattern played; a setting"
            FCB  0
            FCB  42,17,C_VALUE
            FCC  "^Up ^Dn"
            FCB  0
            FCB  54,17,C_LABEL
            FCC  "the order before, after"
            FCB  0
            FCB  42,18,C_VALUE
            FCC  "^N ^D"
            FCB  0
            FCB  54,18,C_LABEL
            FCC  "new pattern; a copy of it"
            FCB  0
            FCB  42,19,C_VALUE
            FCC  "Alt+Ins Del"
            FCB  0
            FCB  54,19,C_LABEL
            FCC  "order again; order out"
            FCB  0
            FCB  42,20,C_VALUE
            FCC  "^Lt ^Rt"
            FCB  0
            FCB  54,20,C_LABEL
            FCC  "the instrument put in"
            FCB  0
            FCB  42,21,C_VALUE
            FCC  "Enter"
            FCB  0
            FCB  54,21,C_LABEL
            FCC  "on title, author: retype"
            FCB  0
            FCB  42,22,C_VALUE
            FCC  "^E ^P ^M"
            FCB  0
            FCB  54,22,C_LABEL
            FCC  "Record; Loop pattern; mute"
            FCB  0
            FCB  42,23,C_VALUE
            FCC  "Sh+arrows"
            FCB  0
            FCB  54,23,C_LABEL
            FCC  "a block (Esc: let go)"
            FCB  0
            FCB  42,24,C_VALUE
            FCC  "^C ^X ^V"
            FCB  0
            FCB  54,24,C_LABEL
            FCC  "copy, cut, paste a block"
            FCB  0
            FCB  42,25,C_VALUE
            FCC  "^Sh+C X V"
            FCB  0
            FCB  54,25,C_LABEL
            FCC  "the same: whole pattern"
            FCB  0
            FCB  42,26,C_VALUE
            FCC  "^(Sh+)Bksp"
            FCB  0
            FCB  54,26,C_LABEL
            FCC  "cut the track (pattern)"
            FCB  0
            FCB  2,28,C_LABEL
            FCC  "Mouse: a click picks a field or ticks a box (a head: mute); a drag, a block."
            FCB  0
            FCB  2,29,C_MSG
            FCC  "Any key: back to the page"
            FCB  0
            FCB  $FF,$FF
; HELPBK: the bank page's help.
HELPBK
            FCB  2,2,C_LABEL
            FCC  "The bank page lists a folder's instrument banks (WOPL files, .WOP) and the"
            FCB  0
            FCB  2,3,C_LABEL
            FCC  "instruments of the bank shown. The piano's keys play the one at the cursor."
            FCB  0
            FCB  2,4,C_LABEL
            FCC  "Enter adds it to the song; ^R puts it over the song's instrument being"
            FCB  0
            FCB  2,5,C_LABEL
            FCC  "edited (on the right). ^P puts that one into the bank, at the cursor: a bank"
            FCB  0
            FCB  2,6,C_LABEL
            FCC  "of your own, made with ^N. An instrument taken keeps where it came from (the"
            FCB  0
            FCB  2,7,C_LABEL
            FCC  "instrument page shows it)."
            FCB  0
            FCB  2,9,C_HEAD
            FCC  "The bank page"
            FCB  0
            FCB  2,10,C_VALUE
            FCC  "Up Down"
            FCB  0
            FCB  14,10,C_LABEL
            FCC  "the cursor"
            FCB  0
            FCB  2,11,C_VALUE
            FCC  "Left Right"
            FCB  0
            FCB  14,11,C_LABEL
            FCC  "the files; the instruments"
            FCB  0
            FCB  2,12,C_VALUE
            FCC  "PgUp PgDn"
            FCB  0
            FCB  14,12,C_LABEL
            FCC  "a page up, down"
            FCB  0
            FCB  2,13,C_VALUE
            FCC  "Home End"
            FCB  0
            FCB  14,13,C_LABEL
            FCC  "the first, the last"
            FCB  0
            FCB  2,14,C_VALUE
            FCC  "Enter"
            FCB  0
            FCB  14,14,C_LABEL
            FCC  "open it; add to the song"
            FCB  0
            FCB  2,15,C_VALUE
            FCC  "^R"
            FCB  0
            FCB  14,15,C_LABEL
            FCC  "over the song's instrument"
            FCB  0
            FCB  2,16,C_VALUE
            FCC  "^P"
            FCB  0
            FCB  14,16,C_LABEL
            FCC  "the song's into the bank"
            FCB  0
            FCB  2,17,C_VALUE
            FCC  "^N"
            FCB  0
            FCB  14,17,C_LABEL
            FCC  "a new bank file"
            FCB  0
            FCB  2,18,C_VALUE
            FCC  "^Lt ^Rt"
            FCB  0
            FCB  14,18,C_LABEL
            FCC  "the bank before, after"
            FCB  0
            FCB  2,19,C_VALUE
            FCC  "^Up ^Dn"
            FCB  0
            FCB  14,19,C_LABEL
            FCC  "song's instrument up, down"
            FCB  0
            FCB  42,9,C_HEAD
            FCC  "And"
            FCB  0
            FCB  42,10,C_VALUE
            FCC  "Z-M Q-P"
            FCB  0
            FCB  54,10,C_LABEL
            FCC  "the piano's keys"
            FCB  0
            FCB  42,11,C_VALUE
            FCC  "[ ]"
            FCB  0
            FCB  54,11,C_LABEL
            FCC  "octave down, up"
            FCB  0
            FCB  42,12,C_VALUE
            FCC  "Space"
            FCB  0
            FCB  54,12,C_LABEL
            FCC  "play the song; stop"
            FCB  0
            FCB  42,13,C_VALUE
            FCC  "Bksp"
            FCB  0
            FCB  54,13,C_LABEL
            FCC  "all notes off"
            FCB  0
            FCB  42,14,C_VALUE
            FCC  "^S ^A"
            FCB  0
            FCB  54,14,C_LABEL
            FCC  "save the song; save as"
            FCB  0
            FCB  42,15,C_VALUE
            FCC  "Tab Esc ^B"
            FCB  0
            FCB  54,15,C_LABEL
            FCC  "back to the page before"
            FCB  0
            FCB  42,16,C_VALUE
            FCC  "F1"
            FCB  0
            FCB  54,16,C_LABEL
            FCC  "this help"
            FCB  0
            FCB  2,21,C_LABEL
            FCC  "Mouse: a click picks a file or an instrument (a file clicked again opens it;"
            FCB  0
            FCB  2,22,C_LABEL
            FCC  "an instrument double-clicked goes over the song's, as ^R); the wheel moves"
            FCB  0
            FCB  2,23,C_LABEL
            FCC  "the cursor."
            FCB  0
            FCB  2,29,C_MSG
            FCC  "Any key: back to the page"
            FCB  0
            FCB  $FF,$FF
