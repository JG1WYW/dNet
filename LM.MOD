
IMPLEMENTATION MODULE LM;

FROM Processes IMPORT WAIT;
FROM MsDos IMPORT
  MSDOS, Registers;
FROM Type IMPORT LINEBUF, LSIZE;
FROM Uty IMPORT AtoC, CtoA, LtoA;
FROM Manager IMPORT Csign, InfoDEV, Ports, Chans;

PROCEDURE KickLine(id:ID);
BEGIN
  WITH InfoDEV[id.pid][id.cid]^ DO
    IF pfull OR (phptr <> ptptr) THEN
      kick := TRUE;
    END;
  END;
  WAIT( Csign[id.pid] );
END KickLine;

PROCEDURE BusyLine(id:ID): BOOLEAN;
BEGIN
  WITH InfoDEV[id.pid][id.cid]^ DO
    IF link AND ( gfull OR ( ghptr <> gtptr ) ) THEN
      RETURN TRUE;
    ELSE
      RETURN FALSE;
    END;
  END;
END BusyLine;

PROCEDURE WaitLine(id:ID);
BEGIN
  WAIT( Csign[id.pid] );
END WaitLine;

PROCEDURE Timer(id:ID; i:CARDINAL);
VAR
  j, hour, min, sec: CARDINAL;
  regs: Registers;
BEGIN
  WITH regs DO
    FOR j := 1 TO i DO
      AH := 02ch;
      MSDOS(regs);
      hour := CH;
      min := CL;
      sec := DH;
      REPEAT
        WAIT( Csign[id.pid] );
        AH := 02ch;
        MSDOS(regs);
      UNTIL (ORD(CH) <> hour) OR (ORD(CL) <> min) OR (ORD(DH) <> sec);
    END;
  END;
END Timer;

PROCEDURE UntilReachLine(id:ID; i:CARDINAL);
BEGIN
  IF ( id.pid > Ports ) OR ( id.cid > Chans[id.pid] ) THEN
    RETURN;
  END;
  WITH InfoDEV[id.pid][id.cid]^ DO
    REPEAT
      WAIT(Csign[id.pid]);
    UNTIL (NOT link) OR ((phptr = ptptr) AND (NOT pfull) AND (NOT kick));
    IF link THEN
      Timer(id,i);
    END;
  END;
END UntilReachLine;

PROCEDURE WriteLine(id:ID; c:CHAR);
BEGIN
  IF (id.pid > Ports) OR (id.cid > Chans[id.pid]) THEN
    RETURN;
  END;
  WITH InfoDEV[id.pid][id.cid]^ DO
    WHILE (kick = TRUE) OR (pfull = TRUE) DO
      WAIT(Csign[id.pid]);
    END;
    IF ( c <> 0x ) AND ( c <> 0ax ) AND ( c <> 01ax ) THEN
      put^[ ptptr ] := c;
      INC(ptptr);
      IF ptptr >= bsize THEN
        ptptr := 0;
      END;
      IF phptr = ptptr THEN
        pfull := TRUE;
      END;
    END;
  END;
END WriteLine;

PROCEDURE WriteStringLine(id:ID; s:ARRAY OF CHAR);
VAR
  c: CARDINAL;
BEGIN
  IF ( id.pid > Ports ) OR ( id.cid > Chans[id.pid] ) THEN
    RETURN;
  END;
  FOR c := 0 TO HIGH(s) DO
    IF s[c] = 0x THEN
      RETURN;
    END;
    WriteLine(id,s[c]);
  END;
END WriteStringLine;

PROCEDURE WriteLnLine(id:ID);
BEGIN
  IF ( id.pid > Ports ) OR ( id.cid > Chans[id.pid] ) THEN
    RETURN;
  END;
  WriteLine(id,0dx);
END WriteLnLine;

PROCEDURE WriteCardLine(id:ID; x:CARDINAL;p:CARDINAL;b:BOOLEAN);
VAR s:ARRAY [0..15] OF CHAR;
BEGIN
  IF (id.pid>Ports) OR (id.cid>Chans[id.pid]) THEN
    RETURN;
  END;
  CtoA(x,s,p,b);
  WriteStringLine(id,s);
END WriteCardLine;

PROCEDURE WriteLongLine(id:ID; x:LONGCARD;p:CARDINAL;b:BOOLEAN);
VAR s:ARRAY [0..15] OF CHAR;
BEGIN
  IF (id.pid>Ports) OR (id.cid>Chans[id.pid]) THEN
    RETURN;
  END;
  LtoA(x,s,p,b);
  WriteStringLine(id,s);
END WriteLongLine;

PROCEDURE ReadLine(id:ID; VAR c:CHAR);
BEGIN
  IF (id.pid>Ports) OR (id.cid>Chans[id.pid]) THEN
    RETURN;
  END;
  c := 0x;
  WITH InfoDEV[id.pid][id.cid]^ DO
    REPEAT
      IF ( ghptr <> gtptr ) OR ( gfull = TRUE ) THEN
        c := get^[ ghptr ];
        INC(ghptr);
        IF ghptr >= bsize THEN
          ghptr := 0;
        END;
        gfull := FALSE;
      ELSE
        WAIT(Csign[id.pid]);
      END;
    UNTIL (NOT link) OR (c <> 0x);
  END;
END ReadLine;

PROCEDURE ReadStringLine(id:ID; VAR s:ARRAY OF CHAR);
VAR i:INTEGER;
  c:CHAR;
BEGIN
  IF ( id.pid > Ports ) OR ( id.cid > Chans[id.pid] ) THEN
    s[0] := 0x;
    RETURN;
  END;
  i := 0;
  REPEAT
    ReadLine(id,c);
    IF c = 08x THEN
      DEC(i);
      IF i < 0 THEN
        i := 0;
      END;
    ELSE
      s[i] := c;
      IF c <> 0dx THEN
        INC(i);
      END;
    END;
  UNTIL (NOT InfoDEV[id.pid][id.cid]^.link) OR ( c = 0dx ) OR ( i >= HIGH(s) );
  s[i] := 0x;
END ReadStringLine;

PROCEDURE ReadCardLine(id:ID; VAR c:CARDINAL);
VAR
  buf:LINEBUF;
  res:CARDINAL;
BEGIN
  ReadStringLine(id,buf);
  res := AtoC(buf,0,c);
END ReadCardLine;

END LM.
