// The video card as the machine's console: its ANSI terminal (vidcard/core/vc_term.c), and
// the BIOS using it for stdin, stdout and stderr when the card says it's to be the console.
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

#include "basic309_session.hpp"
#include "pugputer/video_device.hpp"
#include "test_framework.hpp"
#include "vc.h"

using pugputer::VideoDevice;

namespace {

// ---- the terminal alone ----

struct Term {
    vc_card* c;
    Term() : c(static_cast<vc_card*>(std::calloc(1, sizeof(vc_card)))) {
        c->console = 1;
        vc_reset(c);
    }
    ~Term() { std::free(c); }
    void out(const std::string& s) {
        for (char ch : s) {
            vc_write(c, VC_CMD, VC_C_TERM);
            vc_write(c, VC_CMD, static_cast<uint8_t>(ch));
        }
    }
    const uint8_t* cell(int x, int y) const { return c->vram + VC_RESET_TEXT_MAP + y * 512 + x * 4; }
    std::string row(int y) const {
        std::string s;
        for (int x = 0; x < VC_TERM_COLS; ++x) s += static_cast<char>(cell(x, y)[0]);
        s.erase(s.find_last_not_of(' ') + 1);
        return s;
    }
    std::string in() {
        std::string s;
        while (vc_read(c, VC_STATUS) & VC_STATUS_KEY) s += static_cast<char>(vc_read(c, VC_KEY_CHAR));
        return s;
    }
    void key(uint8_t usage) {
        vc_key(c, usage, 1);
        vc_key(c, usage, 0);
    }
    void with(uint8_t mod, uint8_t usage) {
        vc_key(c, mod, 1);
        key(usage);
        vc_key(c, mod, 0);
    }
    std::vector<uint16_t> line(int y) const {
        std::vector<uint16_t> v(VC_WIDTH);
        vc_render_line(c, y, v.data());
        return v;
    }
};

} // namespace

TEST(term_prints_wraps_and_scrolls) {
    Term t;
    t.out("hello\r\nworld");
    CHECK(t.row(0) == "hello" && t.row(1) == "world");
    CHECK(t.c->term.x == 5 && t.c->term.y == 1);
    CHECK(t.cell(0, 0)[1] == 7 && t.cell(0, 0)[2] == 0);

    // The 80th column doesn't wrap until the next character does.
    Term w;
    w.out(std::string(80, 'x'));
    CHECK(w.c->term.y == 0 && w.c->term.x == 79 && w.c->term.pending);
    w.out("\r");
    CHECK(w.c->term.x == 0 && w.c->term.y == 0); // (CR cancels it: no blank line)
    w.out(std::string(80, 'y') + "z");
    CHECK(w.row(0) == std::string(80, 'y') && w.row(1) == "z");

    // A line feed on the last row scrolls.
    Term s;
    for (int i = 0; i < 30; ++i) s.out(std::string(1, static_cast<char>('A' + i)) + "\r\n");
    CHECK(s.row(0) == "B" && s.row(28) == "^" && s.row(29) == "" && s.c->term.y == 29);
}

TEST(term_moves_and_erases) {
    Term t;
    t.out("\x1b[5;10Hx");
    CHECK(t.cell(9, 4)[0] == 'x' && t.c->term.x == 10 && t.c->term.y == 4);
    t.out("\x1b[H");
    CHECK(t.c->term.x == 0 && t.c->term.y == 0);
    t.out("\x1b[2B\x1b[3C\x1b[1A\x1b[1D");
    CHECK(t.c->term.x == 2 && t.c->term.y == 1);
    t.out("\x1b[999;999H");
    CHECK(t.c->term.x == 79 && t.c->term.y == 29);

    Term e;
    e.out("abcdef\x1b[1;4H\x1b[K");
    CHECK(e.row(0) == "abc");
    e.out("\r\nzzz\x1b[1;2H\x1b[J");
    CHECK(e.row(0) == "a" && e.row(1) == "");
    e.out("\x1b[1;1Hmn\x1b[2J");
    CHECK(e.row(0) == "" && e.c->term.x == 2); // (2J doesn't move it)

    Term i;
    i.out("abcd\x1b[1;2H\x1b[2@");
    CHECK(i.row(0) == "a  bcd");
    i.out("\x1b[2P");
    CHECK(i.row(0) == "abcd");
    i.out("\x1b[1X");
    CHECK(i.row(0) == "a cd");
}

TEST(term_colors) {
    Term t;
    t.out("\x1b[31;44mA");
    CHECK(t.cell(0, 0)[1] == 1 && t.cell(0, 0)[2] == 4);
    t.out("\x1b[1mB");
    CHECK(t.cell(1, 0)[1] == 9); // bright
    t.out("\x1b[0;7mC");
    CHECK(t.cell(2, 0)[1] == 0 && t.cell(2, 0)[2] == 7);
    t.out("\x1b[0;38;5;208;48;5;17mD");
    CHECK(t.cell(3, 0)[1] == 208 && t.cell(3, 0)[2] == 17);
    t.out("\x1b[0;38;2;255;0;0;48;2;128;128;128mE"); // BASIC's HCOLOR
    CHECK(t.cell(4, 0)[1] == 196 && t.cell(4, 0)[2] == 244);
    t.out("\x1b[m\x1b[92mF\x1b[39;41mG");
    CHECK(t.cell(5, 0)[1] == 10 && t.cell(6, 0)[1] == 7 && t.cell(6, 0)[2] == 1);
    // Erasing fills with the background color.
    t.out("\x1b[K");
    CHECK(t.cell(7, 0)[2] == 1 && t.cell(79, 0)[2] == 1);
}

TEST(term_answers_where_the_cursor_is) {
    // EDIT finds the screen's size this way.
    Term t;
    t.out("\x1b[999;999H\x1b[6n");
    CHECK(t.in() == "\x1b[30;80R");
    t.out("\x1b[5n");
    CHECK(t.in() == "\x1b[0n");
    CHECK(t.in() == "");
}

TEST(term_scroll_region_and_lines) {
    Term t;
    for (int i = 0; i < 6; ++i) t.out(std::string(1, static_cast<char>('a' + i)) + "\r\n");
    t.out("\x1b[2;4r"); // rows 2-4 (home afterwards)
    CHECK(t.c->term.top == 1 && t.c->term.bot == 3 && t.c->term.x == 0 && t.c->term.y == 0);
    t.out("\x1b[4;1H\n");
    CHECK(t.row(0) == "a" && t.row(1) == "c" && t.row(2) == "d" && t.row(3) == "" && t.row(4) == "e");
    t.out("\x1b[2;1H\x1b[L"); // insert a line in the region
    CHECK(t.row(1) == "" && t.row(2) == "c" && t.row(3) == "d" && t.row(4) == "e");
    t.out("\x1b[M");
    CHECK(t.row(1) == "c" && t.row(2) == "d" && t.row(3) == "");
    t.out("\x1b[r");
    CHECK(t.c->term.top == 0 && t.c->term.bot == 29);
    t.out("\x1b[1;1H\x1bM"); // reverse index at the top
    CHECK(t.row(0) == "" && t.row(1) == "a");
}

TEST(term_alternate_screen) {
    Term t;
    t.out("keep me\x1b[?1049h");
    CHECK(t.row(0) == "" && t.c->term.alt);
    t.out("\x1b[1;1Hother\x1b[?1049l");
    CHECK(t.row(0) == "keep me" && !t.c->term.alt);
    CHECK(t.c->term.x == 7 && t.c->term.y == 0);

    // The program's own saves don't disturb where the cursor goes back to (EDIT saves and
    // restores it around asking the screen's size, while it has the alternate screen).
    Term k;
    k.out("\x1b[20;9H\x1b[?1049h\x1b[3;3H\x1b" "7\x1b[9;9H\x1b" "8\x1b[s\x1b[?1049l");
    CHECK(k.c->term.x == 8 && k.c->term.y == 19);
    // And the other way: ESC 7 from before it is still there afterwards.
    Term o;
    o.out("\x1b[5;6H\x1b" "7\x1b[20;9H\x1b[?1049h\x1b[?1049l\x1b" "8");
    CHECK(o.c->term.x == 5 && o.c->term.y == 4);
}

TEST(term_ignores_what_it_does_not_know) {
    Term t;
    t.out("a\x1b]0;a title\x07" "b\x1b(Bc\x1b[>5nd\x1b[12;34;56zef");
    CHECK(t.row(0) == "abcdef");
}

TEST(term_keys_arrive_as_a_terminal_sends_them) {
    Term t;
    t.key(0x04);
    CHECK(t.in() == "a");
    t.with(0xE1, 0x04);
    CHECK(t.in() == "A");
    t.with(0xE0, 0x06);
    CHECK(t.in() == "\x03"); // Ctrl+C
    t.with(0xE2, 0x1B);
    CHECK(t.in() == "\x1bx"); // Alt+X
    t.key(0x28);
    CHECK(t.in() == "\r");
    t.key(0x2A);
    CHECK(t.in() == "\b");
    t.key(0x52);
    t.key(0x51);
    t.key(0x4F);
    t.key(0x50);
    CHECK(t.in() == "\x1b[A\x1b[B\x1b[C\x1b[D");
    t.key(0x4A);
    t.key(0x4D);
    t.key(0x4B);
    t.key(0x4C);
    CHECK(t.in() == "\x1b[H\x1b[F\x1b[5~\x1b[3~");
    t.key(0x3A);
    t.key(0x3E);
    CHECK(t.in() == "\x1bOP\x1b[15~");
    t.key(0x2C);
    vc_key(t.c, 0x2C, 1); // (a held key repeats: pressed again)
    CHECK(t.in() == "  ");
}

TEST(term_keys_go_to_the_queue_when_a_program_takes_them) {
    Term t;
    vc_write(t.c, VC_IN_CTRL, VC_IN_KEYS);
    t.key(0x04);
    CHECK(vc_read(t.c, VC_STATUS) & VC_STATUS_KEY);
    CHECK(vc_read(t.c, VC_KEY) == 0x04 && vc_read(t.c, VC_KEY_CHAR) == 'a');
    CHECK(vc_read(t.c, VC_KEY) == 0x04 && vc_read(t.c, VC_KEY_CHAR) == ('a' | 0x80));
    CHECK(!(vc_read(t.c, VC_STATUS) & VC_STATUS_KEY));
    vc_write(t.c, VC_IN_CTRL, 0);
    t.key(0x05);
    CHECK(t.in() == "b");

    // And a card that isn't the console has only the queue, as before.
    Term q;
    q.c->console = 0;
    q.key(0x04);
    CHECK(vc_read(q.c, VC_KEY) == 0x04);
    CHECK(!(vc_read(q.c, VC_STATUS) & VC_STATUS_CONSOLE));
}

TEST(term_is_reset_with_the_card_and_the_console_bit_stays) {
    Term t;
    t.out("\x1b[31mabc\x1b[?1049h");
    t.key(0x04);
    vc_write(t.c, VC_CTRL, 0x80);
    CHECK(t.row(0) == "" && t.c->term.x == 0 && t.c->term.fg == 7 && !t.c->term.alt);
    CHECK(t.in() == "");
    CHECK(vc_read(t.c, VC_STATUS) & VC_STATUS_CONSOLE);
    t.out("ok");
    CHECK(t.cell(1, 0)[0] == 'k');
}

TEST(term_cursor_is_painted_on_the_picture_only) {
    Term t;
    const uint16_t black = t.line(14)[0];
    const uint16_t gray = static_cast<uint16_t>(t.c->cfg[0x200 + 2 * 7] << 8 | t.c->cfg[0x201 + 2 * 7]);
    // Before anything is printed, there's none (a program using the text screen sees none).
    CHECK(t.line(14)[0] == black && t.line(15)[0] == black);
    t.out("\x1b[3;2H");
    auto l = t.line(2 * 16 + 14);
    CHECK(l[8] == gray && l[15] == gray && l[7] == black && l[16] == black);
    CHECK(t.line(2 * 16 + 15)[8] == gray);
    CHECK(t.line(2 * 16 + 13)[8] == black); // (just the bottom two lines)
    CHECK(t.cell(1, 2)[0] == ' ' && t.cell(1, 2)[1] == 7); // video memory is as it was
    t.c->frame = 0x20;                                     // it blinks
    CHECK(t.line(2 * 16 + 14)[8] == black);
    t.c->frame = 0;
    t.out("\x1b[?25l");
    CHECK(t.line(2 * 16 + 14)[8] == black);
    t.out("\x1b[?25h");
    CHECK(t.line(2 * 16 + 14)[8] == gray);
    // A program with its own map: not there.
    t.c->cfg[VC_LAYER0 + VC_L_MAPBASE] = 1;
    CHECK(t.line(2 * 16 + 14)[8] != gray);
}

namespace {

// ---- with the BIOS ----

struct Con {
    Basic309Session s;
    VideoDevice v;
    bool ok = false;
    explicit Con(const char* disk) {
        v.set_console(true);
        s.attach_video(&v);
        ok = s.boot_raw(PUGBIOS_S19_PATH, disk, "6309 BIOS");
    }
    std::string screen() {
        std::string out;
        const vc_card& c = v.card();
        for (int y = 0; y < VC_TERM_ROWS; ++y) {
            std::string r;
            for (int x = 0; x < VC_TERM_COLS; ++x) r += static_cast<char>(c.vram[VC_RESET_TEXT_MAP + y * 512 + x * 4]);
            r.erase(r.find_last_not_of(' ') + 1);
            out += r + "\n";
        }
        return out;
    }
    std::string row(int y) {
        std::string all = screen();
        size_t at = 0;
        for (int i = 0; i < y; ++i) at = all.find('\n', at) + 1;
        return all.substr(at, all.find('\n', at) - at);
    }
    bool wait(const std::string& needle, uint64_t budget = 60000000) {
        uint64_t spent = 0;
        while (spent < budget) {
            if (screen().find(needle) != std::string::npos) return true;
            spent += s.bus.run(200000);
        }
        return screen().find(needle) != std::string::npos;
    }
    bool prompt() { return wait(std::string(1, '>') + std::string(1, char(10))); } // (a row ending in >)
    void hit(uint8_t usage) {
        v.key(usage, true);
        v.key(usage, false);
        s.bus.run(150000);
    }
    void ctrl(uint8_t usage) {
        v.key(0xE0, true);
        hit(usage);
        v.key(0xE0, false);
    }
    void type(const std::string& text) { // letters, digits, and Enter as \r
        for (char ch : text) {
            if (ch >= 'A' && ch <= 'Z') {
                v.key(0xE1, true);
                hit(static_cast<uint8_t>(0x04 + (ch - 'A')));
                v.key(0xE1, false);
            } else if (ch >= '1' && ch <= '9') {
                hit(static_cast<uint8_t>(0x1E + (ch - '1')));
            } else if (ch == '\r') {
                hit(0x28);
            } else {
                hit(static_cast<uint8_t>(0x04 + (ch - 'a')));
            }
        }
    }
};

} // namespace

TEST(console_boots_to_the_shell_on_the_screen) {
    Con m(DISK_IMG_PATH);
    CHECK(m.ok);
    CHECK(m.prompt());
    CHECK(m.screen().find("Pugputer 6309 BIOS") != std::string::npos);
    // The UART has the banner, and not the shell's output.
    CHECK(m.s.received.find("6309 BIOS") != std::string::npos);
    CHECK(m.s.received.find("> ") == std::string::npos);
}

TEST(console_takes_keys_from_the_card_and_the_uart) {
    Con m(DISK_IMG_PATH);
    CHECK(m.ok && m.prompt());
    m.type("HELP\r");
    CHECK(m.wait("EDIT") || m.wait("DIR"));
    const std::string before = m.screen();
    m.s.type("NOSUCHCMD");
    CHECK(m.wait("NOSUCHCMD"));
    CHECK(m.screen() != before);
}

TEST(console_edit_runs_full_screen_on_the_card) {
    Con m(DISK_IMG_PATH);
    CHECK(m.ok && m.prompt());
    m.type("EDIT\r");
    // Its bottom lines are at the screen's real last row: it asked the terminal the size.
    uint64_t spent = 0;
    while (m.row(29).empty() && spent < 60000000) spent += m.s.bus.run(200000);
    CHECK(!m.row(29).empty());
    CHECK(m.screen().find("6309 BIOS") == std::string::npos); // (the alternate screen)
    CHECK(m.v.card().term.alt);
    // Typing and an arrow.
    m.type("abc");
    m.hit(0x50); // left
    m.hit(0x50);
    m.type("Z");
    spent = 0;
    while (m.screen().find("aZbc") == std::string::npos && spent < 30000000) spent += m.s.bus.run(200000);
    CHECK(m.screen().find("aZbc") != std::string::npos);
    // Out, without saving (X, then N at "save?"): the shell's screen is back.
    m.ctrl(0x1B);
    m.s.bus.run(2000000);
    m.type("n");
    spent = 0;
    while (m.v.card().term.alt && spent < 60000000) spent += m.s.bus.run(200000);
    CHECK(!m.v.card().term.alt);
    CHECK(m.wait("6309 BIOS"));
    // The cursor is back below the command that started it, not somewhere in the old text.
    int edit_row = -1;
    for (int y = 0; y < VC_TERM_ROWS; ++y)
        if (m.row(y).find("EDIT") != std::string::npos) edit_row = y;
    CHECK(edit_row >= 0);
    m.s.bus.run(5000000);
    CHECK(m.v.card().term.y > edit_row);
}

TEST(console_no_disk_asks_and_a_key_tries_again) {
    Con m(nullptr);
    CHECK(m.ok);
    CHECK(m.wait("Insert a bootable SD card"));
    // The S-record loader is listening on the UART all the while.
    CHECK(m.s.wait_for("Send S-Record"));
    m.s.received.clear();
    m.hit(0x04);
    CHECK(m.s.wait_for("6309 BIOS"));
    CHECK(m.wait("Insert a bootable SD card"));
    CHECK(m.s.wait_for("Send S-Record"));
}

TEST(console_crash_message_is_on_both) {
    Con m(DISK_IMG_PATH);
    CHECK(m.ok && m.prompt());
    m.s.received.clear();
    m.s.bus.ram()[0x7000] = 0x01; // not an opcode
    hd6309_regs_t r{};
    hd6309_get_regs(m.s.bus.cpu(), &r);
    r.pc = 0x7000;
    hd6309_set_regs(m.s.bus.cpu(), &r);
    CHECK(m.s.wait_for("ILLEGAL OPCODE at $"));
    CHECK(m.wait("ILLEGAL OPCODE at $"));
    CHECK(m.prompt()); // and the shell comes back
}

TEST(console_stays_on_the_uart_when_the_card_does_not_want_it) {
    Basic309Session s;
    VideoDevice v; // (not set_console)
    s.attach_video(&v);
    CHECK(s.boot_shell(PUGBIOS_S19_PATH, DISK_IMG_PATH));
    CHECK(s.received.find("> ") != std::string::npos);
    CHECK(v.card().term.started == 0);
}
