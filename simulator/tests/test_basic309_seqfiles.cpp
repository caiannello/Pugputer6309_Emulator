// BASIC-level sequential file I/O (OPEN/CLOSE/PRINT#/WRITE#/INPUT#/LINE INPUT#/
// EOF/LOF/LOC), driven with real keystrokes through the whole boot chain
// (BIOS -> SD boot -> dos.asm -> BASIC.COM). The GW-BASIC User's Guide's
// sequential-file Examples 1-3 (section 5.2) are run as written -- the guide's
// ON ERROR lines aside, which basic309 doesn't have -- plus the error cases,
// the statement-boundary rules (END/NEW/RUN/CLEAR close files; an error drops
// a PRINT# redirect) and formats that need care (quotes, commas, colons,
// CR LF, >32K sizes).
//
// disk.img is shared and persistent, so every test KILLs the files it uses
// before starting and again when done. (A name typed with no extension gets
// none from OPEN, but KILL/LOAD/SAVE default to .BAS -- so these tests use
// explicit ".DAT" names, except for the guide's own "DATA"/"NAMES", killed
// as "DATA."/"NAMES.".)
#include <string>
#include <vector>

#include "basic309_file_helpers.hpp"
#include "test_framework.hpp"

// Guide Example 1 (creating DATA), Example 2 (reading it back, first without and
// then with the EOF test the guide suggests).
TEST(basic309_seqfiles_guide_examples_1_and_2) {
    Basic309Session s;
    CHECK(boot(s));
    if (!s.ends_with_ok()) return;
    kill(s, "DATA.");

    s.run_line("NEW");
    s.exec("10 OPEN \"O\",#1,\"DATA\"");
    s.exec("20 INPUT \"NAME\";N$");
    s.exec("30 IF N$=\"DONE\" THEN END");
    s.exec("40 INPUT \"DEPARTMENT\";D$");
    s.exec("50 INPUT \"DATE HIRED\";H$");
    s.exec("60 PRINT#1,N$;\",\"D$\",\";H$");
    s.exec("70 PRINT:GOTO 20");
    s.received.clear();
    s.type("RUN");
    CHECK(s.wait_for("NAME? "));
    const char* answers[][2] = {
        {"MICKEY MOUSE", "DEPARTMENT? "}, {"AUDIO/VISUAL", "DATE HIRED? "}, {"01/12/72", "NAME? "},
        {"SHERLOCK HOLMES", "DEPARTMENT? "}, {"RESEARCH", "DATE HIRED? "}, {"12/03/65", "NAME? "},
        {"EBENEEZER SCROOGE", "DEPARTMENT? "}, {"ACCOUNTING", "DATE HIRED? "}, {"04/27/78", "NAME? "},
        {"SUPER MANN", "DEPARTMENT? "}, {"MAINTENANCE", "DATE HIRED? "}, {"08/16/78", "NAME? "},
    };
    for (auto& a : answers) CHECK(answer(s, a[0], a[1]));
    s.received.clear();
    s.type("DONE");
    CHECK(s.run_until_ok(40000000)); // END closes the file (never CLOSEd by the program)

    // The file holds what PRINT# was asked to write: one comma-separated line each.
    std::string listing = dump(s, "DATA");
    CHECK(expect_eq("DATA contents", listing,
                    "[MICKEY MOUSE,AUDIO/VISUAL,01/12/72]\r\n[SHERLOCK HOLMES,RESEARCH,12/03/65]\r\n"
                    "[EBENEEZER SCROOGE,ACCOUNTING,04/27/78]\r\n[SUPER MANN,MAINTENANCE,08/16/78]\r\n"));

    // Example 2 exactly as printed: reads until INPUT hits the end -> "Input past end in 20".
    s.run_line("NEW");
    s.exec("10 OPEN \"I\",#1,\"DATA\"");
    s.exec("20 INPUT#1,N$,D$,H$");
    s.exec("30 IF RIGHT$(H$,2)=\"78\" THEN PRINT N$");
    s.exec("40 GOTO 20");
    s.exec("50 CLOSE #1");
    CHECK(expect_eq("Example 2", s.run_line("RUN"), "EBENEEZER SCROOGE\r\nSUPER MANN\r\n?IE ERROR IN 20\r\n"));
    s.run_line("CLOSE"); // the error left #1 open, as in GW-BASIC

    // ... and with the guide's fix: line 15 tests EOF, line 40 goes to 15.
    s.exec("15 IF EOF(1) THEN END");
    s.exec("40 GOTO 15");
    CHECK(expect_eq("Example 2 with EOF", s.run_line("RUN"), "EBENEEZER SCROOGE\r\nSUPER MANN\r\n"));
    kill(s, "DATA.");
}

// Guide Example 3: APPEND mode adds to an existing file, and LINE INPUT keeps
// commas.
TEST(basic309_seqfiles_guide_example_3_append) {
    Basic309Session s;
    CHECK(boot(s));
    if (!s.ends_with_ok()) return;
    kill(s, "NAMES.");

    s.run_line("NEW");
    s.exec("20 OPEN \"A\", #1, \"NAMES\"");
    s.exec("120 INPUT \"NAME\"; N$");
    s.exec("130 IF N$=\"\" THEN 200");
    s.exec("140 LINE INPUT \"ADDRESS? \"; A$");
    s.exec("150 LINE INPUT \"BIRTHDAY? \"; B$");
    s.exec("160 PRINT#1, N$");
    s.exec("170 PRINT#1, A$");
    s.exec("180 PRINT#1, B$");
    s.exec("190 PRINT: GOTO 120");
    s.exec("200 CLOSE #1");
    for (auto& entry : std::vector<std::vector<std::string>>{{"ANN", "1 MAIN ST", "JAN 1"},
                                                              {"BOB", "2 OAK, AVE", "FEB 2"}}) {
        s.received.clear();
        s.type("RUN");
        CHECK(s.wait_for("NAME? "));
        CHECK(answer(s, entry[0], "ADDRESS? "));
        CHECK(answer(s, entry[1], "BIRTHDAY? "));
        CHECK(answer(s, entry[2], "NAME? "));
        s.received.clear();
        s.type(""); // an empty NAME ends the entry loop
        CHECK(s.run_until_ok(40000000));
    }
    CHECK(expect_eq("NAMES contents", dump(s, "NAMES"),
                    "[ANN]\r\n[1 MAIN ST]\r\n[JAN 1]\r\n[BOB]\r\n[2 OAK, AVE]\r\n[FEB 2]\r\n"));
    kill(s, "NAMES.");
}

// The other OPEN syntax (OPEN "file" FOR mode AS #n), all three modes.
TEST(basic309_seqfiles_open_for_output_append_input_syntax) {
    Basic309Session s;
    CHECK(boot(s));
    if (!s.ends_with_ok()) return;
    kill(s, "T2.DAT");

    CHECK(expect_eq("write", s.run_line("OPEN \"T2.DAT\" FOR OUTPUT AS #1:PRINT#1,\"ONE\":CLOSE 1"), ""));
    CHECK(expect_eq("append", s.run_line("OPEN \"T2.DAT\" FOR APPEND AS 2:PRINT#2,\"TWO\":CLOSE #2"), ""));
    CHECK(expect_eq("read",
                    s.run_line("OPEN \"T2.DAT\" FOR INPUT AS #3:LINE INPUT#3,A$:LINE INPUT#3,B$:PRINT A$;B$:CLOSE"),
                    "ONETWO\r\n"));
    // A lower-case mode letter in the old syntax works too.
    CHECK(expect_eq("lower case mode", s.run_line("OPEN \"i\",#1,\"T2.DAT\":LINE INPUT#1,A$:PRINT A$:CLOSE"),
                    "ONE\r\n"));
    kill(s, "T2.DAT");
}

// WRITE # / INPUT # round trip: quotes keep commas and colons, numbers unpadded,
// empty strings survive.
TEST(basic309_seqfiles_write_and_input_round_trip) {
    Basic309Session s;
    CHECK(boot(s));
    if (!s.ends_with_ok()) return;
    kill(s, "T3.DAT");

    CHECK(expect_eq("write", s.run_line("OPEN \"O\",#1,\"T3.DAT\":WRITE#1,1.5,\"A,B\",-7,\"X:Y\",\"\":WRITE#1,\"Q\":CLOSE"),
                    ""));
    CHECK(expect_eq("file text", dump(s, "T3.DAT"), "[1.5,\"A,B\",-7,\"X:Y\",\"\"]\r\n[\"Q\"]\r\n"));
    CHECK(expect_eq("read back",
                    s.run_line("OPEN \"I\",#1,\"T3.DAT\":INPUT#1,A,B$,C,D$,E$:INPUT#1,F$:CLOSE:"
                               "PRINT A;\"/\";B$;\"/\";C;\"/\";D$;\"/\";E$;\"/\";F$"),
                    " 1.5 /A,B/-7 /X:Y//Q\r\n"));
    // WRITE with no # goes to the console, in the same format.
    CHECK(expect_eq("console WRITE", s.run_line("WRITE 3,\"HI\",-2.5"), "3,\"HI\",-2.5\r\n"));
    kill(s, "T3.DAT");
}

// PRINT # with commas, TAB and USING; INPUT # of unquoted fields.
TEST(basic309_seqfiles_print_formats) {
    Basic309Session s;
    CHECK(boot(s));
    if (!s.ends_with_ok()) return;
    kill(s, "T4.DAT");

    s.run_line("OPEN \"O\",#1,\"T4.DAT\"");
    s.run_line("PRINT#1,USING \"####.##,\";1.5,22.25");
    s.run_line("PRINT#1,\"A\",\"B\"");
    s.run_line("PRINT#1,\"X\";TAB(6);\"Y\"");
    s.run_line("PRINT#1");
    s.run_line("PRINT#1,\"12:30\"");
    s.run_line("CLOSE");
    // Comma = next 16-column zone, TAB(6) after one character = five spaces.
    CHECK(expect_eq("formatted file", dump(s, "T4.DAT"),
                    "[   1.50,  22.25,]\r\n[A" + std::string(15, ' ') + "B]\r\n[X" + std::string(5, ' ') +
                        "Y]\r\n[]\r\n[12:30]\r\n"));
    // INPUT # takes the USING line apart into numbers; then the whole of the next
    // line is one field (unquoted fields end at a comma or line break, not at
    // spaces), blank lines between items are skipped, and a colon is data.
    CHECK(expect_eq("input from formatted file",
                    s.run_line("OPEN \"I\",#1,\"T4.DAT\":INPUT#1,A,B:INPUT#1,A$,B$,C$:CLOSE:"
                               "PRINT A;B:PRINT A$:PRINT B$:PRINT C$"),
                    " 1.5  22.25 \r\nA" + std::string(15, ' ') + "B\r\nX" + std::string(5, ' ') + "Y\r\n12:30\r\n"));
    kill(s, "T4.DAT");
}

// EOF / LOF / LOC on a small file, and a >32K file (LOF has to be unsigned).
TEST(basic309_seqfiles_eof_lof_loc) {
    Basic309Session s;
    CHECK(boot(s));
    if (!s.ends_with_ok()) return;
    kill(s, "T5.DAT");
    kill(s, "T5B.DAT");

    s.run_line("NEW");
    s.exec("10 OPEN \"O\",#1,\"T5.DAT\"");
    s.exec("20 FOR I=1 TO 3:PRINT#1,STRING$(98,\"A\"):NEXT");
    s.exec("30 PRINT \"LOF\";LOF(1);\"LOC\";LOC(1)");
    s.exec("40 CLOSE #1");
    s.exec("50 OPEN \"I\",#1,\"T5.DAT\"");
    s.exec("60 PRINT LOF(1);LOC(1);EOF(1)");
    s.exec("70 LINE INPUT#1,A$:PRINT LEN(A$);LOC(1);EOF(1)");
    s.exec("80 LINE INPUT#1,A$:LINE INPUT#1,A$:PRINT LOC(1);EOF(1)");
    s.exec("90 CLOSE #1");
    CHECK(expect_eq("small file", s.run_line("RUN"), "LOF 300 LOC 3 \r\n 300  0  0 \r\n 98  1  0 \r\n 3 -1 \r\n"));

    // 170 lines of 198 characters + CR LF = 34000 bytes, over 32767.
    s.run_line("NEW");
    s.exec("5 CLEAR 3000"); // room for 198-character strings (the default is 200 bytes)
    s.exec("10 OPEN \"O\",#1,\"T5B.DAT\"");
    s.exec("20 FOR I=1 TO 170:PRINT#1,STRING$(198,\"X\"):NEXT");
    s.exec("30 CLOSE #1");
    s.exec("40 OPEN \"I\",#1,\"T5B.DAT\"");
    s.exec("50 PRINT \"LOF\";LOF(1);\"EOF\";EOF(1)");
    s.exec("60 FOR I=1 TO 169:LINE INPUT#1,A$:NEXT");
    s.exec("70 PRINT \"BEFORE LAST\";EOF(1);LOC(1)");
    s.exec("80 LINE INPUT#1,A$:PRINT LEN(A$);EOF(1);LOC(1)");
    s.exec("90 CLOSE #1");
    CHECK(expect_eq("34000-byte file", s.run_line("RUN", 400000000),
                    "LOF 34000 EOF 0 \r\nBEFORE LAST 0  265 \r\n 198 -1  266 \r\n"));
    kill(s, "T5.DAT");
    kill(s, "T5B.DAT");
}

// Every error a program can provoke, and that each leaves BASIC usable.
TEST(basic309_seqfiles_errors) {
    Basic309Session s;
    CHECK(boot(s));
    if (!s.ends_with_ok()) return;
    for (const char* n : {"E1.DAT", "E2.DAT", "E3.DAT", "E4.DAT"}) kill(s, n);

    CHECK(contains(s.run_line("PRINT#1,\"X\""), "?NO ERROR"));            // not open
    CHECK(contains(s.run_line("INPUT#2,A"), "?NO ERROR"));
    CHECK(contains(s.run_line("PRINT EOF(3)"), "?NO ERROR"));
    CHECK(contains(s.run_line("OPEN \"I\",#1,\"NOFILE.DAT\""), "?NE ERROR")); // missing
    CHECK(contains(s.run_line("OPEN \"O\",#9,\"E1.DAT\""), "?DN ERROR"));     // file number range
    CHECK(contains(s.run_line("OPEN \"O\",#0,\"E1.DAT\""), "?DN ERROR"));
    CHECK(contains(s.run_line("PRINT#5,\"X\""), "?DN ERROR"));
    CHECK(contains(s.run_line("OPEN \"Z\",#1,\"E1.DAT\""), "?FM ERROR"));     // bad mode letter
    CHECK(contains(s.run_line("OPEN \"E1.DAT\" FOR SIDEWAYS AS #1"), "?SN ERROR"));

    CHECK(expect_eq("open", s.run_line("OPEN \"O\",#1,\"E1.DAT\""), ""));
    CHECK(contains(s.run_line("OPEN \"O\",#1,\"E2.DAT\""), "?AO ERROR"));      // number in use
    CHECK(contains(s.run_line("OPEN \"O\",#2,\"E1.DAT\""), "?AO ERROR"));      // file in use
    CHECK(contains(s.run_line("INPUT#1,A"), "?FM ERROR"));                     // input from an output file
    CHECK(contains(s.run_line("LINE INPUT#1,A$"), "?FM ERROR"));
    CHECK(contains(s.run_line("KILL\"E1.DAT\""), "?AO ERROR"));                // can't delete an open file
    CHECK(contains(s.run_line("NAME\"E1.DAT\" AS \"E9.DAT\""), "?AO ERROR"));
    // An error in the middle of PRINT# must not leave the output redirected: the
    // message and later output go to the console, and only what was printed before
    // the error is in the file.
    std::string out = s.run_line("PRINT#1,\"A\";1/0");
    CHECK(contains(out, "?/0 ERROR"));
    CHECK(expect_eq("console after error", s.run_line("PRINT \"BACK\""), "BACK\r\n"));
    CHECK(expect_eq("close", s.run_line("CLOSE"), ""));
    CHECK(expect_eq("file after error", dump(s, "E1.DAT"), "[A]\r\n"));

    // INPUT past the end, and bad data.
    s.run_line("OPEN \"O\",#1,\"E3.DAT\":CLOSE"); // empty file
    CHECK(contains(s.run_line("OPEN \"I\",#1,\"E3.DAT\":INPUT#1,A"), "?IE ERROR"));
    CHECK(contains(s.run_line("LINE INPUT#1,A$"), "?IE ERROR"));
    CHECK(expect_eq("eof of empty file", s.run_line("PRINT EOF(1)"), "-1 \r\n"));
    s.run_line("CLOSE");
    s.run_line("OPEN \"O\",#1,\"E4.DAT\":PRINT#1,\"ABC\":CLOSE");
    CHECK(contains(s.run_line("OPEN \"I\",#1,\"E4.DAT\":INPUT#1,A"), "?FD ERROR"));
    s.run_line("CLOSE");
    // Closing what isn't open is fine; a bad number to CLOSE isn't.
    CHECK(expect_eq("close idle", s.run_line("CLOSE 3"), ""));
    CHECK(contains(s.run_line("CLOSE 7"), "?DN ERROR"));
    for (const char* n : {"E1.DAT", "E2.DAT", "E3.DAT", "E4.DAT", "E9.DAT"}) kill(s, n);
}

// Which statements close files, and which deliberately don't.
TEST(basic309_seqfiles_when_files_are_closed) {
    Basic309Session s;
    CHECK(boot(s));
    if (!s.ends_with_ok()) return;
    for (const char* n : {"H1.DAT", "H2.DAT", "H3.DAT"}) kill(s, n);

    // END (and running off the end of the program) closes -- and flushes -- files.
    s.run_line("NEW");
    s.exec("10 OPEN \"O\",#1,\"H1.DAT\"");
    s.exec("20 PRINT#1,\"HELLO\"");
    s.exec("30 END");
    CHECK(expect_eq("RUN", s.run_line("RUN"), ""));
    CHECK(expect_eq("after END", dump(s, "H1.DAT"), "[HELLO]\r\n"));
    s.run_line("NEW");
    s.exec("10 OPEN \"O\",#1,\"H1.DAT\"");
    s.exec("20 PRINT#1,\"AGAIN\"");
    CHECK(expect_eq("RUN off the end", s.run_line("RUN"), ""));
    CHECK(expect_eq("after run-off", dump(s, "H1.DAT"), "[AGAIN]\r\n"));

    // NEW, CLEAR and RUN each close everything (a fresh OPEN of the same number succeeds).
    CHECK(expect_eq("open", s.run_line("OPEN \"O\",#1,\"H2.DAT\""), ""));
    s.run_line("NEW");
    CHECK(expect_eq("after NEW", s.run_line("OPEN \"O\",#1,\"H2.DAT\""), ""));
    s.run_line("CLEAR");
    CHECK(expect_eq("after CLEAR", s.run_line("OPEN \"O\",#1,\"H2.DAT\""), ""));
    s.exec("10 PRINT 1");
    s.run_line("RUN");
    CHECK(expect_eq("after RUN", s.run_line("OPEN \"O\",#1,\"H2.DAT\""), ""));
    CHECK(expect_eq("close all", s.run_line("OPEN \"O\",#2,\"H3.DAT\":CLOSE:OPEN \"O\",#1,\"H2.DAT\":CLOSE 1,2"), ""));

    // STOP leaves files open (CONT must still work); an error does too.
    s.run_line("NEW");
    s.exec("10 OPEN \"O\",#1,\"H3.DAT\"");
    s.exec("20 STOP");
    s.exec("30 PRINT#1,\"AFTER STOP\":CLOSE #1:PRINT \"DONE\"");
    CHECK(contains(s.run_line("RUN"), "BREAK IN 20"));
    CHECK(expect_eq("CONT", s.run_line("CONT"), "DONE\r\n")); // #1 was still open across the STOP
    CHECK(expect_eq("after CONT", dump(s, "H3.DAT"), "[AFTER STOP]\r\n"));
    // ... and after a STOP the number is still taken (an error, unlike CONT, would
    // end the possibility of continuing).
    s.run_line("NEW");
    s.exec("10 OPEN \"O\",#1,\"H3.DAT\"");
    s.exec("20 STOP");
    CHECK(contains(s.run_line("RUN"), "BREAK IN 20"));
    CHECK(contains(s.run_line("OPEN \"O\",#1,\"H3.DAT\""), "?AO ERROR"));
    CHECK(expect_eq("CLOSE", s.run_line("CLOSE"), ""));
    for (const char* n : {"H1.DAT", "H2.DAT", "H3.DAT"}) kill(s, n);
}

// Several files at once, all four numbers, interleaved; a fifth is refused.
TEST(basic309_seqfiles_four_files_at_once) {
    Basic309Session s;
    CHECK(boot(s));
    if (!s.ends_with_ok()) return;
    for (const char* n : {"M1.DAT", "M2.DAT", "M3.DAT", "M4.DAT"}) kill(s, n);

    s.run_line("NEW");
    s.exec("10 FOR N=1 TO 4:OPEN \"O\",N,\"M\"+CHR$(48+N)+\".DAT\":NEXT");
    s.exec("20 FOR I=1 TO 40:FOR N=1 TO 4:PRINT#N,N*1000+I:NEXT:NEXT");
    s.exec("30 OPEN \"O\",5,\"M5.DAT\"");
    CHECK(contains(s.run_line("RUN"), "?DN ERROR IN 30"));
    s.run_line("CLOSE");
    s.run_line("NEW");
    s.exec("10 FOR N=1 TO 4:OPEN \"I\",N,\"M\"+CHR$(48+N)+\".DAT\":NEXT");
    s.exec("20 T=0:FOR I=1 TO 40:FOR N=1 TO 4:INPUT#N,V:T=T+V:NEXT:NEXT");
    s.exec("30 PRINT T;EOF(1);EOF(2);EOF(3);EOF(4)");
    // sum over N,I of (N*1000+I) = 40*1000*(1+2+3+4) + 4*(40*41/2) = 400000 + 3280
    CHECK(expect_eq("interleaved read", s.run_line("RUN"), " 403280 -1 -1 -1 -1 \r\n"));
    for (const char* n : {"M1.DAT", "M2.DAT", "M3.DAT", "M4.DAT"}) kill(s, n);
}

// Console INPUT with unparsable data must say ?REDO and ask again (it used to fall
// into the error handler with a garbage error code).
TEST(basic309_console_input_redo_on_bad_number) {
    Basic309Session s;
    CHECK(boot(s));
    if (!s.ends_with_ok()) return;
    s.run_line("NEW");
    s.exec("10 INPUT A");
    s.exec("20 PRINT \"GOT\";A");
    s.received.clear();
    s.type("RUN");
    CHECK(s.wait_for("? "));
    CHECK(answer(s, "ABC", "? "));
    CHECK(contains(s.received, "?REDO"));
    s.received.clear();
    s.type("5");
    CHECK(s.run_until_ok(40000000));
    CHECK(contains(s.received, "GOT 5"));
}
