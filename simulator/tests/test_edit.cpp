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
        img = build_image(image_name, 16384, 2, std::move(files));
        if (img.empty() || !s.boot_shell(PUGBIOS_S19_PATH, img.c_str())) return false;
        if (reply_rows) scr.resize(reply_rows, reply_cols);
        sync();
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
    bool wait_status(const std::string& needle) {
        uint64_t spent = 0;
        while (status().find(needle) == std::string::npos && spent < 400000000) {
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
    CHECK(has(e.row(1), "EDIT 1.0") && has(e.row(1), "File: note.txt") && !has(e.row(1), "Modified"));
    CHECK(e.scr.inv[0].find(' ') == std::string::npos); // the title bar is all inverse
    CHECK(e.row(3) == "alpha");
    CHECK(e.row(4) == "beta");
    CHECK(e.row(5) == "");
    CHECK(has(e.status(), "[ Read 2 lines ]"));
    CHECK(has(e.row(23), "^G Get Help") && has(e.row(23), "^O WriteOut") && has(e.row(23), "^C Cur Pos"));
    CHECK(has(e.row(24), "^X Exit") && has(e.row(24), "^W Where Is") && has(e.row(24), "M-6 Copy Text"));

    e.keys(ctrl('E') + "!");                 // end of the line, type
    CHECK(e.row(3) == "alpha!");
    CHECK(has(e.row(1), "Modified"));
    CHECK(has(e.status(), "[ line 1/3, col 7 ]"));
    e.keys(DOWN + ctrl('K'));                // cut "beta"
    CHECK(e.row(3) == "alpha!");
    CHECK(e.row(4) == "");
    CHECK(has(e.status(), "[ line 2/2, col 1 ]"));
    e.keys(UP + ctrl('U'));                  // paste it above
    CHECK(e.row(3) == "beta");
    CHECK(e.row(4) == "alpha!");
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
    CHECK(e.row(3) == "hello");
    CHECK(e.row(4) == "world");
    e.keys(ctrl('X'));
    CHECK(has(e.status(), "Save modified buffer (ANSWERING \"No\" WILL DESTROY CHANGES) ?"));
    CHECK(has(e.row(23), "Y Yes") && has(e.row(24), "N No") && has(e.row(24), "^C Cancel"));
    e.keys(ctrl('C'));                       // not after all
    CHECK(has(e.status(), "[ Cancelled ]"));
    CHECK(e.row(4) == "world");
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
    CHECK(e.scr.inv[2].substr(0, 14) == "    III       ");
    e.keys(meta('6'));                       // copy it; the mark goes
    CHECK(e.scr.inv[2].find('I') == std::string::npos);
    CHECK(has(e.status(), "[ line 1/3, col 8 ]"));
    e.keys(meta('/') + ctrl('U'));           // the end of the text, paste
    CHECK(e.row(5) == "two");
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
    CHECK(e.row(3) == "1" && e.row(4) == "4" && e.row(5) == "5");
    e.keys(DOWN + DOWN + ctrl('U'));         // paste both at the end
    CHECK(e.row(5) == "5" && e.row(6) == "2" && e.row(7) == "3" && e.row(8) == "");
    e.keys(HOME + ctrl('U'));                // the same again
    CHECK(e.row(8) == "2" && e.row(9) == "3");
    e.keys(meta('\\') + "x" + DEL + DEL + "\x7f");  // Del joins lines, Backspace
    CHECK(e.row(3) == "4");
    e.keys(ctrl('E') + ctrl('H') + ctrl('D') + ctrl('B') + ctrl('F')); // ^H, ^D at the end
    CHECK(e.row(3) == "5");
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
    CHECK(e.row(3) == "bbb");
    CHECK(has(e.status(), "[ Read 1 line ]"));
    e.keys(ctrl('R') + "\r");                // Enter alone: an empty new buffer
    CHECK(has(e.row(1), "New Buffer"));
    CHECK(e.row(3) == "");
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
    CHECK(has(e.s.received, "\x1b[3;27r"));  // the scroll region: rows 3..ROWS-3
    CHECK(e.row(3) == "hello");
    CHECK(e.scr.inv[0].find(' ') == std::string::npos && e.scr.inv[0].size() == 100);
    CHECK(has(e.row(29), "^G Get Help"));
    CHECK(has(e.row(28), "[ Read 1 line ]"));
    e.reply_rows = 20;                       // the window shrinks
    e.reply_cols = 60;
    e.scr.resize(20, 60);
    e.keys(ctrl('L'));                       // ^L asks again
    CHECK(has(e.s.received, "\x1b[3;17r"));
    CHECK(e.row(3) == "hello");
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
    CHECK(e.row(3) == "xhello");
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
    CHECK(e.row(3) == "line 1" && e.row(21) == "line 19");
    e.keys(PGDN);                            // a page is the 19 text rows less 2
    CHECK(e.row(3) == "line 18" && e.row(21) == "line 36");
    CHECK(has(e.status(), "[ line 18/62, col 1 ]"));
    e.keys(PGUP);
    CHECK(e.row(3) == "line 1");
    for (int i = 0; i < 19; ++i) e.keys(DOWN); // one past the bottom: scrolls by one
    CHECK(e.row(3) == "line 2" && e.row(21) == "line 20");
    e.keys(UP + UP);
    for (int i = 0; i < 18; ++i) e.keys(UP);  // one above the top
    CHECK(e.row(3) == "line 1" && e.row(4) == "line 2" && e.row(21) == "line 19");
    e.keys(meta('/') + UP);                  // the long line, 153 columns
    CHECK(has(e.status(), "[ line 61/62, col 1 ]"));
    CHECK(e.row(3 + 61 - std::stoi(e.row(3).substr(5))) == std::string(79, 'w') + "$");
    e.keys(END);                             // shown a page further on, with "$" first
    int r = 3 + 61 - std::stoi(e.row(3).substr(5));
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
    for (int r = 3; r <= 21; ++r) shown.push_back(e.row(r));
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

TEST(edit_cut_with_memory_full_and_too_large_files) {
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
    CHECK(e.start("edit11.img", {text("FULL.TXT", t)}, "EDIT FULL.TXT"));
    CHECK(e.wait_status("[ Read " + std::to_string(n + 2) + " lines ]"));
    e.keys("xyzw");                                   // the space is full now
    e.keys("Q");
    CHECK(has(e.status(), "[ Out of memory ]"));
    CHECK(e.row(3) == "xyzwA");
    e.keys(HOME + ctrl('K'));                         // no room in the gap: the cut line
    CHECK(has(e.row(3), "0000...."));                 // is rotated into the cut buffer
    e.keys(ctrl('U'));                                // it still takes the space
    CHECK(has(e.status(), "[ Out of memory ]"));
    e.keys(DEL + DEL + DEL + DEL + DEL + DEL);        // make room ...
    e.keys(ctrl('U'));                                // ... and paste it back
    CHECK(e.row(3) == "xyzwA");
    CHECK(e.row(4).substr(0, 10) == "..........");
    e.keys(ctrl('O') + "\r");
    CHECK(e.wait_status("[ Wrote "));
    CHECK(e.file("FULL.TXT") == "xyzwA\r\n" + body.substr(6));
    e.keys(ctrl('X'));
    CHECK(e.at_shell());

    Editor big;                                       // more than fits: refused
    CHECK(big.start("edit12.img", {text("BIG.TXT", std::string(room + 10, 'q'))}, "EDIT BIG.TXT"));
    CHECK(big.wait_status("[ File too large to edit ]"));
    CHECK(has(big.row(1), "New Buffer"));
    big.keys(ctrl('X'));
    CHECK(big.at_shell());
}
