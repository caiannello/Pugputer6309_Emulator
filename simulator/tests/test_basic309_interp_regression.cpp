// Interpreter regression suite for basic309: exact console output for a broad
// sweep of the interpreter's own features (expressions, string and numeric
// functions, control flow, DATA/READ, arrays, DEF FN, PRINT formatting,
// error messages, program editing, keyboard INPUT). Its job is to catch
// collateral damage when keywords/tokens/functions are added -- twice already
// an added keyword silently broke unrelated existing syntax (GOTO/STEP, then
// assignment) and no test noticed. Boots once (no disk involved) and runs
// every case against that one session, NEW-ing between programs.
#include <cstdio>
#include <string>
#include <vector>

#include "basic309_session.hpp"
#include "test_framework.hpp"

namespace {

struct Case {
    const char* name;
    std::vector<std::string> lines; // all but the last set things up; the last line's output is checked
    std::string expect;
};

std::string escape(const std::string& s) {
    std::string r;
    for (unsigned char c : s) {
        if (c == '\r') r += "\\r";
        else if (c == '\n') r += "\\n";
        else if (c < 32 || c > 126) {
            char buf[8];
            std::snprintf(buf, sizeof buf, "\\x%02X", c);
            r += buf;
        } else r += static_cast<char>(c);
    }
    return r;
}

const std::vector<Case>& cases() {
    static const std::vector<Case> kCases = {
        // --- expressions ---
        {"add_mul_precedence", {"PRINT 2+3*4"}, " 14 \r\n"},
        {"parentheses", {"PRINT (2+3)*4"}, " 20 \r\n"},
        {"division", {"PRINT 10/4"}, " 2.5 \r\n"},
        {"exponent", {"PRINT 2^10"}, " 1024 \r\n"},
        {"unary_minus", {"PRINT -5+3"}, "-2 \r\n"},
        {"subtraction_negative", {"PRINT 7-10"}, "-3 \r\n"},
        {"relational", {"PRINT 3>2;3<2;3=3;3<>3;3>=3;3<=2"}, "-1  0 -1  0 -1  0 \r\n"},
        {"logical", {"PRINT (5 AND 3);(5 OR 3);NOT 0"}, " 1  7 -1 \r\n"},
        {"string_concat_compare", {"10 A$=\"AB\":B$=A$+\"CD\":PRINT B$;LEN(B$)", "RUN"}, "ABCD 4 \r\n"},
        {"string_less_than", {"10 IF \"A\"<\"B\" THEN PRINT \"LT\"", "RUN"}, "LT\r\n"},
        // --- assignment (broke once already) ---
        {"assign_numeric_direct", {"A=5:PRINT A"}, " 5 \r\n"},
        {"assign_string_direct", {"A$=\"X\":PRINT A$"}, "X\r\n"},
        {"assign_in_program", {"10 A=5", "20 PRINT A", "RUN"}, " 5 \r\n"},
        {"assign_string_with_punctuation",
         {"10 Z$=\".,'=+:;*%&$OXB#@ \":PRINT LEN(Z$)", "RUN"}, " 17 \r\n"},
        {"mid_replacement", {"10 A$=\"ABC\":MID$(A$,2,1)=\"X\":PRINT A$", "RUN"}, "AXC\r\n"},
        // --- numeric functions ---
        {"int", {"PRINT INT(3.7);INT(-3.7)"}, " 3 -4 \r\n"},
        {"abs_sgn_sqr", {"PRINT ABS(-4);SGN(-9);SQR(16)"}, " 4 -1  4 \r\n"},
        {"transcendental", {"PRINT EXP(0);SIN(0);COS(0);ATN(0);LOG(2)"}, " 1  0  1  0  .693147181 \r\n"},
        {"rnd_range", {"10 R=RND(6):IF R>=1 AND R<=6 THEN PRINT \"Y\"", "RUN"}, "Y\r\n"},
        {"peek_poke", {"POKE 32768,65:PRINT PEEK(32768)"}, " 65 \r\n"},
        {"mem_nonzero", {"PRINT MEM<>0"}, "-1 \r\n"},
        // --- string functions ---
        {"left_right_mid", {"PRINT LEFT$(\"HELLO\",2);RIGHT$(\"HELLO\",3);MID$(\"HELLO\",2,3)"}, "HELLOELL\r\n"},
        {"len_asc_chr", {"PRINT LEN(\"ABCD\");ASC(\"A\");CHR$(66)"}, " 4  65 B\r\n"},
        {"str_val_hex", {"PRINT STR$(12);VAL(\"34\")+1;HEX$(255)"}, " 12 35 FF\r\n"},
        {"instr_string", {"PRINT INSTR(\"HELLO\",\"LL\");STRING$(3,\"*\")"}, " 3 ***\r\n"},
        {"inkey_no_key", {"PRINT INKEY$"}, "\r\n"},
        // --- control flow (GOTO/FOR-STEP/IF-THEN broke once) ---
        {"for_next", {"10 FOR I=1 TO 3:PRINT I;:NEXT I", "RUN"}, " 1  2  3 \r\n"},
        {"for_step_negative", {"10 FOR I=10 TO 4 STEP -3:PRINT I:NEXT", "RUN"}, " 10 \r\n 7 \r\n 4 \r\n"},
        {"for_nested", {"10 FOR I=1 TO 2:FOR J=1 TO 2:PRINT I*J;:NEXT J:NEXT I", "RUN"}, " 1  2  2  4 \r\n"},
        {"if_then_else", {"10 A=5:IF A>3 THEN PRINT \"BIG\" ELSE PRINT \"SMALL\"", "RUN"}, "BIG\r\n"},
        {"goto_loop", {"10 A=A+1", "20 IF A<3 THEN GOTO 10", "30 PRINT A", "RUN"}, " 3 \r\n"},
        {"gosub_return", {"10 GOSUB 100:PRINT \"B\":END", "100 PRINT \"A\":RETURN", "RUN"}, "A\r\nB\r\n"},
        {"on_goto", {"10 X=2:ON X GOTO 100,200", "100 PRINT \"ONE\":END", "200 PRINT \"TWO\":END", "RUN"},
         "TWO\r\n"},
        {"data_read", {"10 READ A,B$:PRINT A;B$", "20 DATA 5,XYZ", "RUN"}, " 5 XYZ\r\n"},
        {"restore", {"10 READ A:PRINT A:RESTORE:READ B:PRINT B", "20 DATA 7", "RUN"}, " 7 \r\n 7 \r\n"},
        {"dim_array", {"10 DIM A(3):A(2)=7:PRINT A(2)", "RUN"}, " 7 \r\n"},
        {"def_fn", {"10 DEF FNA(X)=X*2:PRINT FNA(4)", "RUN"}, " 8 \r\n"},
        {"stop_message", {"10 PRINT 1:STOP:PRINT 2", "RUN"}, " 1 \r\n\r\nBREAK IN 10\r\n"},
        // --- print formatting ---
        {"print_using", {"PRINT USING \"##.##\";3.14159"}, " 3.14\r\n"},
        {"print_tab", {"PRINT TAB(5);\"X\""}, "     X\r\n"},
        {"print_semicolon_strings", {"PRINT \"A\";\"B\""}, "AB\r\n"},
        {"print_comma_zone", {"PRINT 1,2"}, " 1               2 \r\n"},
        {"print_question_mark", {"? 1+1"}, " 2 \r\n"},
        {"apostrophe_comment", {"10 PRINT 1 'C", "RUN"}, " 1 \r\n"},
        // --- program editing ---
        {"list", {"10 PRINT \"A\"", "LIST"}, "10 PRINT \"A\"\r\n"},
        {"del_range", {"10 A", "20 B", "30 C", "DEL 20", "LIST"}, "10 A\r\n30 C\r\n"},
        {"renum", {"10 PRINT 1", "20 PRINT 2", "RENUM 100,10,10", "LIST"}, "100 PRINT 1\r\n110 PRINT 2\r\n"},
        // --- error messages ---
        {"err_div_zero", {"PRINT 1/0"}, "?/0 ERROR\r\n"},
        {"err_illegal_function", {"PRINT SQR(-1)"}, "?FC ERROR\r\n"},
        {"err_syntax", {"PRINT )"}, "?SN ERROR\r\n"},
        {"err_undefined_line", {"GOTO 999"}, "?UL ERROR\r\n"},
        {"err_return_without_gosub", {"RETURN"}, "?RG ERROR\r\n"},
        {"err_type_mismatch", {"PRINT \"A\"+1"}, "?TM ERROR\r\n"},
        {"err_in_program_line", {"10 X=1/0", "RUN"}, "?/0 ERROR IN 10\r\n"},
    };
    return kCases;
}

} // namespace

TEST(basic309_interpreter_regression_cases) {
    Basic309Session s;
    CHECK(s.boot(PUGBIOS_S19_PATH, EXBASROM309_S19_PATH));
    if (!s.ends_with_ok()) return;

    for (const Case& c : cases()) {
        s.exec("NEW");
        std::string got = s.run_program(c.lines);
        if (got != c.expect) {
            std::fprintf(stderr, "  regression case '%s'\n    expected: %s\n    actual:   %s\n", c.name,
                         escape(c.expect).c_str(), escape(got).c_str());
        }
        CHECK(got == c.expect);
    }
}

// Cases that need keystrokes typed *while* the program is running.
TEST(basic309_interpreter_regression_keyboard_input) {
    Basic309Session s;
    CHECK(s.boot(PUGBIOS_S19_PATH, EXBASROM309_S19_PATH));
    if (!s.ends_with_ok()) return;

    // INPUT with two comma-separated numeric values.
    s.exec("NEW");
    s.exec("10 INPUT A,B:PRINT A+B");
    s.received.clear();
    s.type("RUN");
    s.bus.run(300000);
    CHECK(s.received.find("? ") != std::string::npos);
    s.received.clear();
    s.type("3,4");
    CHECK(s.run_until_ok(40000000));
    CHECK(s.received.find(" 7 ") != std::string::npos);

    // INPUT with a prompt string and a string variable.
    s.exec("NEW");
    s.exec("10 INPUT \"NAME\";N$:PRINT \"HI \";N$");
    s.received.clear();
    s.type("RUN");
    s.bus.run(300000);
    CHECK(s.received.find("NAME? ") != std::string::npos);
    s.received.clear();
    s.type("BOB");
    CHECK(s.run_until_ok(40000000));
    CHECK(s.received.find("HI BOB") != std::string::npos);

    // LINE INPUT keeps commas and quotes.
    s.exec("NEW");
    s.exec("10 LINE INPUT A$:PRINT A$");
    s.received.clear();
    s.type("RUN");
    s.bus.run(300000);
    s.received.clear();
    s.type("HI, \"THERE\"");
    CHECK(s.run_until_ok(40000000));
    CHECK(s.received.find("HI, \"THERE\"") != std::string::npos);
}
