// Directories and paths from BASIC: MKDIR / CHDIR / RMDIR, paths in LOAD / SAVE /
// KILL / NAME / OPEN / FILES, and the errors. Driven with real keystrokes through
// the whole boot chain. (The DOS layer underneath is tested in test_dos_dirs.cpp.)
//
// disk.img is shared, so each test removes what it made first and last.
#include <string>
#include <vector>

#include "basic309_file_helpers.hpp"
#include "test_framework.hpp"

namespace {

// Removes leftovers from an earlier run: files first, then directories.
void tidy(Basic309Session& s) {
    s.run_line("CHDIR \"/\"");
    for (const char* f : {"SUB1/ZED.BAS", "SUB1/DATA.TXT", "SUB1/DEEP/X.BAS", "SUB1/Q.BAS", "SUB2/ZED.BAS", "ZED.BAS"}) kill(s, f);
    for (const char* d : {"SUB1/DEEP", "SUB1", "SUB2"}) s.run_line(std::string("RMDIR \"") + d + "\"");
}

} // namespace

TEST(basic309_dirs_make_enter_list_and_remove_directories) {
    Basic309Session s;
    CHECK(boot(s));
    if (!s.ends_with_ok()) return;
    tidy(s);

    CHECK(expect_eq("start", s.run_line("CHDIR"), "/\r\n")); // no argument: where am I
    CHECK(expect_eq("mkdir", s.run_line("MKDIR \"SUB1\""), ""));
    CHECK(contains(s.run_line("FILES"), "SUB1 <DIR>"));
    CHECK(contains(s.run_line("FILES"), "BASIC.COM 12296"));
    CHECK(expect_eq("chdir", s.run_line("CHDIR \"SUB1\""), ""));
    CHECK(expect_eq("cwd", s.run_line("CHDIR"), "/SUB1\r\n"));
    CHECK(expect_eq("empty", s.run_line("FILES"), "")); // "." and ".." aren't shown

    // A program saved here lands here, and only here.
    s.run_line("NEW");
    s.exec("10 PRINT \"IN SUB1\"");
    CHECK(expect_eq("save", s.run_line("SAVE \"ZED\""), ""));
    CHECK(expect_eq("files", s.run_line("FILES"), "ZED.BAS 19\r\n")); // the 18-character line + CR
    CHECK(expect_eq("up", s.run_line("CHDIR \"..\""), ""));
    CHECK(expect_eq("cwd", s.run_line("CHDIR"), "/\r\n"));
    CHECK(!contains(s.run_line("FILES"), "ZED.BAS"));
    CHECK(expect_eq("files sub", s.run_line("FILES \"SUB1\""), "ZED.BAS 19\r\n"));   // a directory path for FILES
    CHECK(expect_eq("files abs", s.run_line("FILES \"/SUB1/\""), "ZED.BAS 19\r\n"));

    // ... and can be loaded by path from anywhere.
    s.run_line("NEW");
    CHECK(expect_eq("load", s.run_line("LOAD \"SUB1/ZED\""), ""));
    CHECK(expect_eq("list", s.run_line("LIST"), "10 PRINT \"IN SUB1\"\r\n"));
    CHECK(expect_eq("run", s.run_line("RUN"), "IN SUB1\r\n"));

    // Data files by path too, with OPEN (which adds no extension).
    CHECK(expect_eq("open", s.run_line("OPEN \"O\",#1,\"SUB1/DATA.TXT\":PRINT#1,\"HI\":CLOSE"), ""));
    CHECK(expect_eq("read", s.run_line("OPEN \"I\",#1,\"/SUB1/DATA.TXT\":LINE INPUT#1,A$:PRINT A$:CLOSE"), "HI\r\n"));
    CHECK(expect_eq("rename", s.run_line("NAME \"SUB1/ZED\" AS \"Q\""), ""));
    CHECK(expect_eq("files sub", s.run_line("FILES \"SUB1\""), "Q.BAS 19\r\nDATA.TXT 4\r\n"));

    // Removing.
    CHECK(contains(s.run_line("RMDIR \"SUB1\""), "?DE ERROR"));      // not empty
    CHECK(expect_eq("kill", s.run_line("KILL \"SUB1/Q\""), ""));
    CHECK(expect_eq("kill data", s.run_line("KILL \"SUB1/DATA.TXT\""), ""));
    CHECK(expect_eq("rmdir", s.run_line("RMDIR \"SUB1\""), ""));
    CHECK(!contains(s.run_line("FILES"), "SUB1"));
    tidy(s);
}

TEST(basic309_dirs_nested_paths_relative_and_absolute) {
    Basic309Session s;
    CHECK(boot(s));
    if (!s.ends_with_ok()) return;
    tidy(s);

    CHECK(expect_eq("mk", s.run_line("MKDIR \"SUB1\":MKDIR \"SUB1/DEEP\""), ""));
    CHECK(expect_eq("cd", s.run_line("CHDIR \"SUB1/DEEP\":CHDIR"), "/SUB1/DEEP\r\n"));
    s.run_line("NEW");
    s.exec("10 PRINT \"DEEP\"");
    CHECK(expect_eq("save", s.run_line("SAVE \"X\""), ""));
    CHECK(expect_eq("cd ..", s.run_line("CHDIR \"../..\":CHDIR"), "/\r\n"));
    CHECK(expect_eq("cd abs", s.run_line("CHDIR \"/SUB1/DEEP/../DEEP\":CHDIR"), "/SUB1/DEEP\r\n"));
    s.run_line("NEW");
    CHECK(expect_eq("rel load", s.run_line("LOAD \"X\""), ""));
    CHECK(expect_eq("rel list", s.run_line("LIST"), "10 PRINT \"DEEP\"\r\n"));
    CHECK(expect_eq("cd root", s.run_line("CHDIR \"/\":CHDIR"), "/\r\n"));
    CHECK(contains(s.run_line("CHDIR \"SUB1\":RMDIR \"/SUB1\""), "?AO ERROR")); // it is the current directory
    CHECK(expect_eq("cd root", s.run_line("CHDIR \"/\""), ""));
    kill(s, "SUB1/DEEP/X.BAS");
    CHECK(expect_eq("rm", s.run_line("RMDIR \"SUB1/DEEP\":RMDIR \"SUB1\""), ""));
    tidy(s);
}

TEST(basic309_dirs_errors) {
    Basic309Session s;
    CHECK(boot(s));
    if (!s.ends_with_ok()) return;
    tidy(s);

    CHECK(expect_eq("mk", s.run_line("MKDIR \"SUB1\""), ""));
    CHECK(contains(s.run_line("MKDIR \"SUB1\""), "?FE ERROR"));          // exists
    CHECK(contains(s.run_line("CHDIR \"NOPE\""), "?NE ERROR"));          // missing
    CHECK(contains(s.run_line("CHDIR \"BASIC.COM\""), "?ND ERROR"));     // a file, not a directory
    CHECK(contains(s.run_line("RMDIR \"NOPE\""), "?NE ERROR"));
    CHECK(contains(s.run_line("RMDIR \"BASIC.COM\""), "?ND ERROR"));
    CHECK(contains(s.run_line("MKDIR \"NOPE/X\""), "?NE ERROR"));        // a missing parent
    CHECK(contains(s.run_line("MKDIR \"BASIC.COM/X\""), "?ND ERROR"));   // a file as a parent
    CHECK(contains(s.run_line("MKDIR \"A B\""), "?BP ERROR"));           // not a valid name
    CHECK(contains(s.run_line("MKDIR \"TOOLONGNAME\""), "?BP ERROR"));
    CHECK(contains(s.run_line("MKDIR \"A.B.C\""), "?BP ERROR"));
    CHECK(contains(s.run_line("SAVE \"TOOLONGNAME\""), "?BP ERROR"));    // (BASIC used to cut names to 8 characters)
    CHECK(contains(s.run_line("KILL \"SUB1/\""), "?IS ERROR"));          // a directory: use RMDIR
    CHECK(contains(s.run_line("OPEN \"O\",#1,\"SUB1\""), "?IS ERROR"));  // can't open a directory as a file
    CHECK(contains(s.run_line("LOAD \"SUB1/\""), "?IS ERROR"));
    std::string longpath(85, 'A');
    CHECK(contains(s.run_line("MKDIR \"" + longpath + "\""), "?BP ERROR")); // over the 79-character limit
    CHECK(contains(s.run_line("FILES \"NOPE\""), "?NE ERROR"));
    CHECK(contains(s.run_line("FILES \"BASIC.COM\""), "?ND ERROR"));
    CHECK(expect_eq("still usable", s.run_line("PRINT 1+1"), " 2 \r\n"));
    tidy(s);
}

TEST(basic309_dirs_statements_work_inside_a_running_program) {
    Basic309Session s;
    CHECK(boot(s));
    if (!s.ends_with_ok()) return;
    tidy(s);

    s.run_line("NEW");
    s.exec("10 MKDIR \"SUB2\"");
    s.exec("20 CHDIR \"SUB2\"");
    s.exec("30 OPEN \"O\",#1,\"F.TXT\":PRINT#1,\"X\":CLOSE #1");
    s.exec("40 FILES");
    s.exec("50 KILL \"F.TXT\"");
    s.exec("60 CHDIR \"..\"");
    s.exec("70 RMDIR \"SUB2\"");
    s.exec("80 PRINT \"DONE\"");
    // (Each of these used to end the program; only LOAD/SAVE still do.)
    CHECK(expect_eq("program", s.run_line("RUN"), "F.TXT 3\r\nDONE\r\n"));
    CHECK(!contains(s.run_line("FILES"), "SUB2"));
    tidy(s);
}
