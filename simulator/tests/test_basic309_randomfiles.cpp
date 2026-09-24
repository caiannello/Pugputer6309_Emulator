// BASIC-level random-access file I/O (OPEN "R" / OPEN f AS #n LEN=, FIELD, LSET/RSET,
// GET/PUT, MKI$/MKS$/CVI/CVS, and LOC/LOF/EOF on random files), driven with real
// keystrokes through the whole boot chain. The GW-BASIC User's Guide's Examples 4
// (create INFOFILE), 5 (read it back) and 6 (inventory) from section 5.3 are run --
// with the guide's `%` integer variables written as plain numeric variables, which
// basic309 doesn't have -- plus the record/field edge cases and every error.
//
// disk.img is shared and persistent: every test KILLs its files first and last.
#include <string>
#include <vector>

#include "basic309_file_helpers.hpp"
#include "test_framework.hpp"

// Guide Example 4 (create INFOFILE.DAT with PUT) and Example 5 (read it back with GET).
TEST(basic309_randomfiles_guide_examples_4_and_5) {
    Basic309Session s;
    CHECK(boot(s));
    if (!s.ends_with_ok()) return;
    kill(s, "INFOFILE.DAT");

    s.run_line("NEW");
    s.exec("10 OPEN \"R\", #1, \"INFOFILE.DAT\", 32");
    s.exec("20 FIELD#1, 20 AS N$, 4 AS A$, 8 AS P$");
    s.exec("30 INPUT \"2-DIGIT CODE\"; CODE");
    s.exec("40 INPUT \"NAME\"; X$");
    s.exec("50 INPUT \"AMOUNT\"; AMT");
    s.exec("60 INPUT \"PHONE\"; TEL$: PRINT");
    s.exec("70 LSET N$=X$");
    s.exec("80 LSET A$=MKS$(AMT)");
    s.exec("90 LSET P$=TEL$");
    s.exec("100 PUT #1, CODE");
    s.exec("110 GOTO 30");
    s.received.clear();
    s.type("RUN");
    CHECK(s.wait_for("2-DIGIT CODE? "));
    struct Rec { const char *code, *name, *amount, *phone; };
    for (const Rec& r : {Rec{"5", "ALICE", "12.5", "555-1234"}, Rec{"2", "BOB", "100", "555-9999"},
                         Rec{"7", "CAROL", "0.25", "555-0000"}}) {
        CHECK(answer(s, r.code, "NAME? "));
        CHECK(answer(s, r.name, "AMOUNT? "));
        CHECK(answer(s, r.amount, "PHONE? "));
        CHECK(answer(s, r.phone, "2-DIGIT CODE? "));
    }
    s.received.clear();
    s.send_byte(3); // Ctrl-C at the prompt ends the endless loop, as a user would
    CHECK(s.run_until_ok(40000000));
    CHECK(contains(s.received, "BREAK IN 30"));
    s.run_line("CLOSE"); // STOP left the file open

    // Example 5.
    s.run_line("NEW");
    s.exec("10 OPEN \"R\",#1,\"INFOFILE.DAT\",32");
    s.exec("20 FIELD #1, 20 AS N$, 4 AS A$, 8 AS P$");
    s.exec("30 INPUT \"2-DIGIT CODE\";CODE");
    s.exec("40 GET #1, CODE");
    s.exec("50 PRINT N$");
    s.exec("60 PRINT USING \"$$###.##\";CVS(A$)");
    s.exec("70 PRINT P$:PRINT");
    s.exec("80 GOTO 30");
    s.received.clear();
    s.type("RUN");
    CHECK(s.wait_for("2-DIGIT CODE? "));
    // N$ is a 20-character field, so it prints space-padded.
    CHECK(answer(s, "5", "2-DIGIT CODE? "));
    CHECK(expect_eq("record 5", s.received, "5\r\nALICE" + std::string(15, ' ') + "\r\n  $12.50\r\n555-1234\r\n\r\n2-DIGIT CODE? "));
    CHECK(answer(s, "2", "2-DIGIT CODE? "));
    CHECK(expect_eq("record 2", s.received, "2\r\nBOB" + std::string(17, ' ') + "\r\n $100.00\r\n555-9999\r\n\r\n2-DIGIT CODE? "));
    CHECK(answer(s, "7", "2-DIGIT CODE? "));
    CHECK(expect_eq("record 7", s.received, "7\r\nCAROL" + std::string(15, ' ') + "\r\n   $0.25\r\n555-0000\r\n\r\n2-DIGIT CODE? "));
    // A record that was never written reads as zeros / spaces-less nothing: N$ is 20 NULs.
    CHECK(answer(s, "3", "2-DIGIT CODE? "));
    CHECK(contains(s.received, std::string(20, '\0')));
    s.received.clear();
    s.send_byte(3);
    CHECK(s.run_until_ok(40000000));
    s.run_line("CLOSE");
    kill(s, "INFOFILE.DAT");
}

// FIELD / LSET / RSET / GET / PUT / LOC / LOF / EOF on a small file, one line at a time.
TEST(basic309_randomfiles_fields_records_and_positions) {
    Basic309Session s;
    CHECK(boot(s));
    if (!s.ends_with_ok()) return;
    kill(s, "R1.DAT");

    CHECK(expect_eq("open", s.run_line("OPEN \"R\",#1,\"R1.DAT\",10"), ""));
    CHECK(expect_eq("field", s.run_line("FIELD #1, 4 AS A$, 6 AS B$"), ""));
    CHECK(expect_eq("lset", s.run_line("LSET A$=\"AB\":LSET B$=\"123456789\":PRINT \"[\";A$;\"][\";B$;\"]\""),
                    "[AB  ][123456]\r\n")); // padded / truncated on the right
    CHECK(expect_eq("rset", s.run_line("RSET A$=\"AB\":RSET B$=\"XY\":PRINT \"[\";A$;\"][\";B$;\"]\""),
                    "[  AB][    XY]\r\n"));
    CHECK(expect_eq("rset truncates the left end kept", s.run_line("RSET A$=\"ABCDEF\":PRINT \"[\";A$;\"]\""),
                    "[ABCD]\r\n"));
    CHECK(expect_eq("empty", s.run_line("LSET A$=\"\":PRINT \"[\";A$;\"]\""), "[    ]\r\n"));
    CHECK(expect_eq("nothing yet", s.run_line("PRINT LOC(1);LOF(1);EOF(1)"), " 0  0  0 \r\n"));

    // PUT past the end of the file: records 1 and 2 are the gap (zeros).
    s.run_line("LSET A$=\"REC3\":LSET B$=\"THREE\":PUT #1,3");
    CHECK(expect_eq("after PUT 3", s.run_line("PRINT LOC(1);LOF(1)"), " 3  30 \r\n"));
    CHECK(expect_eq("gap", s.run_line("GET #1,1:PRINT ASC(A$);ASC(B$);LOC(1);EOF(1)"), " 0  0  1  0 \r\n"));
    CHECK(expect_eq("get 3", s.run_line("GET #1,3:PRINT A$;B$;LOC(1);EOF(1)"), "REC3THREE  3  0 \r\n"));
    // GET past the end: no error, zero record, EOF true, the record number still moves.
    CHECK(expect_eq("get 4", s.run_line("GET #1,4:PRINT ASC(A$);LOC(1);EOF(1)"), " 0  4 -1 \r\n"));
    // Without a record number, the next one -- for both GET and PUT.
    s.run_line("LSET A$=\"NEXT\":LSET B$=\"FIVE\":PUT #1");
    CHECK(expect_eq("put next", s.run_line("PRINT LOC(1);LOF(1)"), " 5  50 \r\n"));
    CHECK(expect_eq("get again", s.run_line("GET #1,5:GET #1,3:GET #1:PRINT ASC(A$);LOC(1)"), " 0  4 \r\n"));
    CHECK(expect_eq("get 5", s.run_line("GET #1,5:PRINT A$;B$"), "NEXTFIVE  \r\n"));
    CHECK(expect_eq("close", s.run_line("CLOSE"), ""));

    // The data is in the file; a re-opened random file keeps it (and the length is the
    // real one), and the fields have to be set up again.
    s.run_line("OPEN \"R\",#2,\"R1.DAT\",10");
    s.run_line("FIELD 2, 4 AS X$, 6 AS Y$");
    CHECK(expect_eq("reopen", s.run_line("GET 2,3:PRINT X$;Y$;LOF(2)"), "REC3THREE  50 \r\n"));
    // Sequential GET after an explicit one.
    CHECK(expect_eq("sequential", s.run_line("GET 2,1:GET 2:GET 2:PRINT X$;LOC(2)"), "REC3 3 \r\n"));
    // The same file can't be opened twice.
    CHECK(contains(s.run_line("OPEN \"R\",#1,\"R1.DAT\",10"), "?AO ERROR"));
    s.run_line("CLOSE");
    kill(s, "R1.DAT");
}

// The other OPEN syntax (no FOR = random access, optional LEN=), and record lengths.
TEST(basic309_randomfiles_open_syntax_and_record_lengths) {
    Basic309Session s;
    CHECK(boot(s));
    if (!s.ends_with_ok()) return;
    for (const char* n : {"R2.DAT", "R3.DAT", "R4.DAT", "R5.DAT", "R6.DAT"}) kill(s, n);

    // OPEN f AS #n [LEN=n]; default 128; 256 is the largest.
    CHECK(expect_eq("as len", s.run_line("OPEN \"R2.DAT\" AS #1 LEN=16:FIELD #1,16 AS Z$:LSET Z$=\"HELLO\":PUT #1,2:PRINT LOF(1)"),
                    " 32 \r\n"));
    CHECK(contains(s.run_line("FIELD #1,1 AS A$,16 AS B$"), "?FC ERROR")); // 17 > 16
    s.run_line("CLOSE");
    CHECK(expect_eq("default", s.run_line("OPEN \"R3.DAT\" AS 1:FIELD 1,128 AS Z$:LSET Z$=\"X\":PUT 1:PRINT LOF(1)"), " 128 \r\n"));
    CHECK(contains(s.run_line("FIELD 1,100 AS A$,29 AS B$"), "?FC ERROR")); // 129 > 128
    CHECK(contains(s.run_line("FIELD 1,129 AS A$"), "?FC ERROR"));
    s.run_line("CLOSE");
    CHECK(expect_eq("256", s.run_line("OPEN \"R\",#1,\"R4.DAT\",256:FIELD 1,255 AS A$,1 AS B$:LSET B$=\"Z\":PUT 1,3:PRINT LOF(1)"),
                    " 768 \r\n"));
    CHECK(expect_eq("big", s.run_line("GET 1,3:PRINT B$;LOC(1)"), "Z 3 \r\n"));
    s.run_line("CLOSE");
    CHECK(contains(s.run_line("OPEN \"R\",#1,\"R4.DAT\",257"), "?FC ERROR"));
    CHECK(contains(s.run_line("OPEN \"R\",#1,\"R4.DAT\",0"), "?FC ERROR"));
    CHECK(contains(s.run_line("OPEN \"R4.DAT\" AS #1 LEN=300"), "?FC ERROR"));
    // A failed OPEN leaves the number free.
    CHECK(expect_eq("still free", s.run_line("OPEN \"R\",#1,\"R4.DAT\",256:CLOSE"), ""));
    // Two files open at once have separate buffers and record numbers.
    s.run_line("OPEN \"R\",#1,\"R5.DAT\",4:OPEN \"R\",#2,\"R6.DAT\",4");
    s.run_line("FIELD 1,4 AS A$:FIELD 2,4 AS B$");
    s.run_line("FOR I=1 TO 5:LSET A$=MKI$(I):PUT 1:LSET B$=MKI$(I*10):PUT 2:NEXT");
    CHECK(expect_eq("two files", s.run_line("GET 1,3:GET 2,3:PRINT CVI(A$);CVI(B$);LOC(1);LOC(2)"), " 3  30  3  3 \r\n"));
    CHECK(expect_eq("sequential get", s.run_line("GET 1:GET 2,5:GET 2:PRINT CVI(A$);CVI(B$);LOC(1);LOC(2);EOF(2)"),
                    " 4  0  4  6 -1 \r\n"));
    s.run_line("CLOSE");
    for (const char* n : {"R2.DAT", "R3.DAT", "R4.DAT", "R5.DAT", "R6.DAT"}) kill(s, n);
}

// MKI$/CVI/MKS$/CVS.
TEST(basic309_randomfiles_convert_functions) {
    Basic309Session s;
    CHECK(boot(s));
    if (!s.ends_with_ok()) return;

    CHECK(expect_eq("cvi", s.run_line("PRINT CVI(MKI$(0));CVI(MKI$(1));CVI(MKI$(-1));CVI(MKI$(32767));CVI(MKI$(-32768));CVI(MKI$(258))"),
                    " 0  1 -1  32767 -32768  258 \r\n"));
    CHECK(expect_eq("lengths", s.run_line("PRINT LEN(MKI$(5));LEN(MKS$(5));LEN(MKS$(0))"), " 2  4  4 \r\n"));
    CHECK(expect_eq("byte order", s.run_line("PRINT ASC(MKI$(258));ASC(RIGHT$(MKI$(258),1))"), " 1  2 \r\n"));
    CHECK(expect_eq("cvs exact", s.run_line("PRINT CVS(MKS$(1.5));CVS(MKS$(-12.25));CVS(MKS$(100));CVS(MKS$(0));CVS(MKS$(255.75))"),
                    " 1.5 -12.25  100  0  255.75 \r\n"));
    CHECK(expect_eq("cvs inexact", s.run_line("PRINT USING \"#.#####\";CVS(MKS$(.1));CVS(MKS$(3.14159))"), "0.100003.14159\r\n"));
    CHECK(expect_eq("big and small", s.run_line("PRINT USING \"##.###\";CVS(MKS$(1E-30))*1E30;CVS(MKS$(-1E20))/1E20"), " 1.000-1.000\r\n"));
    // Ordinary string functions work on them, and they survive garbage collection.
    CHECK(expect_eq("string ops", s.run_line("A$=MKS$(2.5):B$=A$+A$:FOR I=1 TO 40:C$=STR$(I)+A$:NEXT:PRINT CVS(LEFT$(B$,4));CVS(RIGHT$(B$,4))"),
                    " 2.5  2.5 \r\n"));
    // Errors.
    CHECK(contains(s.run_line("PRINT CVI(\"A\")"), "?FC ERROR"));
    CHECK(contains(s.run_line("PRINT CVS(\"ABC\")"), "?FC ERROR"));
    CHECK(contains(s.run_line("PRINT CVI(5)"), "?TM ERROR"));
    CHECK(contains(s.run_line("PRINT MKI$(\"A\")"), "?TM ERROR"));
    CHECK(contains(s.run_line("PRINT MKS$(\"A\")"), "?TM ERROR"));
    CHECK(contains(s.run_line("PRINT MKI$(40000)"), "?FC ERROR"));
    CHECK(contains(s.run_line("PRINT MKI$(-32769)"), "?FC ERROR"));
    // They compose with the rest of BASIC: as a string result they can be assigned and compared.
    CHECK(expect_eq("compare", s.run_line("IF MKI$(300)=MKI$(300) THEN PRINT \"SAME\""), "SAME\r\n"));
}

// Every error a program can provoke with the random-file statements.
TEST(basic309_randomfiles_errors) {
    Basic309Session s;
    CHECK(boot(s));
    if (!s.ends_with_ok()) return;
    for (const char* n : {"RE1.DAT", "RE2.DAT"}) kill(s, n);

    CHECK(contains(s.run_line("GET #1,1"), "?NO ERROR"));       // not open
    CHECK(contains(s.run_line("PUT #2,1"), "?NO ERROR"));
    CHECK(contains(s.run_line("FIELD #3,4 AS A$"), "?NO ERROR"));
    CHECK(contains(s.run_line("GET #9,1"), "?DN ERROR"));
    CHECK(contains(s.run_line("PRINT LOC(1)"), "?NO ERROR"));

    // Random statements on a sequential file, sequential statements on a random one.
    s.run_line("OPEN \"O\",#1,\"RE1.DAT\"");
    CHECK(contains(s.run_line("GET #1,1"), "?FM ERROR"));
    CHECK(contains(s.run_line("PUT #1"), "?FM ERROR"));
    CHECK(contains(s.run_line("FIELD #1,4 AS A$"), "?FM ERROR"));
    s.run_line("CLOSE");
    s.run_line("OPEN \"R\",#1,\"RE2.DAT\",8");
    s.run_line("FIELD #1,8 AS A$");
    CHECK(contains(s.run_line("PRINT#1,\"X\""), "?FM ERROR"));
    CHECK(contains(s.run_line("WRITE#1,\"X\""), "?FM ERROR"));
    CHECK(contains(s.run_line("INPUT#1,B$"), "?FM ERROR"));
    CHECK(contains(s.run_line("LINE INPUT#1,B$"), "?FM ERROR"));
    // Record numbers.
    CHECK(contains(s.run_line("GET #1,0"), "?FC ERROR"));
    CHECK(contains(s.run_line("PUT #1,32768"), "?FC ERROR"));
    CHECK(contains(s.run_line("GET #1,-1"), "?FC ERROR"));
    // A record must lie inside 64KB: with 8-byte records, #8191 is the last one.
    CHECK(contains(s.run_line("LSET A$=\"LAST\":PUT #1,32767"), "?FC ERROR"));
    CHECK(contains(s.run_line("PUT #1,8192"), "?FC ERROR"));
    CHECK(expect_eq("last record", s.run_line("PUT #1,8191:PRINT LOF(1);LOC(1)"), " 65528  8191 \r\n"));
    // LSET/RSET/FIELD type and target rules.
    s.run_line("CLOSE");
    s.run_line("OPEN \"R\",#1,\"RE2.DAT\",8");
    s.run_line("FIELD #1,8 AS A$");
    CHECK(contains(s.run_line("LSET A=\"X\""), "?TM ERROR"));                // needs a string variable
    CHECK(contains(s.run_line("LSET A$=5"), "?TM ERROR"));
    CHECK(contains(s.run_line("FIELD #1,4 AS A"), "?TM ERROR"));
    CHECK(contains(s.run_line("FIELD #1,4 A$"), "?SN ERROR"));
    CHECK(contains(s.run_line("FIELD #1,300 AS A$"), "?FC ERROR"));
    s.run_line("C$=\"PLAIN\"");
    CHECK(contains(s.run_line("LSET C$=\"X\""), "?FC ERROR"));               // not a FIELD variable
    CHECK(expect_eq("C$ untouched", s.run_line("PRINT C$"), "PLAIN\r\n"));
    // Assigning normally to a fielded variable detaches it from the buffer (the guide's note).
    s.run_line("LSET A$=\"ABC\":A$=\"XYZ\"");
    CHECK(contains(s.run_line("LSET A$=\"Q\""), "?FC ERROR"));
    s.run_line("CLOSE");
    for (const char* n : {"RE1.DAT", "RE2.DAT"}) kill(s, n);
}

// Guide Example 6: the inventory program (menu, part records with a description, two
// 2-byte integers and a 4-byte price), driven through its own menu.
TEST(basic309_randomfiles_guide_example_6_inventory) {
    Basic309Session s;
    CHECK(boot(s));
    if (!s.ends_with_ok()) return;
    kill(s, "INVEN.DAT");

    s.run_line("NEW");
    for (const char* line : {
             "120 OPEN\"R\",#1,\"INVEN.DAT\",39",
             "125 FIELD#1,1 AS F$,30 AS D$, 2 AS Q$,2 AS R$,4 AS P$",
             "130 PRINT:PRINT \"FUNCTIONS:\":PRINT",
             "135 PRINT 1,\"INITIALIZE FILE\"",
             "140 PRINT 2,\"CREATE A NEW ENTRY\"",
             "150 PRINT 3,\"DISPLAY INVENTORY FOR ONE PART\"",
             "160 PRINT 4,\"ADD TO STOCK\"",
             "170 PRINT 5,\"SUBTRACT FROM STOCK\"",
             "180 PRINT 6,\"DISPLAY ALL ITEMS BELOW REORDER LEVEL\"",
             "220 PRINT:PRINT:INPUT\"FUNCTION\";FU",
             "225 IF (FU<1)OR(FU>6) THEN PRINT \"BAD FUNCTION\":GOTO 130",
             "230 ON FU GOSUB 900,250,390,480,560,680",
             "240 GOTO 220",
             "250 REM BUILD NEW ENTRY",
             "260 GOSUB 840",
             "270 IF ASC(F$) <> 255 THEN INPUT\"OVERWRITE\";A$: IF A$ <> \"Y\" THEN RETURN",
             "280 LSET F$=CHR$(0)",
             "290 INPUT \"DESCRIPTION\";DESC$",
             "300 LSET D$=DESC$",
             "310 INPUT \"QUANTITY IN STOCK\";Q",
             "320 LSET Q$=MKI$(Q)",
             "330 INPUT \"REORDER LEVEL\";R",
             "340 LSET R$=MKI$(R)",
             "350 INPUT \"UNIT PRICE\";P",
             "360 LSET P$=MKS$(P)",
             "370 PUT#1,PART",
             "380 RETURN",
             "390 REM DISPLAY ENTRY",
             "400 GOSUB 840",
             "410 IF ASC(F$)=255 THEN PRINT \"NULL ENTRY\":RETURN",
             "420 PRINT USING \"PART NUMBER ###\";PART",
             "430 PRINT D$",
             "440 PRINT USING \"QUANTITY ON HAND #####\";CVI(Q$)",
             "450 PRINT USING \"REORDER LEVEL #####\";CVI(R$)",
             "460 PRINT USING \"UNIT PRICE $$##.##\";CVS(P$)",
             "470 RETURN",
             "480 REM ADD TO STOCK",
             "490 GOSUB 840",
             "500 IF ASC(F$)=255 THEN PRINT \"NULL ENTRY\":RETURN",
             "510 PRINT D$:INPUT \"QUANTITY TO ADD\";A",
             "520 Q=CVI(Q$)+A",
             "530 LSET Q$=MKI$(Q)",
             "540 PUT#1,PART",
             "550 RETURN",
             "560 REM REMOVE FROM STOCK",
             "570 GOSUB 840",
             "580 IF ASC(F$)=255 THEN PRINT \"NULL ENTRY\":RETURN",
             "590 PRINT D$",
             "600 INPUT \"QUANTITY TO SUBTRACT\";S",
             "610 Q=CVI(Q$)",
             "620 IF (Q-S)<0 THEN PRINT \"ONLY\";Q;\"IN STOCK\" :GOTO 600",
             "630 Q=Q-S",
             "640 IF Q<=CVI(R$) THEN PRINT \"QUANTITY NOW\";Q;\"REORDER LEVEL\";CVI(R$)",
             "650 LSET Q$=MKI$(Q)",
             "660 PUT#1,PART",
             "670 RETURN",
             "680 REM DISPLAY ITEMS BELOW REORDER LEVEL",
             "690 FOR I=1 TO 100",
             "710 GET#1,I",
             "720 IF ASC(F$)<>255 THEN IF CVI(Q$)<CVI(R$) THEN PRINT D$;\"QUANTITY\";CVI(Q$);TAB(50);\"REORDER LEVEL\";CVI(R$)",
             "730 NEXT I",
             "740 RETURN",
             "840 INPUT \"PART NUMBER\";PART",
             "850 IF(PART < 1)OR(PART > 100) THEN PRINT \"BAD PART NUMBER\":GOTO 840 ELSE GET#1,PART:RETURN",
             "890 END",
             "900 REM INITIALIZE FILE",
             "910 INPUT \"ARE YOU SURE\";B$:IF B$ <> \"Y\" THEN RETURN",
             "920 LSET F$=CHR$(255)",
             "930 FOR I=1 TO 100",
             "940 PUT#1,I",
             "950 NEXT I",
             "960 RETURN",
         })
        s.exec(line);
    s.received.clear();
    s.type("RUN");
    CHECK(s.wait_for("FUNCTION? "));
    CHECK(contains(s.received, "INITIALIZE FILE")); // PRINT 1,"..." puts the text in the next zone
    // 1: initialize.
    CHECK(answer(s, "1", "ARE YOU SURE? "));
    CHECK(answer(s, "Y", "FUNCTION? "));
    // 2: create part 12.
    CHECK(answer(s, "2", "PART NUMBER? "));
    CHECK(answer(s, "12", "DESCRIPTION? "));
    CHECK(answer(s, "WIDGET LARGE", "QUANTITY IN STOCK? "));
    CHECK(answer(s, "40", "REORDER LEVEL? "));
    CHECK(answer(s, "25", "UNIT PRICE? "));
    CHECK(answer(s, "3.75", "FUNCTION? "));
    // 2 again: part 30, and an attempt to overwrite it is declined.
    CHECK(answer(s, "2", "PART NUMBER? "));
    CHECK(answer(s, "30", "DESCRIPTION? "));
    CHECK(answer(s, "GADGET", "QUANTITY IN STOCK? "));
    CHECK(answer(s, "8", "REORDER LEVEL? "));
    CHECK(answer(s, "10", "UNIT PRICE? "));
    CHECK(answer(s, "19.99", "FUNCTION? "));
    CHECK(answer(s, "2", "PART NUMBER? "));
    CHECK(answer(s, "30", "OVERWRITE? "));
    CHECK(answer(s, "N", "FUNCTION? "));
    // 3: display part 12; and a part that doesn't exist.
    CHECK(answer(s, "3", "PART NUMBER? "));
    CHECK(answer(s, "12", "FUNCTION? "));
    CHECK(expect_eq("display part 12", s.received,
                    "12\r\nPART NUMBER  12\r\nWIDGET LARGE" + std::string(18, ' ') + "\r\nQUANTITY ON HAND    40\r\n"
                    "REORDER LEVEL    25\r\nUNIT PRICE   $3.75\r\n\r\n\r\nFUNCTION? "));
    CHECK(answer(s, "3", "PART NUMBER? "));
    CHECK(answer(s, "13", "FUNCTION? "));
    CHECK(contains(s.received, "NULL ENTRY"));
    CHECK(answer(s, "3", "PART NUMBER? "));
    CHECK(answer(s, "101", "PART NUMBER? "));
    CHECK(contains(s.received, "BAD PART NUMBER"));
    CHECK(answer(s, "30", "FUNCTION? "));
    // 5: subtract 20 from part 12 (40 -> 20, below its reorder level of 25), 4: add 50 to part 30.
    CHECK(answer(s, "5", "PART NUMBER? "));
    CHECK(answer(s, "12", "QUANTITY TO SUBTRACT? "));
    CHECK(answer(s, "100", "QUANTITY TO SUBTRACT? "));
    CHECK(contains(s.received, "ONLY 40 IN STOCK"));
    CHECK(answer(s, "20", "FUNCTION? "));
    CHECK(contains(s.received, "QUANTITY NOW 20 REORDER LEVEL 25"));
    CHECK(answer(s, "4", "PART NUMBER? "));
    CHECK(answer(s, "30", "QUANTITY TO ADD? "));
    CHECK(answer(s, "50", "FUNCTION? "));
    // 6: everything below its reorder level: part 12 only (part 30 is now 58 against 10).
    CHECK(answer(s, "6", "FUNCTION? "));
    CHECK(expect_eq("below reorder", s.received,
                    "6\r\nWIDGET LARGE" + std::string(18, ' ') + "QUANTITY 20" + std::string(9, ' ') + "REORDER LEVEL 25 \r\n\r\n\r\nFUNCTION? "));
    s.received.clear();
    s.send_byte(3);
    CHECK(s.run_until_ok(40000000));
    s.run_line("CLOSE");
    // The file survives: part 30 was 8 + 50.
    s.run_line("NEW");
    s.exec("10 OPEN\"R\",#1,\"INVEN.DAT\",39:FIELD#1,1 AS F$,30 AS D$,2 AS Q$,2 AS R$,4 AS P$");
    s.exec("20 GET#1,30:PRINT D$;CVI(Q$);CVI(R$):PRINT USING \"##.##\";CVS(P$)");
    CHECK(expect_eq("persisted", s.run_line("RUN"), "GADGET" + std::string(24, ' ') + " 58  10 \r\n19.99\r\n"));
    kill(s, "INVEN.DAT");
}
