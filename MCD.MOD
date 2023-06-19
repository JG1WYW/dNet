(* mcd v.0.8 direct c call
 *
 * 注意: 処理系に依存する!!
 *
 * FTL 固有の命令 (Logitech も?)
 * ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
 *   GETREG( 0, i ) == mov "i" ax
 *   CODE( 058h ) == "pop ax"
 *)

IMPLEMENTATION MODULE Mcd;

FROM SYSTEM IMPORT
  ADR, GETREG, CODE;
FROM MSDOS IMPORT
  MakePointer, SEGMENT, OFFSET, Registers, FlagList, MSDOS;

TYPE
  BufferStatus = RECORD
    sBufChars, rBufChars: CARDINAL;
    xOffRecved, xOffSent: CARDINAL;
  END;
  BNODE = POINTER TO BufferStatus;
  AxStatus = RECORD
    handle: INTEGER;
    occupy: BOOLEAN;
    setLineStat: PROCEDURE(CARDINAL,INTEGER);
    getLineStat: PROCEDURE(INTEGER);
    setBufStat: PROCEDURE(CARDINAL,INTEGER);
    getBufStat: PROCEDURE(BNODE,INTEGER);
    breakSig: PROCEDURE(INTEGER);
    getc: PROCEDURE();
    putc: PROCEDURE(INTEGER);
    getSbufFree: PROCEDURE();
    getRbufChars: PROCEDURE();
    getSbufChars: PROCEDURE();
    getRbufFree: PROCEDURE();
  END;
  LineStatus = (
    dsr, bkd, rts, d4,  d3, d2, dtr, d1,   ci, cts, cd, d9,  d8, d7, d6, d5
  );
  LineSet = SET OF LineStatus;

VAR
  axStatus: ARRAY [1..MAXDEVS] OF AxStatus;
  regs: Registers;
  bufferStatus: BufferStatus;

(* open aux device *)

PROCEDURE Axopen(s:ARRAY OF CHAR): INTEGER;
TYPE
  TABLE = ARRAY [ 0..18 ] OF CARDINAL;
  VOID = PROCEDURE();
  INT = PROCEDURE(INTEGER);
  CARDINT = PROCEDURE(CARDINAL,INTEGER);
  PTRINT = PROCEDURE(BNODE,INTEGER);
VAR
  tag: RECORD
    number: INTEGER;
    offs: POINTER TO TABLE;
    codeSeg: CARDINAL;
    tableSize: INTEGER;
  END;
  i, hdl : INTEGER;
  dev: ARRAY [0..15] OF CHAR;
BEGIN
  i := 0;
  WHILE ( i <= HIGH( dev ) ) AND ( i <= HIGH( s ) ) AND ( s[ i ] <> 0x ) DO
    dev[ i ] := s[ i ];
    INC( i );
  END;
  IF i <= HIGH( dev ) THEN
    dev[ i ] := 0x;
  ELSE
    dev[ HIGH( dev ) ] := 0x;
  END
  regs.AX := 03d02h;
  regs.DS := SEGMENT(ADR(dev));
  regs.DX := OFFSET(ADR(dev));
  MSDOS(regs);
  hdl := regs.AX;
  IF NOT ( Carry IN regs.FLAGS ) THEN
    tag.number := 21;
    regs.AX := 04402h;
    regs.BX := hdl;
    regs.CX := 10;
    regs.DS := SEGMENT(ADR(tag));
    regs.DX := OFFSET(ADR(tag));
    MSDOS(regs);
    IF NOT ( Carry IN regs.FLAGS ) THEN
      i := 1;
      WHILE ( (i<=MAXDEVS) AND axStatus[i].occupy ) DO
        INC(i);
      END;
      IF i <= MAXDEVS THEN
        WITH axStatus[i] DO
          handle := hdl;
          occupy := TRUE;
	  WITH tag DO
            setLineStat := CARDINT(MakePointer(codeSeg,offs^[2]));
            getLineStat := INT(MakePointer(codeSeg,offs^[2]));
            setBufStat := CARDINT(MakePointer(codeSeg,offs^[3]));
            getBufStat := PTRINT(MakePointer(codeSeg,offs^[3]));
            breakSig := INT(MakePointer(codeSeg,offs^[6]));
            getc := VOID(MakePointer(codeSeg,offs^[8]));
            putc := INT(MakePointer(codeSeg,offs^[9]));
            getSbufChars := VOID(MakePointer(codeSeg,offs^[10]));
            getSbufFree := VOID(MakePointer(codeSeg,offs^[11]));
            getRbufChars := VOID(MakePointer(codeSeg,offs^[12]));
            getRbufFree := VOID(MakePointer(codeSeg,offs^[13]));
	  END;
          RETURN i;
        END;
      END;
    END;
  END;
  RETURN 0;
END Axopen;

PROCEDURE Axclose(i:INTEGER);
BEGIN
  regs.AH := 03eh;
  regs.BX := axStatus[i].handle;
  MSDOS(regs);
  axStatus[i].occupy := FALSE;
END Axclose;

PROCEDURE Cts(i:INTEGER): BOOLEAN;
BEGIN
  axStatus[i].getLineStat(0);
  GETREG(0,i);			(* 返値がスタックでないので，とりあえず
				   ボイドで呼んで, ax レジスタを見る *)
  CODE(058h);	(* pop ax *)	(* つんだスタックは自分で降ろす *)
  RETURN cts IN LineSet(i);
END Cts;

PROCEDURE Dcd(i:INTEGER): BOOLEAN;
BEGIN
  axStatus[i].getLineStat(0);
  GETREG(0,i);
  CODE(058h);     (* pop ax *)
  RETURN cd IN LineSet(i);
END Dcd;

PROCEDURE DTRoff(i:INTEGER);
VAR
  j: CARDINAL;
BEGIN
  axStatus[i].getLineStat(0);
  GETREG(0,j);
  CODE(058h);     (* pop ax *)
  j := INTEGER(LineSet(j) - LineSet{dtr});
  axStatus[i].setLineStat(j,1);
  CODE(058h);     (* pop ax *)
  CODE(058h);     (* pop ax *)
END DTRoff;

PROCEDURE DTRon(i:INTEGER);
VAR
  j: CARDINAL;
BEGIN
  axStatus[i].getLineStat(0);
  GETREG(0,j);
  CODE(058h);     (* pop ax *)
  j := INTEGER(LineSet(j) + LineSet{dtr});
  axStatus[i].setLineStat(j,1);
  CODE(058h);     (* pop ax *)
  CODE(058h);     (* pop ax *)
END DTRon;

PROCEDURE XoffSent(i:INTEGER): BOOLEAN;
BEGIN
  axStatus[i].getBufStat(ADR(bufferStatus),0);
  CODE(058h);     (* pop ax *)
  CODE(058h);     (* pop ax *)
  CODE(058h);     (* pop ax *)
  RETURN bufferStatus.xOffSent <> 0;
END XoffSent;

PROCEDURE Xoff(i:INTEGER);
BEGIN
  axStatus[i].setBufStat(0100h,1);
  CODE(058h);     (* pop ax *)
  CODE(058h);     (* pop ax *)
END Xoff;

PROCEDURE Xon(i:INTEGER);
BEGIN
  axStatus[i].setBufStat(0200h,1);
  CODE(058h);     (* pop ax *)
  CODE(058h);     (* pop ax *)
END Xon;

PROCEDURE SendBreak(i:INTEGER);
BEGIN
  axStatus[i].breakSig(1);
  CODE(058h);     (* pop ax *)
END SendBreak;

PROCEDURE ReceiveBreak(i:INTEGER): BOOLEAN;
BEGIN
  axStatus[i].breakSig(0);
  GETREG(0,i);
  CODE(058h);     (* pop ax *)
  IF 0 = i THEN
    RETURN FALSE;
  ELSE
    RETURN TRUE;
  END;
END ReceiveBreak;

PROCEDURE Axin(i:INTEGER): CHAR;
BEGIN
  axStatus[i].getc();
  GETREG(0,i);
  RETURN CHR(i);
END Axin;

PROCEDURE Axout(i:INTEGER;c:CHAR);
BEGIN
  axStatus[i].putc(INTEGER(c));
(*  GETREG(0,i);*)
  CODE(058h);     (* pop ax *)
END Axout;

PROCEDURE Rest(i:INTEGER): BOOLEAN;
BEGIN
  axStatus[i].getSbufChars();
  GETREG(0,i);
  IF 0 = i THEN
    RETURN FALSE;
  ELSE
    RETURN TRUE;
  END;
END Rest;

PROCEDURE CanPut(i:INTEGER): BOOLEAN;
BEGIN
  axStatus[i].getSbufFree();
  GETREG(0,i);
  RETURN 0 <> i;
END CanPut;

PROCEDURE CanGet(i:INTEGER): BOOLEAN;
BEGIN
  axStatus[i].getRbufChars();
  GETREG(0,i);
  RETURN 0 <> i;
END CanGet;

PROCEDURE InitTable;
VAR
  i: INTEGER;
BEGIN
  FOR i := 1 TO MAXDEVS DO
    axStatus[ i ].occupy := FALSE;
  END;
END InitTable;

BEGIN
  InitTable;
END Mcd.
