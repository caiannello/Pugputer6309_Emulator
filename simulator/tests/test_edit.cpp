// EDIT.COM (edit/edit.asm), the nano-style full-screen editor, driven through the
// whole boot chain (BIOS -> SD boot -> DOS -> SHELL.COM -> EDIT.COM) with real
// keystrokes. A small terminal model (Screen) interprets the editor's ANSI output,
// so the tests check what the screen shows as well as the files the editor writes;
// it can also answer the editor's terminal-size query (ESC [ 6 n) the way a real
// terminal does, or stay silent like one that can't.
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

#include "basic309_session.hpp"
#include "disk_images.hpp"
#include "fat16_reader.hpp"
#include "test_framework.hpp"

namespace {

// Enough of a VT100 / xterm for what EDIT sends: cursor positioning, erase in line
// / display, insert / delete line inside a scroll region, save / restore cursor,
// inverse video.
struct Screen {
    int rows = 24, cols = 80;
    std::vector<std::string> text;
    std::vector<std::string> inv; // 'I' where the cell is in inverse video
    int r = 0, c = 0, top = 0, bot = 23, saved_r = 0, saved_c = 0;
    bool inverse = false;
    std::string pending; // an escape sequence not complete yet

    void resize(int nr, int nc) {
        rows = nr;
        cols = nc;
        text.assign(rows, std::string(cols, ' '));
        inv.assign(rows, std::string(cols, ' '));
        r = c = top = 0;
        bot = rows - 1;
    }
    Screen() { resize(24, 80); }

    void blank_line(int row) {
        text[row].assign(cols, ' ');
        inv[row].assign(cols, ' ');
    }
    void scroll_up(int from, int to) { // lines from+1..to move up one; a blank one at `to`
        for (int i = from; i < to; ++i) {
            text[i] = text[i + 1];
            inv[i] = inv[i + 1];
        }
        blank_line(to);
    }
    void scroll_down(int from, int to) {
        for (int i = to; i > from; --i) {
            text[i] = text[i - 1];
            inv[i] = inv[i - 1];
        }
        blank_line(from);
    }
    void put(char ch) {
        if (c >= cols) { // the delayed wrap
            c = 0;
            newline();
        }
        text[r][c] = ch;
        inv[r][c] = inverse ? 'I' : ' ';
        ++c;
    }
    void newline() {
        if (r == bot)
            scroll_up(top, bot);
        else if (r < rows - 1)
            ++r;
    }
    void csi(const std::string& params, char final) {
        std::vector<int> p;
        bool priv = !params.empty() && params[0] == '?';
        std::string body = priv ? params.substr(1) : params;
        size_t i = 0;
        while (i <= body.size()) {
            size_t j = body.find(';', i);
            if (j == std::string::npos) j = body.size();
            p.push_back(j > i ? std::atoi(body.substr(i, j - i).c_str()) : 0);
            i = j + 1;
        }
        auto arg = [&](size_t k, int dflt) { return k < p.size() && p[k] ? p[k] : dflt; };
        if (priv) return; // ?1049h/l and the like
        switch (final) {
        case 'H':
            r = std::min(arg(0, 1), rows) - 1;
            c = std::min(arg(1, 1), cols) - 1;
            break;
        case 'K':
            for (int k = c; k < cols; ++k) {
                text[r][k] = ' ';
                inv[r][k] = ' ';
            }
            break;
        case 'J':
            if (arg(0, 0) == 2)
                for (int k = 0; k < rows; ++k) blank_line(k);
            break;
        case 'm':
            for (int v : p) {
                if (v == 7) inverse = true;
                if (v == 0 || v == 27) inverse = false;
            }
            break;
        case 'L':
            if (r >= top && r <= bot) scroll_down(r, bot);
            break;
        case 'M':
            if (r >= top && r <= bot) scroll_up(r, bot);
            break;
        case 'r':
            top = arg(0, 1) - 1;
            bot = arg(1, rows) - 1;
            r = c = 0;
            break;
        default:
            break;
        }
    }
    void feed(const std::string& s) {
        for (char ch : s) {
            if (!pending.empty()) {
                pending += ch;
                if (pending.size() == 2) {
                    if (ch == '7') {
                        saved_r = r;
                        saved_c = c;
                        pending.clear();
                    } else if (ch == '8') {
                        r = saved_r;
                        c = saved_c;
                        pending.clear();
                    } else if (ch != '[') {
                        pending.clear();
                    }
                } else if (ch >= 0x40 && ch <= 0x7E) {
                    csi(pending.substr(2, pending.size() - 3), ch);
                    pending.clear();
                }
                continue;
            }
            if (ch == 0x1B)
                pending = "\x1b";
            else if (ch == '\r')
                c = 0;
            else if (ch == '\n')
                newline();
            else if (ch == 8) {
                if (c > 0) --c;
            } else if (static_cast<unsigned char>(ch) >= 0x20)
                put(ch);
        }
    }
    std::string row(int n) const { // 1-based, trailing blanks trimmed
        std::string t = text[n - 1];
        t.erase(t.find_last_not_of(' ') + 1);
        return t;
    }
};

struct Editor {
    Basic309Session s;
    Screen scr;
    std::string img;
    int reply_rows = 0, reply_cols = 0; // 0: the terminal doesn't answer size queries
    bool hog = false; // first run HOG.COM, which takes every free RAM page (so EDIT gets none)
    size_t scanned = 0, fed = 0;
    int queries = 0;

    // Boots the shell from a fresh disk holding EDIT.COM and `files`, and types `cmdline`.
    bool start(const char* image_name, std::vector<pugputer::Fat16File> files, const std::string& cmdline) {
        pugputer::Fat16File edit;
        edit.name = "EDIT.COM";
        std::ifstream f(EDIT_BIN_PATH, std::ios::binary);
        if (!f) return false;
        edit.data.assign((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
        files.push_back(std::move(edit));
        if (hog) {
            // HOG.COM: LDA #B_PAGE_ALLOC ; SWI2 ; BCC (back) ; LDA #B_EXIT ; SWI2. Pages a
            // program takes stay taken after it ends.
            pugputer::Fat16File h;
            h.name = "HOG.COM";
            h.data = {'P', 'X', 0x40, 0x00, 0x40, 0x00, 0, 0, 0x86, 0x2F, 0x10, 0x3F, 0x24, 0xFA, 0x86, 0x2B, 0x10, 0x3F};
            files.push_back(std::move(h));
        }
        img = build_image(image_name, 16384, 2, std::move(files));
        if (img.empty() || !s.boot_shell(PUGBIOS_S19_PATH, img.c_str())) return false;
        if (reply_rows) scr.resize(reply_rows, reply_cols);
        sync();
        if (hog) {
            for (char ch : std::string("HOG\r")) s.send_byte(static_cast<uint8_t>(ch));
            settle();
            if (!at_shell()) return false;
        }
        for (char ch : cmdline) s.send_byte(static_cast<uint8_t>(ch));
        s.send_byte('\r');
        settle();
        return true;
    }
    // Answers new size queries (if this terminal does) and shows the new output.
    void sync() {
        size_t q;
        while ((q = s.received.find("\x1b[6n", scanned)) != std::string::npos) {
            scanned = q + 4;
            ++queries;
            if (reply_rows) {
                std::string rep = "\x1b[" + std::to_string(reply_rows) + ";" + std::to_string(reply_cols) + "R";
                for (char ch : rep) s.uart.rx_enqueue(static_cast<uint8_t>(ch));
            }
        }
        if (s.received.size() > scanned + 3) scanned = s.received.size() - 3;
        scr.feed(s.received.substr(fed));
        fed = s.received.size();
    }
    // Runs until the output has been quiet for a while.
    void settle() {
        size_t last = s.received.size();
        int quiet = 0;
        uint64_t spent = 0;
        while (quiet < 150 && spent < 400000000) {
            spent += s.bus.run(20000);
            sync();
            if (s.received.size() == last)
                ++quiet;
            else {
                quiet = 0;
                last = s.received.size();
            }
        }
    }
    // Runs until the status line shows `needle` (for work that takes a while
    // with nothing to show: loading or writing a big file).
    bool wait_status(const std::string& needle, uint64_t budget = 400000000) {
        uint64_t spent = 0;
        while (status().find(needle) == std::string::npos && spent < budget) {
            spent += s.bus.run(20000);
            sync();
        }
        settle();
        return status().find(needle) != std::string::npos;
    }
    void keys(const std::string& k) {
        for (char ch : k) {
            s.send_byte(static_cast<uint8_t>(ch));
            sync();
        }
        settle();
    }
    std::string row(int n) const { return scr.row(n); }
    std::string status() const { return scr.row(scr.rows - 2); }
    // With EDIT_DEBUG set: the screen, and the end of the raw output.
    void dump(const char* what) const {
        if (!std::getenv("EDIT_DEBUG")) return;
        std::printf("---- %s\n", what);
        for (int i = 1; i <= scr.rows; ++i) std::printf("%2d|%s\n", i, scr.row(i).c_str());
        std::string tail = s.received.substr(s.received.size() > 400 ? s.received.size() - 400 : 0);
        for (char ch : tail) {
            if (ch == 0x1B)
                std::printf("<E>");
            else if (static_cast<unsigned char>(ch) < 0x20)
                std::printf("<%02X>", ch);
            else
                std::printf("%c", ch);
        }
        std::printf("\n");
    }
    bool at_shell() const {
        return s.received.size() >= 2 && s.received.compare(s.received.size() - 2, 2, "> ") == 0;
    }
    // A file on the disk, "<none>" if it isn't there.
    std::string file(const std::string& path) const {
        Fat16Volume v;
        if (!v.load(img.c_str())) return "<no image>";
        Fat16Volume::Entry e;
        if (!v.find(path, e)) return "<none>";
        std::vector<uint8_t> d = v.read(e);
        return std::string(d.begin(), d.end());
    }
};

pugputer::Fat16File text(const std::string& name, const std::string& t) {
    pugputer::Fat16File f;
    f.name = name;
    f.data.assign(t.begin(), t.end());
    return f;
}

bool has(const std::string& hay, const std::string& needle) { return hay.find(needle) != std::string::npos; }

std::string ctrl(char letter) { return std::string(1, static_cast<char>(letter & 0x1F)); }
std::string meta(char key) { return std::string("\x1b") + key; }
const std::string UP = "\x1b[A", DOWN = "\x1b[B", RIGHT = "\x1b[C", LEFT = "\x1b[D";
const std::string HOME = "\x1b[H", END = "\x1b[F", PGUP = "\x1b[5~", PGDN = "\x1b[6~", DEL = "\x1b[3~";

// The start of the text area (ARENA_LO in edit.lst): how much text fits.
long arena_size() {
    std::ifstream f(EDIT_LST_PATH);
    std::string line;
    while (std::getline(f, line)) {
        size_t k = line.find("] ARENA_LO ");
        if (k != std::string::npos) return 0xF000 - std::strtol(line.substr(line.find_last_of(' ') + 1).c_str(), nullptr, 16);
    }
    return -1;
}

} // namespace

TEST(edit_shows_a_file_edits_it_and_writes_it_back) {
    Editor e;
    CHECK(e.start("edit1.img", {text("NOTE.TXT", "alpha\r\nbeta\r\n")}, "edit note.txt"));
    CHECK(has(e.row(1), "NANO6309 1.0") && has(e.row(1), "File: note.txt") && !has(e.row(1), "Modified"));
    CHECK(e.scr.inv[0].find(' ') == std::string::npos); // the title bar is all inverse
    CHECK(e.row(2) == "alpha");
    CHECK(e.row(3) == "beta");
    CHECK(e.row(4) == "");
    CHECK(has(e.status(), "[ Read 2 lines ]"));
    CHECK(has(e.row(23), "^G Get Help") && has(e.row(23), "^O WriteOut") && has(e.row(23), "^C Cur Pos"));
    CHECK(has(e.row(24), "^X Exit") && has(e.row(24), "^W Where Is") && has(e.row(24), "M-6 Copy Text"));

    e.keys(ctrl('E') + "!");                 // end of the line, type
    CHECK(e.row(2) == "alpha!");
    CHECK(has(e.row(1), "Modified"));
    CHECK(has(e.status(), "[ line 1/3, col 7 ]"));
    e.keys(DOWN + ctrl('K'));                // cut "beta"
    CHECK(e.row(2) == "alpha!");
    CHECK(e.row(3) == "");
    CHECK(has(e.status(), "[ line 2/2, col 1 ]"));
    e.keys(UP + ctrl('U'));                  // paste it above
    CHECK(e.row(2) == "beta");
    CHECK(e.row(3) == "alpha!");
    CHECK(has(e.status(), "[ line 2/3, col 1 ]"));

    e.keys(ctrl('O'));                       // write out, keeping the name
    CHECK(has(e.status(), "File Name to Write: note.txt"));
    CHECK(has(e.row(23), "^C Cancel"));
    e.keys("\r");
    CHECK(has(e.status(), "[ Wrote 2 lines ]"));
    CHECK(!has(e.row(1), "Modified"));
    e.keys(ctrl('X'));                       // nothing unsaved: straight out
    CHECK(e.at_shell());
    CHECK(e.file("NOTE.TXT") == "beta\r\nalpha!\r\n");
}

TEST(edit_a_new_file_asks_to_save_on_exit) {
    Editor e;
    CHECK(e.start("edit2.img", {}, "EDIT NEW.TXT"));
    CHECK(has(e.status(), "[ New File ]"));
    CHECK(has(e.row(1), "File: NEW.TXT"));
    e.keys("hello\rworld");
    CHECK(e.row(2) == "hello");
    CHECK(e.row(3) == "world");
    e.keys(ctrl('X'));
    CHECK(has(e.status(), "Save modified buffer (ANSWERING \"No\" WILL DESTROY CHANGES) ?"));
    CHECK(has(e.row(23), "Y Yes") && has(e.row(24), "N No") && has(e.row(24), "^C Cancel"));
    e.keys(ctrl('C'));                       // not after all
    CHECK(has(e.status(), "[ Cancelled ]"));
    CHECK(e.row(3) == "world");
    e.keys(ctrl('X') + "y");
    CHECK(has(e.status(), "File Name to Write: NEW.TXT"));
    e.keys("\r");
    CHECK(e.at_shell());
    CHECK(e.file("NEW.TXT") == "hello\r\nworld\r\n"); // CR LF, and the last line ended

    Editor f;                                // "No" leaves the disk alone
    CHECK(f.start("edit3.img", {}, "EDIT GONE.TXT"));
    f.keys("text" + ctrl('X') + "n");
    CHECK(f.at_shell());
    CHECK(f.file("GONE.TXT") == "<none>");
}

TEST(edit_search_mark_copy_and_paste) {
    Editor e;
    CHECK(e.start("edit4.img", {text("T.TXT", "one two three\r\nfour\r\n")}, "EDIT T.TXT"));
    e.keys(ctrl('W'));
    CHECK(has(e.status(), "Search:"));
    e.keys("TWO\r");                         // case doesn't matter
    CHECK(has(e.status(), "[ line 1/3, col 5 ]"));
    e.keys(ctrl('C'));
    CHECK(has(e.status(), "[ line 1/3 (33%), col 5/14 (35%), char 5/20 (25%) ]"));
    e.keys(meta('a'));
    CHECK(has(e.status(), "[ Mark Set ]"));
    e.keys(RIGHT + RIGHT + RIGHT);           // "two" marked: in inverse
    CHECK(e.scr.inv[1].substr(0, 14) == "    III       ");
    e.keys(meta('6'));                       // copy it; the mark goes
    CHECK(e.scr.inv[1].find('I') == std::string::npos);
    CHECK(has(e.status(), "[ line 1/3, col 8 ]"));
    e.keys(meta('/') + ctrl('U'));           // the end of the text, paste
    CHECK(e.row(4) == "two");
    e.keys(ctrl('W'));
    CHECK(has(e.status(), "Search [TWO]:"));
    e.keys("\r");                            // again: round from the top
    CHECK(has(e.status(), "[ Search Wrapped ]"));
    e.keys(meta('W'));
    CHECK(has(e.status(), "[ line 3/3, col 1 ]"));
    e.keys(ctrl('W') + "zzz\r");
    CHECK(has(e.status(), "[ \"zzz\" not found ]"));
    e.keys(meta('\\'));                      // first line
    CHECK(has(e.status(), "[ line 1/3, col 1 ]"));
    e.keys(ctrl('O') + "\r" + ctrl('X'));
    CHECK(e.at_shell());
    CHECK(e.file("T.TXT") == "one two three\r\nfour\r\ntwo\r\n");
}

TEST(edit_cuts_collect_lines_and_other_keys) {
    Editor e;
    CHECK(e.start("edit5.img", {text("L.TXT", "1\n2\n3\n4\n5\n")}, "EDIT L.TXT"));
    e.keys(DOWN + ctrl('K') + ctrl('K'));    // two cuts in a row: "2" and "3" together
    CHECK(e.row(2) == "1" && e.row(3) == "4" && e.row(4) == "5");
    e.keys(DOWN + DOWN + ctrl('U'));         // paste both at the end
    CHECK(e.row(4) == "5" && e.row(5) == "2" && e.row(6) == "3" && e.row(7) == "");
    e.keys(HOME + ctrl('U'));                // the same again
    CHECK(e.row(7) == "2" && e.row(8) == "3");
    e.keys(meta('\\') + "x" + DEL + DEL + "\x7f");  // Del joins lines, Backspace
    CHECK(e.row(2) == "4");
    e.keys(ctrl('E') + ctrl('H') + ctrl('D') + ctrl('B') + ctrl('F')); // ^H, ^D at the end
    CHECK(e.row(2) == "5");
    e.keys(ctrl('O') + "\r" + ctrl('X'));
    CHECK(e.at_shell());
    CHECK(e.file("L.TXT") == "5\n2\n3\n2\n3\n"); // bare LFs stay bare
}

TEST(edit_open_another_file_and_a_new_buffer) {
    Editor e;
    CHECK(e.start("edit6.img", {text("A.TXT", "aaa\r\n"), text("B.TXT", "bbb\r\n")}, "EDIT A.TXT"));
    e.keys("x" + ctrl('R'));                 // changed: asks first
    CHECK(has(e.status(), "Save modified buffer"));
    e.keys("n");
    CHECK(has(e.status(), "File to Read (Enter alone: New Buffer):"));
    e.keys("b.txt\r");
    CHECK(has(e.row(1), "File: b.txt"));
    CHECK(e.row(2) == "bbb");
    CHECK(has(e.status(), "[ Read 1 line ]"));
    e.keys(ctrl('R') + "\r");                // Enter alone: an empty new buffer
    CHECK(has(e.row(1), "New Buffer"));
    CHECK(e.row(2) == "");
    e.keys("new" + ctrl('O'));
    CHECK(has(e.status(), "File Name to Write:"));
    e.keys("b.txt\r");                       // there already: asks
    CHECK(has(e.status(), "File exists, OVERWRITE ?"));
    e.keys("n");
    CHECK(has(e.status(), "[ Cancelled ]"));
    e.keys(ctrl('O') + "c.txt\r" + ctrl('X'));
    CHECK(e.at_shell());
    CHECK(e.file("A.TXT") == "aaa\r\n");     // "No": never written
    CHECK(e.file("B.TXT") == "bbb\r\n");
    CHECK(e.file("C.TXT") == "new\r\n");
}

TEST(edit_help_screen) {
    Editor e;
    CHECK(e.start("edit7.img", {}, "EDIT"));
    CHECK(has(e.row(1), "New Buffer"));
    e.keys(ctrl('G'));
    CHECK(has(e.row(2), "EDIT: a small text editor"));
    CHECK(has(e.row(12), "M-\\ M-|     first line"));
    CHECK(has(e.row(23), "^X Exit Help"));
    e.keys(ctrl('X'));                       // back to the (empty) text
    CHECK(has(e.row(23), "^G Get Help"));
    CHECK(!has(e.row(12), "first line"));
    e.keys(ctrl('X'));
    CHECK(e.at_shell());
}

TEST(edit_fits_itself_to_the_terminal_size) {
    Editor e;
    e.reply_rows = 30;
    e.reply_cols = 100;
    CHECK(e.start("edit8.img", {text("T.TXT", "hello\r\n")}, "EDIT T.TXT"));
    CHECK(e.queries == 1);
    CHECK(has(e.s.received, "\x1b[2;27r"));  // the scroll region: rows 2..ROWS-3
    CHECK(e.row(2) == "hello");
    CHECK(e.scr.inv[0].find(' ') == std::string::npos && e.scr.inv[0].size() == 100);
    CHECK(has(e.row(29), "^G Get Help"));
    CHECK(has(e.row(28), "[ Read 1 line ]"));
    e.reply_rows = 20;                       // the window shrinks
    e.reply_cols = 60;
    e.scr.resize(20, 60);
    e.keys(ctrl('L'));                       // ^L asks again
    CHECK(has(e.s.received, "\x1b[2;17r"));
    CHECK(e.row(2) == "hello");
    CHECK(has(e.row(19), "^G Get Help"));
    CHECK(has(e.row(20), "^X Exit"));
    e.reply_rows = 24;                       // and after typing, it asks by itself
    e.reply_cols = 80;
    e.scr.resize(24, 80);
    int before = e.queries;
    e.keys("x");
    e.s.bus.run(4000000);
    e.settle();
    CHECK(e.queries > before);
    CHECK(e.row(2) == "xhello");
    CHECK(has(e.row(23), "^G Get Help"));
    e.keys(ctrl('X') + "n");
    CHECK(e.at_shell());
}

TEST(edit_scrolls_long_files_and_lines) {
    std::string t;
    for (int i = 1; i <= 60; ++i) t += "line " + std::to_string(i) + "\r\n";
    t += std::string(150, 'w') + "END\r\n";
    Editor e;
    CHECK(e.start("edit9.img", {text("LONG.TXT", t)}, "EDIT LONG.TXT"));
    CHECK(e.row(2) == "line 1" && e.row(21) == "line 20");
    e.keys(PGDN);                            // a page is the 20 text rows less 2
    CHECK(e.row(2) == "line 19" && e.row(21) == "line 38");
    CHECK(has(e.status(), "[ line 19/62, col 1 ]"));
    e.keys(PGUP);
    CHECK(e.row(2) == "line 1");
    for (int i = 0; i < 20; ++i) e.keys(DOWN); // one past the bottom: scrolls by one
    CHECK(e.row(2) == "line 2" && e.row(21) == "line 21");
    e.keys(UP + UP);
    for (int i = 0; i < 18; ++i) e.keys(UP);  // one above the top
    CHECK(e.row(2) == "line 1" && e.row(3) == "line 2" && e.row(21) == "line 20");
    e.keys(meta('/') + UP);                  // the long line, 153 columns
    CHECK(has(e.status(), "[ line 61/62, col 1 ]"));
    CHECK(e.row(2 + 61 - std::stoi(e.row(2).substr(5))) == std::string(79, 'w') + "$");
    e.keys(END);                             // shown a page further on, with "$" first
    int r = 2 + 61 - std::stoi(e.row(2).substr(5));
    CHECK(e.row(r).substr(0, 1) == "$");
    CHECK(has(e.row(r), "wEND"));
    CHECK(has(e.status(), "col 154 ]"));
    e.keys(DOWN);                            // leaving it: drawn from the start again
    CHECK(e.row(r) == std::string(79, 'w') + "$");
    e.keys(ctrl('X'));
    CHECK(e.at_shell());
}

// Random editing: afterwards, every text row on the screen must be a line of what
// the editor writes out, in order -- the incremental redraw never loses track.
TEST(edit_screen_stays_true_to_the_text) {
    std::string t;
    for (int i = 1; i <= 40; ++i) t += "row " + std::to_string(i) + "\r\n";
    Editor e;
    CHECK(e.start("edit10.img", {text("R.TXT", t)}, "EDIT R.TXT"));
    const std::vector<std::string> moves = {UP, DOWN, LEFT, RIGHT, HOME, END, PGUP, PGDN, DEL, "\x7f", "\r",
                                            ctrl('K'), ctrl('U'), "a", "b", DOWN + DOWN + DOWN, meta('6')};
    uint32_t seed = 12345;
    std::string script;
    for (int i = 0; i < 160; ++i) {
        seed = seed * 1103515245u + 12345u;
        script += moves[(seed >> 16) % moves.size()];
    }
    for (size_t i = 0; i < script.size(); i += 12) e.keys(script.substr(i, 12));
    std::vector<std::string> shown;
    for (int r = 2; r <= 21; ++r) shown.push_back(e.row(r));
    e.keys(ctrl('O') + "\r");
    CHECK(has(e.status(), "[ Wrote "));
    std::string saved = e.file("R.TXT");
    std::vector<std::string> lines;
    size_t p = 0;
    while (p < saved.size()) {
        size_t q = saved.find("\r\n", p);
        lines.push_back(saved.substr(p, q - p));
        p = q + 2;
    }
    lines.push_back(""); // the empty line after the last line end
    // find where the screen starts in the file
    bool match = false;
    for (size_t start = 0; start < lines.size() && !match; ++start) {
        bool ok = true;
        for (size_t k = 0; k < shown.size() && ok; ++k) {
            std::string want = start + k < lines.size() ? lines[start + k] : "";
            ok = shown[k] == want;
        }
        match = ok;
    }
    CHECK(match);
    if (!match) {
        std::printf("  screen:\n");
        for (auto& s : shown) std::printf("    [%s]\n", s.c_str());
        std::printf("  file:\n%s\n", saved.c_str());
    }
    e.keys(ctrl('X'));
    CHECK(e.at_shell());
}

TEST(edit_screen_stays_true_to_the_text_across_the_window) {
    // The same, on a text twice the arena, with page bursts and jumps to the ends that
    // move the window through the banked RAM between the edits.
    std::string t;
    for (int i = 1; i <= 1200; ++i) t += "row " + std::to_string(i) + std::string(56, '-') + "\r\n";
    CHECK(static_cast<long>(t.size()) > 2 * arena_size());
    Editor e;
    CHECK(e.start("edit14.img", {text("R.TXT", t)}, "EDIT R.TXT"));
    CHECK(e.wait_status("[ Read 1200 lines ]", 4000000000ull));
    const std::string burst = PGDN + PGDN + PGDN + PGDN + PGDN + PGDN;
    const std::vector<std::string> moves = {UP,  DOWN,       PGUP,       PGDN,       burst,     END,   HOME,
                                            DEL, "\x7f",     "\r",       ctrl('K'),  ctrl('U'), "a",   meta('6'),
                                            burst, meta('/'), meta('\\'), PGUP + PGUP + PGUP + PGUP + PGUP};
    uint32_t seed = std::getenv("EDIT_SEED") ? static_cast<uint32_t>(std::atoi(std::getenv("EDIT_SEED"))) : 4242;
    for (int i = 0; i < 200; ++i) {
        seed = seed * 1103515245u + 12345u;
        e.keys(moves[(seed >> 16) % moves.size()]);
    }
    e.keys(ctrl('C')); // (after everything before it is done)
    CHECK(e.wait_status("char ", 4000000000ull));
    std::string pos = e.status();
    std::vector<std::string> shown;
    for (int r = 2; r <= 21; ++r) shown.push_back(e.row(r));
    e.keys(ctrl('O') + "\r");
    CHECK(e.wait_status("[ Wrote ", 4000000000ull));
    std::string saved = e.file("R.TXT");
    std::vector<std::string> lines;
    size_t p = 0, chars = 0;
    while (p < saved.size()) {
        size_t q = saved.find("\r\n", p);
        lines.push_back(saved.substr(p, q - p));
        chars += q - p + 1;
        p = q + 2;
    }
    lines.push_back("");
    // (A line longer than the screen shows its first 79 columns and a "$".)
    auto same = [](const std::string& row, const std::string& line) {
        if (row.size() == 80 && row.back() == '$') return line.size() > 79 && line.compare(0, 79, row, 0, 79) == 0;
        return row == line;
    };
    bool match = false;
    for (size_t start = 0; start < lines.size() && !match; ++start) {
        bool ok = true;
        for (size_t k = 0; k < shown.size() && ok; ++k) ok = same(shown[k], start + k < lines.size() ? lines[start + k] : "");
        match = ok;
    }
    CHECK(match);
    if (!match && std::getenv("EDIT_DEBUG")) {
        std::printf("  status: %s\n  screen:\n", pos.c_str());
        for (auto& s : shown) std::printf("    [%s]\n", s.c_str());
        for (size_t start = 0; start < lines.size(); ++start)
            if (lines[start] == shown[0] || lines[start] == shown[1]) {
                std::printf("  file from line %zu:\n", start + 1);
                for (size_t k = start; k < lines.size() && k < start + 20; ++k) std::printf("    [%s]\n", lines[k].c_str());
            }
    }
    // ^C's count of the whole text (+1) agrees with the file (its lines all end in LF).
    CHECK(has(pos, "/" + std::to_string(chars + 1) + " (") || has(pos, "/" + std::to_string(chars) + " ("));
    e.keys(ctrl('X'));
    CHECK(e.at_shell());
}

TEST(edit_window_moves_keep_the_text_intact) {
    // Random moves and jumps through a text three times the arena, typing a "#" here
    // and there: take the "#"s out of what is written, and it is the text as read.
    std::string t;
    for (int i = 1; i <= 1600; ++i) t += "L" + std::to_string(i) + ":" + std::string(i % 97, 'a' + i % 26) + "\r\n";
    CHECK(static_cast<long>(t.size()) > 2 * arena_size());
    Editor e;
    CHECK(e.start("edit15.img", {text("T.TXT", t)}, "EDIT T.TXT"));
    CHECK(e.wait_status("[ Read 1600 lines ]", 4000000000ull));
    const std::string burst = PGDN + PGDN + PGDN + PGDN + PGDN + PGDN + PGDN + PGDN;
    const std::vector<std::string> moves = {UP,   DOWN, LEFT, RIGHT,     PGUP,       PGDN,
                                            HOME, END,  "#",  meta('/'), meta('\\'), burst,
                                            "#",  PGUP + PGUP + PGUP + PGUP + PGUP + PGUP + PGUP, ctrl('W') + "L7\r"};
    uint32_t seed = std::getenv("EDIT_SEED") ? static_cast<uint32_t>(std::atoi(std::getenv("EDIT_SEED"))) : 777;
    int hashes = 0;
    for (int i = 0; i < 250; ++i) {
        seed = seed * 1103515245u + 12345u;
        const std::string& m = moves[(seed >> 16) % moves.size()];
        if (m == "#") ++hashes;
        e.keys(m);
    }
    e.keys(ctrl('O') + "\r");
    CHECK(e.wait_status("[ Wrote ", 4000000000ull));
    std::string saved = e.file("T.TXT"), stripped;
    int found = 0;
    for (char ch : saved)
        if (ch == '#')
            ++found;
        else
            stripped += ch;
    CHECK(found == hashes);
    // (A "#" typed after the last line is a line of its own, which is written with its CR LF.)
    if (stripped.size() == t.size() + 2 && stripped.compare(t.size(), 2, "\r\n") == 0) stripped.resize(t.size());
    CHECK(stripped == t);
    if (stripped != t) {
        size_t d = 0;
        while (d < t.size() && d < stripped.size() && t[d] == stripped[d]) ++d;
        std::printf("  sizes %zu %zu, first difference at %zu:\n  want [%s]\n  got  [%s]\n", t.size(), stripped.size(), d,
                    t.substr(d > 40 ? d - 40 : 0, 100).c_str(), stripped.substr(d > 40 ? d - 40 : 0, 100).c_str());
    }
    e.keys(ctrl('X'));
    CHECK(e.at_shell());
}

TEST(edit_cut_with_memory_full_and_too_large_files) {
    // With no RAM pages free, EDIT has only its window: the arena above the program.
    long room = arena_size();
    CHECK(room > 30000);
    // "A", then lines of 99 characters + CR LF (100 bytes in the editor, with just
    // the LF), filling all but 4 bytes of the space.
    std::string t = "A\r\n", body;
    long used = 2;
    int n = 0;
    while (used + 100 <= room - 4) {
        char head[16];
        std::snprintf(head, sizeof head, "%04d", n++);
        body += head + std::string(95, '.') + "\r\n";
        used += 100;
    }
    body += std::string(room - 4 - used - 1, 'z') + "\r\n"; // exactly room-4 bytes
    t += body;
    Editor e;
    e.hog = true;
    CHECK(e.start("edit11.img", {text("FULL.TXT", t)}, "EDIT FULL.TXT"));
    CHECK(e.wait_status("[ Read " + std::to_string(n + 2) + " lines ]"));
    e.keys("xyzw");                                   // the space is full now
    e.keys("Q");
    CHECK(has(e.status(), "[ Out of memory ]"));
    CHECK(e.row(2) == "xyzwA");
    e.keys(HOME + ctrl('K'));                         // no room in the gap: the cut line
    CHECK(has(e.row(2), "0000...."));                 // is rotated into the cut buffer
    e.keys(ctrl('U'));                                // it still takes the space
    CHECK(has(e.status(), "[ Out of memory ]"));
    e.keys(DEL + DEL + DEL + DEL + DEL + DEL);        // make room ...
    e.keys(ctrl('U'));                                // ... and paste it back
    CHECK(e.row(2) == "xyzwA");
    CHECK(e.row(3).substr(0, 10) == "..........");
    e.keys(ctrl('O') + "\r");
    CHECK(e.wait_status("[ Wrote "));
    CHECK(e.file("FULL.TXT") == "xyzwA\r\n" + body.substr(6));
    e.keys(ctrl('X'));
    CHECK(e.at_shell());

    Editor big;                                       // more than fits: refused
    big.hog = true;
    CHECK(big.start("edit12.img", {text("BIG.TXT", std::string(room + 10, 'q'))}, "EDIT BIG.TXT"));
    CHECK(big.wait_status("[ File too large to edit ]"));
    CHECK(has(big.row(1), "New Buffer"));
    big.keys(ctrl('X'));
    CHECK(big.at_shell());
}

TEST(edit_big_files_live_in_banked_ram) {
    // Five times what the arena holds: the rest of the text is in RAM pages above
    // 64KB, and the window moves through it.
    const int N = 2500;
    std::string body;
    for (int i = 1; i <= N; ++i) {
        char line[80];
        std::snprintf(line, sizeof line, "Line %05d: %s", i, std::string(60, 'a' + i % 26).c_str());
        body += line + std::string("\r\n");
    }
    CHECK(static_cast<long>(body.size()) > 5 * arena_size());
    Editor e;
    CHECK(e.start("edit13.img", {text("BIG.TXT", body)}, "EDIT BIG.TXT"));
    CHECK(e.wait_status("[ Read 2500 lines ]", 4000000000ull));
    CHECK(e.row(2).substr(0, 10) == "Line 00001");
    auto number = [](const std::string& row) { return row.compare(0, 5, "Line ") == 0 ? std::atoi(row.c_str() + 5) : -1; };
    // Page down well past the window: every row shows the line after the last.
    for (int i = 0; i < 60; ++i) e.keys(PGDN);
    int first = number(e.row(2));
    CHECK(first > 900);
    for (int r = 3; r <= 21; ++r) CHECK(number(e.row(r)) == first + (r - 2));
    for (int i = 0; i < 25; ++i) e.keys(PGUP); // and back up some
    int back = number(e.row(2));
    CHECK(back > 1 && back < first);
    for (int r = 3; r <= 21; ++r) CHECK(number(e.row(r)) == back + (r - 2));
    // The last line, and the position in the whole text.
    // (Jumps across the text take a while with nothing on the screen: they wait for
    // the status line.)
    const uint64_t LONG = 4000000000ull;
    e.keys(meta('/'));
    CHECK(e.wait_status("line 2501/2501", LONG));
    e.keys("END");
    e.keys(ctrl('C'));
    const long total = N * 73L + 3; // (in the editor, lines end in just LF)
    CHECK(has(e.status(), "char " + std::to_string(total + 1) + "/" + std::to_string(total + 1) + " (100%)"));
    // Search: from the end round to a line near the start, then on to one in the middle.
    e.keys(ctrl('W') + "line 00077\r");
    CHECK(e.wait_status("Search Wrapped", LONG));
    CHECK(number(e.row(2)) <= 77);
    e.keys(ctrl('C'));
    CHECK(has(e.status(), "line 77/2501"));
    e.keys(ctrl('W') + "line 01500\r");
    CHECK(e.wait_status("line 1500/2501", LONG));
    // Cut that line, paste it at the top.
    e.keys(ctrl('K'));
    e.keys(meta('\\'));
    CHECK(e.wait_status("line 1/2500", LONG));  // (one line fewer: it was cut)
    CHECK(e.row(2).substr(0, 10) == "Line 00001");
    e.keys(ctrl('U'));
    CHECK(e.row(2).substr(0, 10) == "Line 01500");
    CHECK(e.row(3).substr(0, 10) == "Line 00001");
    e.keys("TOP");
    e.keys(ctrl('O') + "\r");
    CHECK(e.wait_status("[ Wrote 2501 lines ]", LONG));
    size_t at = body.find("Line 01500");
    std::string cut = body.substr(at, 74);
    std::string want = cut + "TOP" + body.substr(0, at) + body.substr(at + 74) + "END\r\n";
    CHECK(e.file("BIG.TXT") == want);
    // Mark the first lines (more than a screen, some of the window), cut them and
    // paste them at the far end.
    e.keys(meta('\\'));
    CHECK(e.wait_status("line 1/2501", LONG));
    e.keys(meta('A'));
    for (int i = 0; i < 9; ++i) e.keys(PGDN);
    std::string st = e.status();
    size_t lp = st.find("line ");
    CHECK(lp != std::string::npos);
    int k = std::atoi(st.c_str() + lp + 5) - 1; // whole lines marked
    CHECK(k > 100);
    e.keys(ctrl('K'));
    e.keys(meta('/'));
    CHECK(e.wait_status("line " + std::to_string(2501 - k) + "/", LONG));
    e.keys(ctrl('U'));
    e.keys(ctrl('O') + "\r");
    CHECK(e.wait_status("[ Wrote 2500 lines ]", LONG)); // ("END" and the first pasted line joined)
    size_t cutlen = 0;
    for (int i = 0; i < k; ++i) cutlen = want.find("\r\n", cutlen) + 2;
    std::string moved = want.substr(cutlen, want.size() - cutlen - 2) + want.substr(0, cutlen);
    CHECK(e.file("BIG.TXT") == moved);
    // The pages go back when it ends.
    e.keys(ctrl('X'));
    CHECK(e.at_shell());
    size_t from = e.s.received.size();
    for (char ch : std::string("MEM\r")) e.s.send_byte(static_cast<uint8_t>(ch));
    e.settle();
    CHECK(has(e.s.received.substr(from), "960 KB free"));
}
