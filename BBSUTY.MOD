
IMPLEMENTATION MODULE BBSUTY;

FROM Type IMPORT LINEBUF;
FROM Streams IMPORT
  Direction,Connect,Disconnect,EOS,ReadChar,WriteChar,
  BufferStream,SetLongPos,GetLongPos,IOResult,StreamLength;
FROM Stdio IMPORT
  WriteStringStream, WriteLnStream,WriteCardStream,WriteLongStream,
  ReadCardStream,ReadLongStream;
FROM LM IMPORT
  BusyLine, KickLine, WaitLine, ReadStringLine,
  WriteLine,WriteStringLine,WriteLnLine,WriteCardLine;
FROM Manager IMPORT
  InfoDEV;
FROM GetDate IMPORT
  GetDateTime;
FROM Strings IMPORT
  Length;

(* デバグ終了後、削除 *)
FROM InOut IMPORT WriteString,WriteLn,WriteInt;

(*  空白の削除  *)

PROCEDURE TailCut( VAR str: ARRAY OF CHAR );
VAR
  i: INTEGER;
BEGIN
  i := INTEGER( Length( str ) ) - 1;
  WHILE (i >= 0) AND (str[i] = ' ') DO
    DEC( i );
  END;
  IF (i+1) <= HIGH(str) THEN
    str[ i+1 ] := 0x
  END
END TailCut;

PROCEDURE CheckTime(): BOOLEAN;
VAR
  t: TimeRec;
BEGIN
  GetDateTime(t);
  IF ((6 <= t.Hour) AND (t.Hour < 9)) OR  (21 <= t.Hour) THEN
    RETURN FALSE;
  ELSE
    RETURN TRUE;
  END
END CheckTime;

PROCEDURE InNumber(VAR s:ARRAY OF CHAR;p:CARDINAL):CARDINAL;
VAR
  c: CARDINAL;
BEGIN
  FOR c := p TO HIGH(s) DO
    IF s[ c ] = 0x THEN
      RETURN HIGH(s) + 1;
    END;
    IF ( s[ c ] >= '0' ) AND ( s[ c ] <= '9' ) THEN
      RETURN c;
    END;
  END;
  RETURN HIGH(s) + 1;
END InNumber;


(* コマンドの解析に使います *)

PROCEDURE Valid(VAR s:ARRAY OF CHAR;p:CARDINAL):CARDINAL;
VAR
  c: CARDINAL;
BEGIN
  FOR c := p TO HIGH(s) DO
    IF s[ c ] = 0x THEN
      RETURN HIGH(s) + 1;
    END;
    IF ( s[ c ] <> ' ' ) AND ( s[ c ] <> 09x ) THEN
      RETURN c;
    END;
  END;
  RETURN HIGH(s) + 1;
END Valid;

PROCEDURE Invalid(VAR s:ARRAY OF CHAR;p:CARDINAL):CARDINAL;
VAR
  c:CARDINAL;
BEGIN
  FOR c := p TO HIGH(s) DO
    IF ( s[ c ] = 0x ) OR ( s[ c ] = ' ' ) OR ( s[ c ] = 09x ) THEN
      RETURN c;
    END;
  END;
  RETURN HIGH(s) + 1;
END Invalid;

PROCEDURE CopyFile( id: ID; VAR s, r: ARRAY OF CHAR );
VAR
  c: CHAR;
  u: CARDINAL;
  fi, fo: STREAM;
BEGIN
  IF 0 = Connect( fi, s, input ) THEN
    BufferStream(fi,1024);
    IF 0 = Connect( fo, r, output ) THEN
      BufferStream(fo,1024);
      u := 0;
      WHILE NOT EOS( fi ) DO
        ReadChar( fi, c );
        WriteChar( fo, c );
        INC( u );
        IF u = 1024 THEN
          WaitLine( id );
          u := 0;
        END
      END;
      Disconnect( fo, TRUE );
    END;
    Disconnect( fi, TRUE );
  END;
END CopyFile;

PROCEDURE SetFp(fp:STREAM; pos:LONGCARD):BOOLEAN;
BEGIN
  SetLongPos(fp,pos);
  IF IOResult = 0 THEN
    RETURN TRUE;
  ELSE
    RETURN FALSE;
  END;
END SetFp;

PROCEDURE GoEOS(fp:STREAM);
VAR
  c:CHAR;
  l:LONGCARD;
BEGIN
  l := StreamLength(fp);
  IF l > 0 THEN
    DEC(l);
    SetLongPos(fp,l);
    ReadChar(fp,c);
    IF c = 01ax THEN
      SetLongPos(fp,l);
    END;
  END;
END GoEOS;

PROCEDURE Exist(VAR s:ARRAY OF CHAR):BOOLEAN;
VAR
  fp:STREAM;
BEGIN
  IF 0<>Connect(fp,s,input) THEN
    RETURN FALSE;
  ELSE
    Disconnect(fp,TRUE);
    RETURN TRUE;
  END;
END Exist;


PROCEDURE Cannotopen(id:ID; s:ARRAY OF CHAR);
BEGIN
  WriteStringLine(id,'error: Cannot open [');
  WriteStringLine(id,s);
  WriteLine(id,']');
  WriteLnLine(id);
  KickLine(id);
END Cannotopen;


PROCEDURE WriteTimeStream(fp:STREAM;t:TimeRec;b:BOOLEAN);
BEGIN
  WriteCardStream(fp,t.Year,2,TRUE);
  WriteChar(fp,'-');
  WriteCardStream(fp,t.Month,2,TRUE);
  WriteChar(fp,'-');
  WriteCardStream(fp,t.Day,2,TRUE);
  IF b=TRUE THEN
    WriteChar(fp,' ');
    WriteCardStream(fp,t.Hour,2,TRUE);
    WriteChar(fp,':');
    WriteCardStream(fp,t.Minute,2,TRUE);
  END;
END WriteTimeStream;

PROCEDURE WriteTimeLine(id:ID;t:TimeRec);
BEGIN
  WriteCardLine(id,t.Year,4,TRUE);
  WriteLine(id,'-');
  WriteCardLine(id,t.Month,2,TRUE);
  WriteLine(id,'-');
  WriteCardLine(id,t.Day,2,TRUE);
  WriteLine(id,' ');
  WriteCardLine(id,t.Hour,2,TRUE);
  WriteLine(id,':');
  WriteCardLine(id,t.Minute,2,TRUE);
END WriteTimeLine;

PROCEDURE PutFileLine(id:ID; VAR s:ARRAY OF CHAR; p:CARDINAL): BOOLEAN;
VAR
  c:CHAR;
  fp:STREAM;
  buf:LINEBUF;
BEGIN
  IF 0 <> Connect(fp,s,input) THEN
    Cannotopen(id,s);
    RETURN FALSE;
  END;
  IF NOT SetFp(fp,LONG(p)) THEN
    RETURN FALSE
  END;
  BufferStream(fp,1024);
  WHILE InfoDEV[id.pid][id.cid]^.link AND (NOT EOS(fp)) DO
    ReadChar(fp,c);
    WriteLine(id,c);
    IF BusyLine(id) THEN
      ReadStringLine( id, buf );
      IF buf = '..' THEN
        Disconnect(fp,TRUE);
        RETURN FALSE;
      END
    END
  END;
  Disconnect(fp,TRUE);
  RETURN TRUE;
END PutFileLine;

PROCEDURE Numeric(c:CHAR):BOOLEAN;
BEGIN
  IF (c>='0') AND (c<='9') THEN
    RETURN TRUE;
  ELSE
    RETURN FALSE;
  END;
END Numeric;

PROCEDURE Alphabetic(c:CHAR):BOOLEAN;
BEGIN
  IF ((c>='a') AND (c<='z')) OR ((c>='A') AND (c<='Z')) THEN
    RETURN TRUE;
  ELSE
    RETURN FALSE;
  END;
END Alphabetic;

(* コールサインのチェックをしますが、これは適当にコーディングしています *)

PROCEDURE IsCall(VAR s:ARRAY OF CHAR):BOOLEAN;
VAR
  i: CARDINAL;
  FlgAlphabet, FlgNumber: BOOLEAN;
BEGIN
  IF ( s = 'ROOT' ) OR ( s = 'GUEST' ) THEN
    RETURN TRUE
  END;
  FlgAlphabet := FALSE;
  FlgNumber := FALSE;
  i := 0;
  WHILE ( i <= HIGH(s) ) AND (s[i] <> ' ') AND (s[i] <> 09x) AND (s[i] <> 0x) DO
    IF Alphabetic( s[ i ] ) THEN
      FlgAlphabet := TRUE;
    ELSIF Numeric( s[ i ] ) THEN
      FlgNumber := TRUE;
    END;
    INC( i );
  END;
  IF FlgAlphabet AND FlgNumber THEN
    RETURN TRUE;
  ELSE
    RETURN FALSE;
  END;
END IsCall;

PROCEDURE IsAlphabetic(VAR s:ARRAY OF CHAR):BOOLEAN;
VAR
  i: CARDINAL;
  FlgAlphabet: BOOLEAN;
BEGIN
  FlgAlphabet := FALSE;
  i := 0;
  WHILE ( i <= HIGH(s) ) AND (s[i] <> ' ') AND (s[i] <> 09x) AND (s[i] <> 0x) DO
    IF Alphabetic( s[ i ] ) THEN
      FlgAlphabet := TRUE;
    ELSIF NOT Numeric( s[ i ] ) THEN
      RETURN FALSE;
    END;
    INC( i );
  END;
  IF FlgAlphabet THEN
    RETURN TRUE;
  ELSE
    RETURN FALSE;
  END;
END IsAlphabetic;

(* インデックス s を作成し、b,e をセット *)

PROCEDURE MakeIndex(VAR s:ARRAY OF CHAR; b, e: CARDINAL);
VAR
  fp: STREAM;
BEGIN
  IF 0 <> Connect(fp,s,output) THEN
    RETURN;
  END;
  WriteCardStream(fp,b,4,TRUE);
  WriteChar(fp,09x);
  WriteCardStream(fp,e,4,TRUE);
  WriteLnStream(fp);
  Disconnect(fp,TRUE);
END MakeIndex;

(* ファイル名 s のインデックスを取得して b,e に返す *)

PROCEDURE GetIndex(VAR s: ARRAY OF CHAR; VAR b,e: CARDINAL);
VAR
  fp: STREAM;
BEGIN
  IF 0 <> Connect(fp,s,input) THEN
    b := 0;
    e := 0;
    IF 0 <> Connect(fp,s,output) THEN
      RETURN;
    END;
    WriteCardStream(fp,b,4,TRUE);
    WriteChar(fp,09x);
    WriteCardStream(fp,e,4,TRUE);
    WriteLnStream(fp);
    Disconnect(fp,TRUE);
  ELSE
    ReadCardStream(fp,b);
    ReadCardStream(fp,e);
    Disconnect(fp,TRUE);
  END;
END GetIndex;

(* インデックス s の第二パラメタをインクリメントして b,e に返す *)

PROCEDURE IncIndex(VAR s:ARRAY OF CHAR;VAR b:CARDINAL;VAR e:CARDINAL);
VAR
  fp: STREAM;
BEGIN
  GetIndex(s,b,e);
  IF b = 0 THEN
    b := 1;
  END;
  INC(e);
  IF e > 9999 THEN
    e := 1;
  END;
  IF 0 <> Connect(fp,s,output) THEN
    RETURN;
  END;
  WriteCardStream(fp,b,4,TRUE);
  WriteChar(fp,09x);
  WriteCardStream(fp,e,4,TRUE);
  WriteLnStream(fp);
  Disconnect(fp,TRUE);
END IncIndex;

PROCEDURE IncIndexContinue(VAR s:ARRAY OF CHAR; VAR e:CARDINAL);
VAR
  b: CARDINAL;
  fp: STREAM;
BEGIN
  GetIndex(s,b,e);
  IF b = 0 THEN
    b := 1;
  END;
  INC(e);
  IF 0 <> Connect(fp,s,output) THEN
    RETURN;
  END;
  WriteCardStream(fp,b,5,TRUE);
  WriteChar(fp,09x);
  WriteCardStream(fp,e,5,TRUE);
  WriteLnStream(fp);
  Disconnect(fp,TRUE);
END IncIndexContinue;

(*
PROCEDURE GetLongIndex(VAR s: ARRAY OF CHAR; VAR b,e: LONGCARD);
VAR
  fp: STREAM;
BEGIN
  IF 0 <> Connect(fp,s,input) THEN
    b := 0;
    e := 0;
    IF 0 <> Connect(fp,s,output) THEN
      RETURN;
    END;
    WriteLongStream(fp,b,6,TRUE);
    WriteChar(fp,09x);
    WriteLongStream(fp,e,6,TRUE);
    WriteLnStream(fp);
    Disconnect(fp,TRUE);
  ELSE
    ReadLongStream(fp,b);
    ReadLongStream(fp,e);
    Disconnect(fp,TRUE);
  END;
END GetLongIndex;

PROCEDURE IncLongIndex(VAR s: ARRAY OF CHAR; VAR b, e: LONGCARD);
VAR
  fp: STREAM;
BEGIN
  GetLongIndex(s,b,e);
  IF b = 0 THEN
    b := 1;
  END;
  INC(e);
  IF 0 <> Connect(fp,s,output) THEN
    RETURN;
  END;
  WriteLongStream(fp,b,6,TRUE);   (* ６桁 *)
  WriteChar(fp,09x);
  WriteLongStream(fp,e,6,TRUE);
  WriteLnStream(fp);
  Disconnect(fp,TRUE);
END IncLongIndex;
*)


(*
PROCEDURE BackwardStream(VAR fp:STREAM): BOOLEAN;
VAR
  flag: BOOLEAN;
  c: CHAR;
  l: LONGCARD;
BEGIN
  GetLongPos(fp,l);
  IF l = 0 THEN
    RETURN FALSE;
  END;
  flag := FALSE;
  WHILE l > 0 DO
    DEC(l);
    SetLongPos(fp,l);
    ReadChar(fp,c);
    IF c = 0ax THEN
      IF flag THEN
        RETURN TRUE;
      ELSE
        flag := TRUE;
      END;
    END;
  END;
  IF flag THEN
    RETURN FALSE;
  ELSE
    SetLongPos(fp,0);
    RETURN TRUE;
  END;
END BackwardStream;
*)

END BBSUTY.
