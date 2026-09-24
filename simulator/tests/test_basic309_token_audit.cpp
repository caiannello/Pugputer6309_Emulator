// Token-table audit for basic309. Adding a keyword means keeping several
// hand-synchronized structures consistent: the reserved-word dictionaries
// (LAA66/LAB1A), their counts in COMVEC, the dispatch tables (CMD_TAB /
// FUNC_TAB) and the TOK_* constants the interpreter compares against. Twice
// now one of those was missed after an insertion and broke unrelated syntax
// (GOTO/STEP, then '=' assignment). This test cross-checks all of them from
// the assembled image + symbol table, and then types every keyword at the
// real interpreter and verifies the token byte the crunch routine stored --
// a LIST round-trip alone can't catch an uncrunched keyword, since LIST just
// shows the same letters either way.
//
// Needs basic309/exbasrom309.lst built with --symbols (basic309/build_basic.bat
// and reinit_disk.bat do that).
#include <cstdio>
#include <fstream>
#include <map>
#include <regex>
#include <set>
#include <string>
#include <vector>

#include "basic309_session.hpp"
#include "pugputer/srec_loader.hpp"
#include "test_framework.hpp"

namespace {

using SymbolMap = std::map<std::string, uint32_t>;

SymbolMap load_symbols(const char* lst_path) {
    SymbolMap syms;
    std::ifstream f(lst_path);
    std::string line;
    static const std::regex kSym(R"(^\[ *[A-Z]+\] +(\S+) +([0-9A-Fa-f]+) *$)");
    while (std::getline(f, line)) {
        std::smatch m;
        if (std::regex_match(line, m, kSym)) syms[m[1]] = static_cast<uint32_t>(std::stoul(m[2], nullptr, 16));
    }
    return syms;
}

// Reads `count` dictionary entries starting at `addr` (each entry's last
// character has bit 7 set). Returns the words; *end is the address just past
// the last entry read.
std::vector<std::string> walk_dictionary(const std::vector<uint8_t>& img, uint16_t addr, int count, uint16_t* end) {
    std::vector<std::string> words;
    for (int i = 0; i < count; ++i) {
        std::string w;
        for (;;) {
            uint8_t b = img[addr++];
            w += static_cast<char>(b & 0x7F);
            if (b & 0x80) break;
            if (w.size() > 12) { // runaway: no terminator where one was expected
                *end = addr;
                return words;
            }
        }
        words.push_back(w);
    }
    *end = addr;
    return words;
}

// Same walk, but bounded by the next table's address instead of trusting
// COMVEC's count -- so a wrong count can't hide words from the audit.
std::vector<std::string> walk_dictionary_until(const std::vector<uint8_t>& img, uint16_t addr, uint16_t stop) {
    std::vector<std::string> words;
    while (addr < stop) {
        std::string w;
        for (;;) {
            uint8_t b = img[addr++];
            w += static_cast<char>(b & 0x7F);
            if (b & 0x80) break;
        }
        words.push_back(w);
    }
    return words;
}

int index_of(const std::vector<std::string>& v, const std::string& w) {
    for (size_t i = 0; i < v.size(); ++i)
        if (v[i] == w) return static_cast<int>(i);
    return -1;
}

uint16_t be16(const uint8_t* mem, uint32_t a) { return static_cast<uint16_t>((mem[a] << 8) | mem[a + 1]); }

} // namespace

TEST(basic309_token_tables_are_internally_consistent) {
    SymbolMap sym = load_symbols(EXBASROM309_LST_PATH);
    CHECK(!sym.empty()); // else: rebuild with --list=... --symbols
    if (sym.empty()) {
        std::fprintf(stderr, "  no symbol table in %s -- assemble with --symbols\n", EXBASROM309_LST_PATH);
        return;
    }
    for (const char* need : {"COMVEC", "LAA66", "LAB1A", "CMD_TAB", "FUNC_TAB", "NUM_SEC_FNS", "TOK_HIGH_EXEC",
                             "TOK_TAB", "LABAF", "LAA29", "LAB67"}) {
        CHECK(sym.count(need) == 1);
        if (!sym.count(need)) {
            std::fprintf(stderr, "  missing symbol %s\n", need);
            return;
        }
    }

    std::vector<uint8_t> img(65536, 0);
    CHECK(pugputer::load_srec_file(EXBASROM309_S19_PATH, img.data(), img.size()).ok);

    // COMVEC header: count, dictionary, jump table, count, dictionary, jump table.
    const uint32_t cv = sym["COMVEC"];
    const int primary_count = img[cv];
    const int secondary_count = img[cv + 5];
    CHECK(be16(img.data(), cv + 1) == sym["LAA66"]);
    CHECK(be16(img.data(), cv + 3) == sym["LAB67"]);
    CHECK(be16(img.data(), cv + 6) == sym["LAB1A"]);
    CHECK(be16(img.data(), cv + 8) == sym["LAA29"]);

    // The counts must land each dictionary walk exactly on the next table.
    // A count that's too low silently hides the LAST entries from the crunch
    // routine (the '=' bug); too high walks into the next table.
    uint16_t end = 0;
    std::vector<std::string> primary = walk_dictionary(img, static_cast<uint16_t>(sym["LAA66"]), primary_count, &end);
    if (end != sym["LAB1A"])
        std::fprintf(stderr, "  COMVEC primary count %d walks to $%04X, but LAB1A is at $%04X\n", primary_count, end,
                     sym["LAB1A"]);
    CHECK(end == sym["LAB1A"]);

    std::vector<std::string> secondary =
        walk_dictionary(img, static_cast<uint16_t>(sym["LAB1A"]), secondary_count, &end);
    if (end != sym["CMD_TAB"])
        std::fprintf(stderr, "  COMVEC secondary count %d walks to $%04X, but CMD_TAB is at $%04X\n", secondary_count,
                     end, sym["CMD_TAB"]);
    CHECK(end == sym["CMD_TAB"]);
    CHECK(static_cast<uint32_t>(secondary_count) == sym["NUM_SEC_FNS"]); // FUNC_TAB length

    // Executable statements are the dictionary prefix before "TAB(" (the
    // first non-executable token); CMD_TAB must have one entry for each.
    const int tab_index = index_of(primary, "TAB(");
    CHECK(tab_index > 0);
    CHECK(sym["TOK_TAB"] == static_cast<uint32_t>(0x80 + tab_index));
    CHECK(sym["TOK_HIGH_EXEC"] == static_cast<uint32_t>(0x80 + tab_index - 1));
    CHECK((sym["LABAF"] - sym["CMD_TAB"]) / 2 == static_cast<uint32_t>(tab_index));

    // Every TOK_* constant must name the dictionary word at its own index.
    const std::map<std::string, std::string> primary_tokens = {
        {"TOK_FOR", "FOR"},   {"TOK_GO", "GO"},     {"TOK_REM", "REM"},   {"TOK_SNGL_Q", "'"},    {"TOK_ELSE", "ELSE"},
        {"TOK_IF", "IF"},     {"TOK_DATA", "DATA"}, {"TOK_PRINT", "PRINT"}, {"TOK_INPUT", "INPUT"},
        {"TOK_TAB", "TAB("},  {"TOK_TO", "TO"},     {"TOK_SUB", "SUB"},     {"TOK_THEN", "THEN"},
        {"TOK_NOT", "NOT"},   {"TOK_STEP", "STEP"}, {"TOK_PLUS", "+"},      {"TOK_MINUS", "-"},
        {"TOK_GREATER", ">"}, {"TOK_EQUALS", "="},  {"TOK_FN", "FN"},       {"TOK_USING", "USING"},
        {"TOK_NEXT", "NEXT"}, {"TOK_ERROR", "ERROR"},
    };
    const std::map<std::string, std::string> secondary_tokens = {
        {"TOK_USR", "USR"}, {"TOK_LEN", "LEN"}, {"TOK_LEFT", "LEFT$"}, {"TOK_MID", "MID$"}, {"TOK_INKEY", "INKEY$"},
    };
    for (const auto& [name, word] : primary_tokens) {
        int i = index_of(primary, word);
        bool ok = i >= 0 && sym.count(name) && sym[name] == static_cast<uint32_t>(0x80 + i);
        if (!ok)
            std::fprintf(stderr, "  %s = $%02X but dictionary word '%s' is token $%02X\n", name.c_str(),
                         sym.count(name) ? sym[name] : 0, word.c_str(), 0x80 + i);
        CHECK(ok);
    }
    for (const auto& [name, word] : secondary_tokens) {
        int i = index_of(secondary, word);
        bool ok = i >= 0 && sym.count(name) && sym[name] == static_cast<uint32_t>(0x80 + i);
        if (!ok)
            std::fprintf(stderr, "  %s = $%02X but secondary word '%s' is token $%02X\n", name.c_str(),
                         sym.count(name) ? sym[name] : 0, word.c_str(), 0x80 + i);
        CHECK(ok);
    }
    CHECK(sym["TOK_FF_USR"] == 0xFF00u + sym["TOK_USR"]);

    // The dispatch tables must hold the right handler at each word's position.
    // (The count check above can't see two FDBs listed in swapped order.) Only
    // handlers named after their keyword are listed; extend as statements are added.
    const std::map<std::string, std::string> statement_handlers = {
        {"LOAD", "LOAD"}, {"SAVE", "SAVE"},   {"FILES", "FILES"}, {"KILL", "KILL"},
        {"NAME", "NAME"}, {"OPEN", "OPEN"},   {"CLOSE", "CLOSE"}, {"WRITE", "WRITE"},
        {"FIELD", "FIELD"}, {"GET", "GET"},   {"PUT", "PUT"},     {"LSET", "LSET"},   {"RSET", "RSET"},
        {"MKDIR", "MKDIR"}, {"CHDIR", "CHDIR"}, {"RMDIR", "RMDIR"},
        {"PRINT", "PRINT"}, {"INPUT", "INPUT"}, {"LINE", "LINE"},
    };
    for (const auto& [word, handler] : statement_handlers) {
        int i = index_of(primary, word);
        bool ok = i >= 0 && sym.count(handler) && be16(img.data(), sym["CMD_TAB"] + 2 * i) == sym[handler];
        if (!ok) std::fprintf(stderr, "  CMD_TAB entry for '%s' does not point at %s\n", word.c_str(), handler.c_str());
        CHECK(ok);
    }
    const std::map<std::string, std::string> function_handlers = {
        {"EOF", "EOFFN"}, {"LOF", "LOFFN"}, {"LOC", "LOCFN"}, {"CVI", "CVIFN"}, {"CVS", "CVSFN"},
        {"MKI$", "MKIFN"}, {"MKS$", "MKSFN"}, {"HEX$", "HEXDOL"}, {"USR", "USRJMP"}};
    for (const auto& [word, handler] : function_handlers) {
        int i = index_of(secondary, word);
        bool ok = i >= 0 && sym.count(handler) && be16(img.data(), sym["FUNC_TAB"] + 2 * i) == sym[handler];
        if (!ok) std::fprintf(stderr, "  FUNC_TAB entry for '%s' does not point at %s\n", word.c_str(), handler.c_str());
        CHECK(ok);
    }

    // The fixed entry point (dos/dos.asm, the harnesses and demos all jump to
    // $C000): it must be a JMP straight to RESVEC.
    CHECK(img[0xC000] == 0x7E && be16(img.data(), 0xC001) == sym["RESVEC"]);

    // Any TOK_* symbol not covered above is a new token nobody audited:
    // add it to the tables in this test (that is the point of the check).
    std::set<std::string> known = {"TOK_HIGH_EXEC", "TOK_FF_USR"};
    for (const auto& kv : primary_tokens) known.insert(kv.first);
    for (const auto& kv : secondary_tokens) known.insert(kv.first);
    for (const auto& kv : sym) {
        if (kv.first.rfind("TOK_", 0) == 0 && !known.count(kv.first)) {
            std::fprintf(stderr, "  unaudited token symbol %s -- add it to test_basic309_token_audit.cpp\n",
                         kv.first.c_str());
            CHECK(false);
        }
    }
}

// Type each keyword alone on a numbered line and check the bytes the crunch
// routine stored for it (primary token: 1 byte; secondary function: $FF + 1).
TEST(basic309_every_keyword_crunches_to_its_dictionary_token) {
    SymbolMap sym = load_symbols(EXBASROM309_LST_PATH);
    CHECK(!sym.empty());
    if (sym.empty()) return;

    std::vector<uint8_t> img(65536, 0);
    CHECK(pugputer::load_srec_file(EXBASROM309_S19_PATH, img.data(), img.size()).ok);
    std::vector<std::string> primary =
        walk_dictionary_until(img, static_cast<uint16_t>(sym["LAA66"]), static_cast<uint16_t>(sym["LAB1A"]));
    std::vector<std::string> secondary =
        walk_dictionary_until(img, static_cast<uint16_t>(sym["LAB1A"]), static_cast<uint16_t>(sym["CMD_TAB"]));

    struct Want {
        std::string word;
        std::vector<uint8_t> bytes;
    };
    std::vector<Want> wants;
    for (size_t i = 0; i < primary.size(); ++i) {
        std::vector<uint8_t> b;
        // The crunch routine stores the apostrophe as ":<REM token>" and ELSE
        // as ":<ELSE token>" (both act as statement separators).
        if (primary[i] == "'" || primary[i] == "ELSE") b = {':', static_cast<uint8_t>(0x80 + i)};
        else b = {static_cast<uint8_t>(0x80 + i)};
        wants.push_back({primary[i], b});
    }
    for (size_t j = 0; j < secondary.size(); ++j) wants.push_back({secondary[j], {0xFF, static_cast<uint8_t>(0x80 + j)}});

    Basic309Session s;
    CHECK(s.boot(PUGBIOS_S19_PATH, EXBASROM309_S19_PATH));
    if (!s.ends_with_ok()) return;
    s.exec("NEW");
    for (size_t k = 0; k < wants.size(); ++k) s.exec(std::to_string((k + 1) * 10) + " " + wants[k].word);

    // Walk the stored program: [link:2][line#:2][crunched bytes...][0]
    const uint8_t* ram = s.bus.ram();
    uint32_t p = be16(ram, sym["TXTTAB"]);
    size_t k = 0;
    while (k < wants.size()) {
        uint16_t link = be16(ram, p);
        CHECK(link != 0);
        if (link == 0) break;
        std::vector<uint8_t> got;
        for (uint32_t q = p + 4; ram[q] != 0; ++q) got.push_back(ram[q]);
        bool ok = got == wants[k].bytes;
        if (!ok) {
            std::string g, w;
            char buf[8];
            for (uint8_t b : got) {
                std::snprintf(buf, sizeof buf, "%02X ", b);
                g += buf;
            }
            for (uint8_t b : wants[k].bytes) {
                std::snprintf(buf, sizeof buf, "%02X ", b);
                w += buf;
            }
            std::fprintf(stderr, "  keyword '%s' crunched to [ %s] but dictionary says [ %s]\n",
                         wants[k].word.c_str(), g.c_str(), w.c_str());
        }
        CHECK(ok);
        p = link;
        ++k;
    }
    CHECK(k == wants.size());

    // And uncrunching: LIST must show each keyword spelled as typed.
    std::string listing = s.run_line("LIST");
    for (size_t i = 0; i < wants.size(); ++i) {
        if (wants[i].word == "'") continue; // LIST renders ":'" specially; covered by the byte check above
        std::string line = std::to_string((i + 1) * 10) + " " + wants[i].word + "\r\n";
        bool found = listing.find(line) != std::string::npos;
        if (!found) std::fprintf(stderr, "  LIST is missing line '%s'\n", line.substr(0, line.size() - 2).c_str());
        CHECK(found);
    }
}
