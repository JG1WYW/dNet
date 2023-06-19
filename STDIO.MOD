
IMPLEMENTATION MODULE Stdio;

FROM SYSTEM IMPORT BYTE;
FROM Streams IMPORT STREAM, EOS, WriteChar, ReadChar;
FROM Uty IMPORT CtoA, LtoA, AtoC, AtoL;
FROM Type IMPORT LINEBUF;
FROM Manager IMPORT PORTS, CHANS, Ports, Chans;
FROM MCD IMPORT XoffSent, Xoff, Xon;

VAR
  xoffSent: ARRAY [ 1..PORTS ] OF BOOLEAN;

PROCEDURE XoffAll;
VAR
  i: BYTE;
BEGIN
  FOR i := 1 TO Ports DO
    xoffSent[ i ] := XoffSent( i );
    IF NOT xoffSent[ i ] THEN
      Xoff( i );
    END;
  END;
END XoffAll;

PROCEDURE XonAll;
VAR
  i: BYTE;
BEGIN
  FOR i := 1 TO Ports DO
    IF NOT xoffSent[ i ] THEN
      Xon( i );
    END;
  END;
END XonAll;

PROCEDURE WriteLnStream( fp: STREAM );
BEGIN
  WriteChar( fp, 0dx );
  WriteChar( fp, 0ax );
END WriteLnStream;

PROCEDURE WriteStringStream( fp: STREAM; s: ARRAY OF CHAR );
VAR
  c: CARDINAL;
BEGIN
  c := 0;
  WHILE c <= HIGH( s ) DO
    IF s[ c ] = 0x THEN
      RETURN;
    END;
    IF s[ c ] <> 0ax THEN
      WriteChar( fp, s[ c ] );
      IF 0dx = s[ c ] THEN
        WriteChar( fp, 0ax );
      END;
    END;
    INC( c );
  END;
END WriteStringStream;

PROCEDURE ReadStringStream( fp: STREAM; VAR s: ARRAY OF CHAR );
VAR
  c: CARDINAL;
BEGIN
  c := 0;
  WHILE ( NOT EOS( fp ) ) AND ( c <= HIGH( s ) ) DO
    ReadChar( fp, s[ c ] );
    IF s[ c ] = 0dx THEN
      ReadChar( fp, s[ c ] );
      s[ c ] := 0x;
      RETURN;
    END;
    IF ( s[ c ] = 0x ) OR ( s[ c ] = ' ' ) OR ( s[ c ] = 09x ) THEN
      s[ c ] := 0x;
      RETURN;
    END;
    IF s[ c ] <> 0ax THEN
      INC( c );
    END;
  END;
  s[ c ] := 0x;
END ReadStringStream;

PROCEDURE ReadCardStream( fp: STREAM; VAR c: CARDINAL );
VAR
  res: CARDINAL;
  buf: LINEBUF;
BEGIN
  ReadStringStream( fp, buf );
  res := AtoC( buf, 0, c );
END ReadCardStream;

PROCEDURE WriteCardStream( fp: STREAM; c, p: CARDINAL; b: BOOLEAN );
VAR
  buf: LINEBUF;
BEGIN
  CtoA(c,buf,p,b);
  WriteStringStream( fp, buf );
END WriteCardStream;

PROCEDURE ReadLongStream( fp: STREAM; VAR c: LONGCARD );
VAR
  res: CARDINAL;
  buf: LINEBUF;
BEGIN
  ReadStringStream( fp, buf );
  res := AtoL( buf, 0, c );
END ReadLongStream;

PROCEDURE WriteLongStream( fp: STREAM; c: LONGCARD; p: CARDINAL; b: BOOLEAN );
VAR
  res:CARDINAL;
  buf:LINEBUF;
BEGIN
  LtoA( c, buf, p, b );
  WriteStringStream( fp, buf );
END WriteLongStream;

PROCEDURE GetStreamLine( fp: STREAM; VAR s: ARRAY OF CHAR );
VAR
  c: CARDINAL;
BEGIN
  c := 0;
  WHILE ( NOT EOS( fp ) ) AND ( c <= HIGH( s ) ) DO
    ReadChar( fp, s[ c ] );
    IF s[ c ] = 0dx THEN
      ReadChar( fp, s[ c ] );
      s[ c ] := 0x;
      RETURN;
    END;
    IF s[ c ] = 0x THEN
      RETURN;
    END;
    IF s[c] <> 0ax THEN
      INC( c );
    END;
  END;
  s[ c ] := 0x;
END GetStreamLine;

END Stdio.
