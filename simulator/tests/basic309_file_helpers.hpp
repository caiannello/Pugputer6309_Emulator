// Helpers shared by the disk-backed BASIC file tests (sequential and random).
// They drive a Basic309Session booted through the whole disk chain.
#pragma once

#include <cstdio>
#include <string>

#include "basic309_session.hpp"

inline bool boot(Basic309Session& s) { return s.boot_disk(PUGBIOS_S19_PATH, DISK_IMG_PATH); }

// KILL a file; "?NE" if it isn't there is fine.
inline void kill(Basic309Session& s, const std::string& name) { s.run_line("KILL\"" + name + "\""); }

// Replaces the program with one that prints every line of `name` in brackets.
inline std::string dump(Basic309Session& s, const std::string& name) {
    s.run_line("NEW");
    s.exec("10 OPEN \"I\",#1,\"" + name + "\"");
    s.exec("20 IF EOF(1) THEN 60");
    s.exec("30 LINE INPUT#1,A$:PRINT \"[\";A$;\"]\"");
    s.exec("40 GOTO 20");
    s.exec("60 CLOSE #1");
    return s.run_line("RUN");
}

inline bool contains(const std::string& hay, const std::string& needle) { return hay.find(needle) != std::string::npos; }

// Types one line at an INPUT prompt (which has no "OK" to wait for) and waits
// for the next thing BASIC prints.
inline bool answer(Basic309Session& s, const std::string& text, const std::string& next_prompt) {
    s.received.clear();
    s.type(text);
    return s.wait_for(next_prompt);
}

inline void report(const char* what, const std::string& got) {
    std::fprintf(stderr, "  %s: got [", what);
    for (char c : got) {
        if (c == '\r') std::fputs("\\r", stderr);
        else if (c == '\n') std::fputs("\\n", stderr);
        else std::fputc(c, stderr);
    }
    std::fputs("]\n", stderr);
}

inline bool expect_eq(const char* what, const std::string& got, const std::string& want) {
    if (got == want) return true;
    report(what, got);
    std::string w;
    for (char c : want) w += (c == '\r' ? std::string("\\r") : c == '\n' ? std::string("\\n") : std::string(1, c));
    std::fprintf(stderr, "  %s: want [%s]\n", what, w.c_str());
    return false;
}

