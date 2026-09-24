// Error trapping in basic309: ON ERROR GOTO, RESUME / RESUME NEXT / RESUME n, ERR, ERL,
// ERROR n. Driven with real keystrokes. The programs that don't need files use the
// no-disk boot; the DOS-error test boots the whole disk chain.
#include <string>
#include <vector>

#include "basic309_file_helpers.hpp"
#include "test_framework.hpp"

namespace {

// Types a program (each line is one string) after NEW and runs it; returns RUN's output.
std::string run_program(Basic309Session& s, const std::vector<std::string>& lines) {
    s.run_line("NEW");
    for (const auto& l : lines) s.exec(l);
    return s.run_line("RUN");
}

bool boot_plain(Basic309Session& s) { return s.boot(PUGBIOS_S19_PATH, EXBASROM309_S19_PATH); }

} // namespace

TEST(basic309_on_error_goto_traps_an_error_and_resume_next_continues_after_it) {
    Basic309Session s;
    CHECK(boot_plain(s));
    std::string out = run_program(s, {"10 ON ERROR GOTO 100", "20 PRINT \"A\":PRINT 1/0:PRINT \"NOT PRINTED\"", "30 PRINT \"AFTER\"",
                                      "40 END", "100 PRINT \"ERR=\";ERR;\"ERL=\";ERL", "110 RESUME NEXT"});
    CHECK(contains(out, "A\r\n"));
    CHECK(contains(out, "ERR= 10 ERL= 20 \r\n")); // "/0" is message number 10
    CHECK(contains(out, "NOT PRINTED"));            // RESUME NEXT: only the failed statement is skipped, not the rest of its line
    CHECK(contains(out, "AFTER"));
    CHECK(!contains(out, "ERROR"));
}

TEST(basic309_resume_runs_the_failed_statement_again) {
    Basic309Session s;
    CHECK(boot_plain(s));
    std::string out = run_program(s, {"10 ON ERROR GOTO 100", "20 PRINT 10/D", "30 PRINT \"DONE\"", "40 END", "100 D=4:RESUME"});
    CHECK(expect_eq("retry", out, " 2.5 \r\nDONE\r\n"));
}

TEST(basic309_resume_with_a_line_number_goes_there) {
    Basic309Session s;
    CHECK(boot_plain(s));
    std::string out = run_program(s, {"10 ON ERROR GOTO 100", "20 PRINT 1/0", "30 PRINT \"SKIPPED\"", "40 PRINT \"FOUR\":END",
                                      "100 RESUME 40"});
    CHECK(expect_eq("resume n", out, "FOUR\r\n"));
    // A line that doesn't exist is the usual undefined-line error.
    out = run_program(s, {"10 ON ERROR GOTO 100", "20 PRINT 1/0", "100 RESUME 999"});
    CHECK(contains(out, "?UL ERROR"));
}

TEST(basic309_errors_in_the_handler_and_in_direct_mode_are_not_trapped) {
    Basic309Session s;
    CHECK(boot_plain(s));
    // An error while handling one stops the program with the usual message, in the handler's line.
    std::string out = run_program(s, {"10 ON ERROR GOTO 100", "20 PRINT 1/0", "100 PRINT 2/0"});
    CHECK(contains(out, "?/0 ERROR IN 100"));
    // Direct mode: never trapped, even with a handler set.
    s.run_line("ON ERROR GOTO 100");
    CHECK(contains(s.run_line("PRINT 1/0"), "?/0 ERROR"));
    // RESUME outside a handler.
    CHECK(contains(s.run_line("RESUME"), "?RW ERROR"));
    CHECK(contains(s.run_line("RESUME NEXT"), "?RW ERROR"));
    CHECK(contains(s.run_line("RESUME 10"), "?RW ERROR"));
}

TEST(basic309_on_error_goto_zero_and_run_new_clear_end_trapping) {
    Basic309Session s;
    CHECK(boot_plain(s));
    // GOTO 0 turns it off again.
    std::string out = run_program(s, {"10 ON ERROR GOTO 100", "20 ON ERROR GOTO 0", "30 PRINT 1/0", "100 PRINT \"TRAPPED\":END"});
    CHECK(contains(out, "?/0 ERROR IN 30") && !contains(out, "TRAPPED"));
    // A later program doesn't inherit a trap: RUN, NEW and CLEAR reset it.
    s.exec("10 ON ERROR GOTO 100");
    s.exec("20 END");
    s.run_line("RUN");
    out = run_program(s, {"10 PRINT 1/0", "100 PRINT \"TRAPPED\":END"});
    CHECK(contains(out, "?/0 ERROR IN 10") && !contains(out, "TRAPPED"));
    out = run_program(s, {"10 ON ERROR GOTO 100", "20 CLEAR", "30 PRINT 1/0", "100 PRINT \"TRAPPED\":END"});
    CHECK(contains(out, "?/0 ERROR IN 30") && !contains(out, "TRAPPED"));
}

TEST(basic309_a_trapped_error_deep_in_gosub_and_for_resumes_with_the_stack_intact) {
    Basic309Session s;
    CHECK(boot_plain(s));
    std::string out = run_program(s, {"10 ON ERROR GOTO 100", "20 FOR I=1 TO 3", "30 GOSUB 60", "40 NEXT I", "50 PRINT \"END\":END",
                                      "60 PRINT I;1/(I-2)", "70 RETURN", "100 PRINT \"E\";I:RESUME NEXT"});
    // I=1: -1;  I=2: error, the handler runs, RESUME NEXT skips the rest of line 60 and RETURN still
    // returns to the FOR loop; I=3: 1.
    CHECK(expect_eq("nested", out, " 1 -1 \r\n 2 E 2 \r\n 3  1 \r\nEND\r\n"));
    // The same with RESUME (retry) after the handler fixes the cause, from inside the subroutine.
    out = run_program(s, {"10 ON ERROR GOTO 100", "20 FOR I=1 TO 2", "30 GOSUB 60", "40 NEXT I", "50 END", "60 PRINT I;10/D:RETURN",
                          "100 D=5:RESUME"});
    CHECK(expect_eq("retry in gosub", out, " 1  1  2 \r\n 2  2 \r\n"));
}

TEST(basic309_err_erl_and_error_statement) {
    Basic309Session s;
    CHECK(boot_plain(s));
    // ERL is unsigned: line numbers past 32767 are fine.
    std::string out = run_program(s, {"10 ON ERROR GOTO 50000", "20 GOTO 40000", "40000 ERROR 4", "50000 PRINT ERR;ERL:END"});
    CHECK(expect_eq("erl", out, " 4  40000 \r\n"));
    // ERROR n raises error n (FC for a number past the table), trapped or not.
    CHECK(contains(s.run_line("ERROR 10"), "?/0 ERROR"));
    CHECK(contains(s.run_line("ERROR 7"), "?UL ERROR"));
    CHECK(contains(s.run_line("ERROR 200"), "?FC ERROR"));
    // ERR and ERL are readable anywhere, initially 0.
    s.run_line("NEW");
    CHECK(expect_eq("initial", s.run_line("PRINT ERR;ERL"), " 0  0 \r\n"));
    // ON ERROR needs GOTO.
    CHECK(contains(s.run_line("ON ERROR 100"), "?SN ERROR"));
    CHECK(contains(s.run_line("ON ERROR GOSUB 100"), "?SN ERROR"));
    // ON n GOTO still works.
    CHECK(expect_eq("on goto", run_program(s, {"10 ON 2 GOTO 30,40,50", "30 PRINT 3:END", "40 PRINT 4:END", "50 PRINT 5:END"}), " 4 \r\n"));
    // The new words list back properly.
    s.run_line("NEW");
    s.exec("10 ON ERROR GOTO 100:PRINT ERR;ERL:RESUME NEXT:ERROR 5:RESUME 20");
    CHECK(expect_eq("list", s.run_line("LIST"), "10 ON ERROR GOTO 100:PRINT ERR;ERL:RESUME NEXT:ERROR 5:RESUME 20\r\n"));
}

TEST(basic309_dos_errors_can_be_trapped_and_the_program_carries_on) {
    Basic309Session s;
    CHECK(boot(s));
    std::string out = run_program(s, {"10 ON ERROR GOTO 100", "20 OPEN \"I\",#1,\"NOSUCH.TXT\"", "30 PRINT \"WENT ON\":END",
                                      "100 PRINT \"ERR\";ERR:RESUME NEXT"});
    CHECK(contains(out, "ERR 26")); // "NE": file not found
    CHECK(contains(out, "WENT ON"));
    // A trapped error in the middle of PRINT# goes back to the console afterwards.
    kill(s, "TRAP.TXT");
    out = run_program(s, {"10 ON ERROR GOTO 100", "20 OPEN \"O\",#1,\"TRAP.TXT\"", "30 PRINT #1,1/0", "40 CLOSE", "50 PRINT \"CONSOLE\":END",
                          "100 PRINT \"E\";ERR:RESUME NEXT"});
    CHECK(contains(out, "E 10") && contains(out, "CONSOLE"));
    kill(s, "TRAP.TXT");
}

TEST(basic309_default_string_space_is_2000_bytes) {
    Basic309Session s;
    CHECK(boot_plain(s));
    // (A string is at most 255 characters and STRING$ makes at most 255, so use an array of 100-byte strings.)
    CHECK(expect_eq("fits", s.run_line("DIM A$(30):FOR I=1 TO 15:A$(I)=STRING$(100,\"X\"):NEXT:PRINT LEN(A$(15))"), " 100 \r\n")); // 1500 bytes
    CHECK(contains(s.run_line("FOR I=16 TO 30:A$(I)=STRING$(100,\"Y\"):NEXT"), "?OS ERROR")); // 3000 bytes don't fit in 2000
    CHECK(expect_eq("clear", s.run_line("CLEAR 5000:DIM B$(40):FOR I=1 TO 40:B$(I)=STRING$(100,\"Z\"):NEXT:PRINT LEN(B$(40))"), " 100 \r\n")); // 4000 bytes do
}

TEST(basic309_kill_and_name_try_a_name_as_typed_when_the_default_extension_finds_nothing) {
    Basic309Session s;
    CHECK(boot(s));
    for (const char* f : {"DATA", "DATA.BAS", "OLDDATA.DAT", "PROG.BAS", "X"}) kill(s, f);
    // A data file made without an extension: KILL "DATA" first looks for DATA.BAS, then DATA.
    s.run_line("OPEN \"O\",#1,\"DATA\":PRINT#1,\"HI\":CLOSE");
    CHECK(contains(s.run_line("FILES"), "DATA 4"));
    // NAME does the same for its old name (the new one still gets the default extension, so give it one).
    CHECK(expect_eq("name", s.run_line("NAME \"DATA\" AS \"OLDDATA.DAT\""), ""));
    std::string files = s.run_line("FILES");
    CHECK(contains(files, "OLDDATA.DAT 4") && !contains(files, "DATA 4\r\n"));
    CHECK(expect_eq("kill", s.run_line("KILL \"OLDDATA.DAT\""), ""));
    s.run_line("OPEN \"O\",#1,\"DATA\":PRINT#1,\"HI\":CLOSE");
    CHECK(expect_eq("kill bare", s.run_line("KILL \"DATA\""), ""));
    CHECK(!contains(s.run_line("FILES"), "DATA"));
    // A program saved with the default extension is still killed by its bare name ...
    s.run_line("NEW");
    s.exec("10 PRINT 1");
    s.run_line("SAVE \"PROG\"");
    CHECK(contains(s.run_line("FILES"), "PROG.BAS"));
    CHECK(expect_eq("kill prog", s.run_line("KILL \"PROG\""), ""));
    CHECK(!contains(s.run_line("FILES"), "PROG"));
    // ... and a name typed WITH its extension is never stripped: KILL "X.BAS" must not delete a file called X.
    s.run_line("OPEN \"O\",#1,\"X\":PRINT#1,\"HI\":CLOSE");
    CHECK(contains(s.run_line("KILL \"X.BAS\""), "?NE ERROR"));
    CHECK(contains(s.run_line("FILES"), "X 4"));
    CHECK(contains(s.run_line("KILL \"NOSUCH\""), "?NE ERROR"));
    kill(s, "X");
}
