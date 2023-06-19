
IMPLEMENTATION MODULE Manager;

FROM STORAGE IMPORT
  ALLOCATE;
FROM Processes IMPORT
  Init, StartProcess, WAIT, SEND, Awaited, SIGNAL;
FROM Mcd IMPORT
  Axin, Axout, CanGet, CanPut, Rest, SendBreak, Dcd, DTRoff, DTRon;
FROM IntLogic IMPORT
  IAND, IOR;
FROM InOut IMPORT
  Write, WriteLn, WriteString, WriteCard;
FROM Terminal IMPORT
  BusyRead;

CONST
  NUL = 000x;
  SOH = 001x;
  STX = 002x;
  ETX = 003x;
  BS  = 008x;
  LF  = 00ax;
  CR  = 00dx;
  DLE = 010x;
  ETB = 017x;
  SUB = 01ax;

TYPE
  STATUS = ( begin, connect, receive, idle );
  LENGTH = RECORD
    CASE :BOOLEAN OF
      TRUE: x: CARDINAL;
    | FALSE:  l, h: BYTE;
    END;
  END;

VAR
  PID, CID: BYTE;
  echoMode: ARRAY [ 0..PORTS ] OF BOOLEAN;
  Esign: SIGNAL;
  Dsign: ARRAY [ 0..PORTS ] OF SIGNAL;

(*
PROCEDURE WriteStartUp(pid,cid: BYTE; s: ARRAY OF CHAR);
BEGIN
  WriteString('Start up [');
  WriteString(s);
  WriteString('] pid [');
  WriteInt(pid,2);
  WriteString('] cid [');
  WriteInt(cid,2);
  WriteString(']');
  WriteLn;
END WriteStartUp;
*)

PROCEDURE SetEchoMode( pid:BYTE; echo:BOOLEAN );
BEGIN
  echoMode[pid] := echo;
END SetEchoMode;

PROCEDURE GetEchoMode( pid:BYTE ): BOOLEAN;
BEGIN
  RETURN echoMode[pid];
END GetEchoMode;

PROCEDURE IsPenalty( ch: CHAR ): BOOLEAN;
BEGIN
  CASE ch OF
    NUL, SUB, LF, STX, ETX, ETB: RETURN TRUE;
  ELSE
    RETURN FALSE;
  END;
END IsPenalty;

PROCEDURE ConPut( ch: CHAR );
BEGIN
  IF ( ch <> NUL ) AND ( ch <> SUB ) AND ( ch <> LF ) THEN
    Write( ch );
    IF (ch = CR) AND echoMode[0] THEN
      Write( LF );
    END;
  END;
END ConPut;

PROCEDURE AxPut( pid: BYTE; ch: CHAR );
BEGIN
  IF ( ch <> NUL ) AND ( ch <> SUB ) AND ( ch <> LF ) THEN
    WHILE NOT( CanPut( ORD( pid ) ) ) DO
      WAIT( Dsign[ pid ] );
    END;
(*    Write( ch );    *)
    Axout( ORD( pid ), ch );
    IF (ch = CR) AND echoMode[pid] THEN
      WHILE NOT( CanPut( ORD( pid ) ) ) DO
        WAIT( Dsign[ pid ] );
      END;
      Axout( ORD( pid ), LF );
    END;
  END;
END AxPut;

PROCEDURE AxPuts( pid: BYTE; str: ARRAY OF CHAR );
VAR
  i: BYTE;
BEGIN
  FOR i := 0 TO HIGH( str ) DO
    AxPut( pid, str[ i ] );
  END;
END AxPuts;

PROCEDURE SendCon;
VAR
  i: INTEGER;
BEGIN
  WITH InfoDEV[ 0 ][ 0 ]^ DO
    IF phptr < ptptr THEN
      FOR i := phptr TO ptptr - 1 DO
        ConPut( put^[ i ] );
      END;
    ELSE
      FOR i := phptr TO bsize - 1 DO
        ConPut( put^[ i ] );
      END;
      IF ptptr > 0 THEN
        FOR i := 0 TO ptptr - 1 DO
          ConPut( put^[ i ] );
        END;
      END;
    END;
    phptr := ptptr;
  END;
END SendCon;

PROCEDURE Send( pid, cid: BYTE );
VAR
  i: INTEGER;
BEGIN
  WITH InfoDEV[ pid ][ cid ]^ DO
    IF Did[ pid ] = aea THEN
      AxPut( pid, SOH );
      i := BYTE( IOR( 020h, ORD( cid ) ) );
      AxPut( pid, CHR( i ) );
    ELSIF Did[ pid ] = tas THEN
      AxPut( pid, STX );
      AxPut( pid, CHR( ORD( cid ) + ORD( 'A' ) ) );
    END;
    IF phptr < ptptr THEN
      FOR i := phptr TO ptptr - 1 DO
        AxPut( pid, put^[ i ] );
      END;
    ELSE
      FOR i := phptr TO bsize - 1 DO
        AxPut( pid, put^[ i ] );
      END;
      IF ptptr > 0 THEN
        FOR i := 0 TO ptptr - 1 DO
          AxPut( pid, put^[ i ] );
        END;
      END;
    END;
    IF Did[ pid ] = aea THEN
      AxPut( pid, ETB );
    END;
    phptr := ptptr;
  END;
END Send;

PROCEDURE AxGet( pid: BYTE ): CHAR;
VAR
  ch: CHAR;
BEGIN
  WHILE NOT CanGet( ORD( pid ) ) DO
    WAIT( Dsign[ pid ] );
  END;
  ch := Axin( ORD( pid ) );
  IF echoMode[ pid ] THEN
    AxPut( pid, ch );
    IF ch = BS THEN
      AxPut( pid, ' ' );
      AxPut( pid, BS );
    END;
  END;
(*  WAIT(Dsign[ pid ]);  *)
  RETURN ch;
END AxGet;

PROCEDURE ConGet( VAR ch: CHAR ): BOOLEAN;
BEGIN
  BusyRead( ch );
  IF ch = NUL THEN
    RETURN FALSE
  END;
  IF echoMode[ 0 ] THEN
    ConPut( ch );
    IF ch = BS THEN
      ConPut( ' ' );
      ConPut( BS );
    END;
  END;
  RETURN TRUE;
END ConGet;

PROCEDURE WatchGetCon;
VAR
  ch: CHAR;
  pid: BYTE;
BEGIN
  pid := PID;
  InfoDEV[ pid ][ 0 ]^.active := TRUE;
  LOOP
    WITH InfoDEV[ pid ][ 0 ]^ DO
      call := "login";
      WHILE NOT ConGet( ch ) DO
        WAIT( Dsign[ pid ] );
      END;
      link := TRUE;
      LOOP
        IF NOT link THEN
          EXIT;
        END;
        WHILE ( NOT gfull ) AND ConGet( ch ) DO
          IF NOT IsPenalty( ch ) THEN
            get^[ gtptr ] := ch;
            INC( gtptr );
            IF gtptr >= bsize THEN
              gtptr := 0;
            END;
            IF ghptr = gtptr THEN
              gfull := TRUE;
            END;
          END;
        END;
        WAIT( Dsign[ pid ] );
      END;
    END;
    WAIT( Dsign[ pid ] );
  END;
END WatchGetCon;

PROCEDURE WatchGetTty;
VAR
  ch: CHAR;
  pid, i, j: BYTE;
BEGIN
  pid := PID;
  InfoDEV[ pid ][ 0 ]^.active := TRUE;
  LOOP
    WITH InfoDEV[ pid ][ 0 ]^ DO
      call := "login";
      WHILE NOT CanGet( pid ) DO
        WAIT( Dsign[ pid ] );
      END;
      ch := AxGet( pid );
      link := TRUE;
      LOOP
        IF NOT link THEN
          EXIT;
        END;
        WHILE ( NOT gfull ) AND CanGet( pid ) DO
          ch := AxGet( pid );
          IF NOT IsPenalty( ch ) THEN
            get^[ gtptr ] := ch;
            INC( gtptr );
            IF gtptr >= bsize THEN
              gtptr := 0;
            END;
            IF ghptr = gtptr THEN
              gfull := TRUE;
            END;
          END;
        END;
        WAIT(Dsign[ pid ]);
      END;
    END;
    WAIT(Dsign[ pid ]);
  END;
END WatchGetTty;

PROCEDURE SkipETB( pid: BYTE );
VAR
  ch: CHAR;
BEGIN
  LOOP
    ch := AxGet( pid );
    IF ch = ETB THEN
      RETURN;
    END;
  END;
END SkipETB;

PROCEDURE WatchGetAea;
VAR
  FlgCon, FlgSkip: BOOLEAN;
  ch: CHAR;
  pid, cid, i, j: BYTE;
  stat: STATUS;
BEGIN
  pid := PID;
  stat := idle;
  LOOP
    IF stat = idle THEN
      IF CanGet( ORD( pid ) ) THEN
        stat := begin;
      END;
    END;
    IF stat = begin THEN
      ch := AxGet( pid );
      IF ch = SOH THEN
        ch := AxGet( pid );
        IF ( ch >= 030x ) AND ( ch <= 039x ) THEN
          cid := BYTE( IAND( ORD( ch ), 0fh ) );
          IF  ( cid > Chans[ pid ] )
            OR
            ( NOT InfoDEV[pid][cid]^.link )
          THEN
            SkipETB( pid );
            stat := idle;
          ELSE
            stat := receive;
          END;
        ELSIF ( ch >= 050x ) AND ( ch <= 059x ) THEN
          cid := BYTE( IAND( ORD( ch ), 0fh ) );
          IF cid > Chans[ pid ] THEN
            SkipETB( pid );
            stat := idle;
          ELSE
            stat := connect;
          END;
        ELSE
          SkipETB( pid );
          stat := idle;
        END;
      ELSE
        SkipETB( pid );
        stat := idle;
      END;
    END;
    IF stat = connect THEN
      WITH InfoDEV[ pid ][ cid ]^ DO
        FlgSkip := TRUE;
        ch := AxGet( pid );
        IF ch = 'C' THEN
      (*    WriteString('コネクト検出');
          WriteLn;
      *)
          FlgCon := TRUE;
          FOR i := 1 TO 12 DO
            ch := AxGet( pid );
          END;
          
          i := 0;
          REPEAT
            ch := AxGet( pid );
            IF  ( ch = '-' ) OR ( ch = ' ' ) OR
              ( ch = CR ) OR ( ch = ETB)
            THEN
              IF ch = ETB THEN
                FlgSkip := FALSE;
              END;
              ch := NUL;
      (*      ELSE
              Write( ch );
      *)
            END;
            call[ i ] := ch;
            IF (ch <> NUL) AND (i >= 5 ) THEN
              call[ i + 1 ] := NUL;
              ch := NUL;
            END;
            INC( i );
          UNTIL ( ch = NUL ) OR ( i > HIGH( call ) );
        ELSE
      (*    WriteString('ディスコネ検出');
          WriteLn;
      *)
          FlgCon := FALSE;
        END;
      (*  WriteString('コール取得[');
      *)
        IF FlgSkip THEN
          SkipETB( pid );
        END;
        stat := idle;
      (*  WriteString(']');
      *)
        IF FlgCon THEN
          active := TRUE;
          link := TRUE;
        ELSE
          link := FALSE;
        END;
      END;
    END;
    IF stat = receive THEN
      WITH InfoDEV[ pid ][ cid ]^ DO
        IF gfull = FALSE THEN
          ch := AxGet( pid );
          IF ch = ETB THEN
            stat := idle;
          END;
          IF NOT IsPenalty( ch ) THEN
            get^[ gtptr ] := ch;
            INC( gtptr );
            IF gtptr >= bsize THEN
              gtptr := 0;
            END;
            IF ghptr = gtptr THEN
              gfull := TRUE;
            END;
          END;
        END;
      END;
    END;
    WAIT(Dsign[ pid ]);
  END;
END WatchGetAea;

PROCEDURE SkipEOS( pid, cid: BYTE ): BYTE;
VAR
  ch: CHAR;
BEGIN
  LOOP
    ch := AxGet( pid );
    IF ch = STX THEN
      RETURN BYTE( ORD( AxGet( pid ) ) - ORD( 'A' ) );
    END;
    IF ch = CR THEN
      RETURN cid;
    END;
  END;
END SkipEOS;

(* TNC210 用: TNC210 では, "?TOO MANY PAC..." の処理は必要ないようだ? *)

PROCEDURE WatchGetTas;
VAR
  FlgCon, FlgSkip: BOOLEAN;
  ch: CHAR;
  pid, cid: BYTE;
  i: CARDINAL;
  stat: STATUS;
  Length: LENGTH;
BEGIN
  pid := PID;
  cid := 0;
  stat := idle;
  SendBreak( pid );
  AxPut( pid, STX );
  AxPut( pid, 'A' );
  AxPut( pid, 'K' );
  AxPut( pid, CR );
  LOOP
    IF stat = idle THEN
      IF CanGet( ORD( pid ) ) THEN
        stat := begin;
      END;
    END;
    IF stat = begin THEN
      ch := AxGet( pid );
      IF ch = 0ffx THEN
        Length.h := BYTE( IAND( 0fh, ORD( AxGet( pid ) ) ) );
        Length.l := BYTE( AxGet( pid ) );
        Length.x := Length.x - 3;
    (*    WriteString( 'LEN(' );
        WriteCard( Length.x, 0 );
        WriteString( ')' );
        WriteLn;
    *)
        ch := AxGet( pid ); (* protocol id *)
        stat := receive;
      ELSIF ch = STX THEN
        cid := BYTE( ORD( AxGet( pid ) ) - ORD( 'A' ) );
        stat := idle;
      ELSIF ch = '*' THEN
        ch := AxGet( pid ); (* '*' *)
        ch := AxGet( pid ); (* '*' *)
        ch := AxGet( pid ); (* ' ' *)
        ch := AxGet( pid );
        IF ( ch = 'C' ) OR ( ch = 'D' ) THEN
          IF cid > Chans[ pid ] THEN
            cid := SkipEOS( pid, cid );
            stat := idle;
          ELSE
            stat := connect;
          END;
        ELSE
          cid := SkipEOS( pid, cid );
          stat := idle;
        END;
      ELSIF ch = '?' THEN
        WriteString( '[CAUTION]' );
        SendBreak( pid );
        AxPut( pid, 'K' );
        AxPut( pid, CR );
        cid := SkipEOS( pid, cid );
        stat := idle;
      ELSE
        stat := idle;
      END;
    END;
    IF stat = connect THEN
      WITH InfoDEV[ pid ][ cid ]^ DO
        FlgSkip := TRUE;
        ch := AxGet( pid );
        IF ch = 'O' THEN
      (*    WriteString('コネクト検出 cid=');
          WriteCard(cid,0);
      *)
          FlgCon := TRUE;
          FOR i := 1 TO 11 DO   (* "NNECTED to " *)
            ch := AxGet( pid );
          END;
      (*    WriteString(' コール取得[');
      *)
          i := 0;
          REPEAT
            ch := AxGet( pid );
            IF ( ch = '-' ) OR ( ch = ' ' ) OR ( ch = CR ) THEN
              IF ch = CR THEN
                FlgSkip := FALSE;
              END;
              ch := NUL;
      (*      ELSE
              Write( ch );
      *)
            END;
            call[ i ] := ch;
            IF ( ch <> NUL ) AND ( i >= 5 ) THEN
              call[ i + 1 ] := NUL;
              ch := NUL;
            END;
            INC( i );
          UNTIL ( ch = NUL ) OR ( i > HIGH( call ) );
    (*      WriteString( ']' );
          WriteLn;
    *)
        ELSE
    (*      WriteString( 'ディスコネ検出 cid=' );
          WriteCard( cid, 0 );
          WriteLn;
    *)
          FlgCon := FALSE;
        END;
        IF FlgSkip THEN
          cid := SkipEOS( pid, cid );
        END;
        stat := idle;
        IF FlgCon THEN
          active := TRUE;
          link := TRUE;
        ELSE
          link := FALSE;
        END;
      END;
    END;
    IF stat = receive THEN
      ch := AxGet( pid );
      IF ch = STX THEN
        cid := BYTE( ORD( AxGet( pid ) ) - ORD( 'A' ) );
        FlgSkip := FALSE;
      ELSE
        FlgSkip := TRUE;
      END;
    (*  WriteString( 'LEN(' );
      WriteCard( Length.x, 0 );
      WriteString( ') cid=' );
      WriteCard( cid, 0 );
      WriteLn;
    *)
      i := 1;
      WHILE i <= Length.x DO
        IF NOT FlgSkip THEN
          ch := AxGet( pid );
        ELSE
          FlgSkip := FALSE;
        END;
        WITH InfoDEV[ pid ][ cid ]^ DO
          WHILE gfull DO 
            WAIT( Dsign[ pid ] );
          END;
          IF NOT IsPenalty( ch ) THEN
            get^[ gtptr ] := ch;
            INC( gtptr );
            IF gtptr >= bsize THEN
              gtptr := 0;
            END;
            IF ghptr = gtptr THEN
              gfull := TRUE;
            END;
          END;
        END;
        INC( i );
(*        WAIT( Dsign[ pid ] ); *)
      END;
      stat := idle;
    END;
    WAIT( Dsign[ pid ] );
  END;
END WatchGetTas;

PROCEDURE SkipCR(pid: BYTE);
VAR
  ch: CHAR;
BEGIN
  LOOP
    ch := AxGet( pid );
    IF ch = CR THEN
      RETURN;
    END;
  END;
END SkipCR;

PROCEDURE WatchGetTnc;
VAR
  FlgSkip: BOOLEAN;
  ch: CHAR;
  pid: BYTE;
  i: CARDINAL;
BEGIN
  pid := PID;
  SendBreak( pid );
  AxPut( pid, 'K' );
  AxPut( pid, CR );
  LOOP
    WITH InfoDEV[ pid ][ 0 ]^ DO
      call := "login";
      WHILE NOT Dcd( pid ) DO
        WAIT( Dsign[ pid ] );
      END;
      REPEAT
        REPEAT
          ch := AxGet( pid )
        UNTIL ( NOT Dcd( pid ) ) OR ( ch = ' ' );
        ch := AxGet( pid );
      UNTIL ( NOT Dcd( pid ) ) OR ( ch = 'C' );
      IF Dcd( pid ) THEN
        FOR i := 1 TO 12 DO   (* "ONNECTED to ______ *)
          ch := AxGet( pid );
        END;
        
        FlgSkip := TRUE;
        i := 0;
        REPEAT
          ch := AxGet( pid );
          IF ( ch = '-' ) OR ( ch = ' ' ) OR ( ch = CR ) THEN
            IF ch = CR THEN
              FlgSkip := FALSE;
            END;
            ch := NUL;
          END;
          call[ i ] := ch;
          IF ( ch <> NUL ) AND ( i >= 5 ) THEN
            call[ i + 1 ] := NUL;
            ch := NUL;
          END;
          INC( i );
        UNTIL ( ch = NUL ) OR ( i > HIGH( call ) );
        IF FlgSkip THEN
          SkipCR( pid );
        END;
        
        link := TRUE;
        active := TRUE;
      END;
      LOOP
        IF NOT Dcd( pid ) THEN
          link := FALSE
        END;
        IF NOT link THEN
          EXIT;
        END;
        WHILE ( NOT gfull ) AND CanGet( pid ) DO
          ch := AxGet( pid );
          IF NOT IsPenalty( ch ) THEN
            get^[ gtptr ] := ch;
            INC( gtptr );
            IF gtptr >= bsize THEN
              gtptr := 0;
            END;
            IF ghptr = gtptr THEN
              gfull := TRUE;
            END;
          END;
        END;
        WAIT( Dsign[ pid ] );
      END;
      WHILE Dcd( pid ) DO
        IF CanGet( pid ) THEN
          ch := AxGet( pid );
        END;
        WAIT( Dsign[ pid ] );
      END;
    END;
  END;
END WatchGetTnc;

PROCEDURE WatchGetMnp;
VAR
  ch: CHAR;
  pid: BYTE;
BEGIN
  pid := PID;
  WITH InfoDEV[ pid ][ 0 ]^ DO
    LOOP
      call := "login";
      WHILE NOT Dcd( pid ) DO
        IF CanGet( pid ) THEN
          ch := AxGet( pid );
        END;
        WAIT( Dsign[ pid ] );
      END;
      REPEAT
        REPEAT
          ch := AxGet( pid )
        UNTIL ( NOT Dcd( pid ) ) OR ( ch = 'C' );
        ch := AxGet( pid );
      UNTIL ( NOT Dcd( pid ) ) OR ( ch = 'O' );
      REPEAT
        ch := AxGet( pid );
      UNTIL ( NOT Dcd( pid ) ) OR ( ch = CR );
      
      link := TRUE;
      active := TRUE;
      LOOP
        IF NOT Dcd( pid ) THEN
          link := FALSE
        END;
        IF NOT link THEN
          EXIT;
        END;
        WHILE ( NOT gfull ) AND CanGet( pid ) DO
          ch := AxGet( pid );
          IF NOT IsPenalty( ch ) THEN
            get^[ gtptr ] := ch;
            INC( gtptr );
            IF gtptr >= bsize THEN
              gtptr := 0;
            END;
            IF ghptr = gtptr THEN
              gfull := TRUE;
            END;
          END;
        END;
        WAIT( Dsign[ pid ] );
      END;
      WHILE Dcd( pid ) DO
        IF CanGet( pid ) THEN
          ch := AxGet( pid );
        END;
        WAIT( Dsign[ pid ] );
      END;
      active := FALSE;
    END;
  END;
END WatchGetMnp;

PROCEDURE WatchGet;
BEGIN
  IF Did[ PID ] = con THEN
    WatchGetCon;
  ELSIF Did[ PID ] = tty THEN
    WatchGetTty;
  ELSIF Did[ PID ] = aea THEN
    WatchGetAea;
  ELSIF Did[ PID ] = tas THEN
    WatchGetTas;
  ELSIF Did[ PID ] = tnc THEN
    WatchGetTnc;
  ELSIF Did[ PID ] = mnp THEN
    WatchGetMnp;
  END;
END WatchGet;

PROCEDURE WatchPutCon;
VAR
  pid: BYTE;
BEGIN
  pid := PID;
  LOOP
    WITH InfoDEV[ pid ][ 0 ]^ DO
      IF kick OR pfull THEN
        SendCon;
        pfull := FALSE;
        kick := FALSE;
      END;
      WAIT( Dsign[ pid ] );
    END;
  END;
END WatchPutCon;

PROCEDURE WatchPutTty;
VAR
  pid: BYTE;
BEGIN
  pid := PID;
  LOOP
    WITH InfoDEV[ pid ][ 0 ]^ DO
      IF kick OR pfull THEN
        Send( pid, 0 );
        pfull := FALSE;
        kick := FALSE;
      END;
      WAIT( Dsign[ pid ] );
    END;
  END;
END WatchPutTty;

PROCEDURE WatchPutAea;
VAR
  pid, j: BYTE;
BEGIN
  pid := PID;
  LOOP
    FOR j := 0 TO Chans[ pid ] DO
      WITH InfoDEV[ pid ][ j ]^ DO
        IF kick OR pfull THEN
          Send( pid, j );
          pfull := FALSE;
          kick := FALSE;
        END;
        IF active AND ( NOT link ) THEN
          AxPut( pid, SOH );
          AxPut( pid, CHR( IOR( 040h, ORD( j ) ) ) );
          AxPut( pid, 'D' );
          AxPut( pid, 'I' );
          AxPut( pid, ETB );
          active := FALSE;
        END;
      END;
    END;
    WAIT( Dsign[ pid ] );
  END;
END WatchPutAea;

PROCEDURE WatchPutTas;
VAR
  pid, j: BYTE;
BEGIN
  pid := PID;
  LOOP
    FOR j := 0 TO Chans[ pid ] DO
      WITH InfoDEV[ pid ][ j ]^ DO
        IF kick OR pfull THEN
          Send( pid, j );
          pfull := FALSE;
          kick := FALSE;
        END;
        IF active AND ( NOT link ) THEN
          WHILE Rest( pid ) DO
            WAIT( Dsign[ pid ] );
          END;
          SendBreak( pid );
          AxPut( pid, STX );
          AxPut( pid, CHR( ORD( j ) + ORD( 'A' ) ) );
          AxPut( pid, 'D' );
          AxPut( pid, CR );
          AxPut( pid, 'K' );
          AxPut( pid, CR );
          active := FALSE;
        END;
      END;
    END;
    WAIT( Dsign[ pid ] );
  END;
END WatchPutTas;

PROCEDURE WatchPutTnc;
VAR
  pid: BYTE;
BEGIN
  pid := PID;
  WITH InfoDEV[ pid ][ 0 ]^ DO
    LOOP
      IF kick OR pfull THEN
        Send( pid, 0 );
        pfull := FALSE;
        kick := FALSE;
      END;
      IF active AND ( NOT link ) THEN
        SendBreak( pid );
        AxPut(pid, 'D' );
        AxPut(pid, CR );
        AxPut(pid, 'K' );
        AxPut(pid, CR );
        active := FALSE;
      END;
      WAIT( Dsign[ pid ] );
    END;
  END;
END WatchPutTnc;

PROCEDURE WatchPutMnp;
VAR
  pid: BYTE;
BEGIN
  pid := PID;
  WITH InfoDEV[ pid ][ 0 ]^ DO
    LOOP
      IF kick OR pfull THEN
        Send( pid, 0 );
        pfull := FALSE;
        kick := FALSE;
      END;
      IF active AND ( NOT link ) THEN
        DTRoff( pid );
	WHILE Dcd( pid ) DO
          WAIT( Dsign[ pid ] );
        END;
        DTRon( pid );
        active := FALSE;
      END;
      WAIT( Dsign[ pid ] );
    END;
  END;
END WatchPutMnp;

PROCEDURE WatchPut;
BEGIN
  IF Did[ PID ] = con THEN
    WatchPutCon;
  ELSIF Did[ PID ] = tty THEN
    WatchPutTty;
  ELSIF Did[ PID ] = aea THEN
    WatchPutAea;
  ELSIF Did[ PID ] = tas THEN
    WatchPutTas;
  ELSIF Did[ PID ] = tnc THEN
    WatchPutTnc;
  ELSIF Did[ PID ] = mnp THEN
    WatchPutMnp;
  END;
END WatchPut;

PROCEDURE CallBBS;
VAR
  id: ID;
BEGIN
  id.pid := PID;
  id.cid := CID;
  WITH InfoDEV[ id.pid ][ id.cid ]^ DO
    LOOP
      IF link THEN
        active := TRUE;
        ghptr := 0;
        gtptr := 0;
        gfull := FALSE;
        kick := FALSE;
        phptr := 0;
        ptptr := 0;
        pfull := FALSE;
    (*    WriteStartUp( id.pid, id.cid, 'BBS' );  *)
        StartUpBBS( id );
        ghptr := 0;
        gtptr := 0;
        gfull := FALSE;
        kick := FALSE;
        phptr := 0;
        ptptr := 0;
        pfull := FALSE;
      END;
      WAIT( Csign[ id.pid ] );
    END;
  END;
  WAIT( Esign );
END CallBBS;

PROCEDURE DM;
BEGIN
  IF Did[ PID ] = con THEN
    echoMode[ PID ] := TRUE;
  ELSIF Did[ PID ] = tty THEN
    echoMode[ PID ] := TRUE;
  ELSIF Did[ PID ] = aea THEN
    echoMode[ PID ] := FALSE;
  ELSIF Did[ PID ] = tas THEN
    echoMode[ PID ] := FALSE;
  ELSIF Did[ PID ] = tnc THEN
    echoMode[ PID ] := FALSE;
  ELSIF Did[ PID ] = mnp THEN
    echoMode[ PID ] := TRUE;
  END;
(*  WriteStartUp( PID, 0, 'cid = 0 WatchGet' ); *)
  StartProcess( WatchGet, 1024 );
(*  WriteStartUp( PID, 0, 'cid = 0 WatchPut' ); *)
  StartProcess( WatchPut, 1024 );
(*  WAIT( Esign ); *)
END DM;

PROCEDURE CM;
VAR
  pid, i: BYTE;
BEGIN
  pid := PID;
  i := 0;
  FOR i := 0 TO Chans[ pid ] DO
    CID := i;
(*    WriteStartUp( pid, i, 'CallBBS' );  *)
    StartProcess( CallBBS, Heap );
    INC( i );
  END;
(*  WAIT( Esign ); *)
END CM;

PROCEDURE Initialize;
VAR
  i, j: BYTE;
BEGIN
  FOR i := 0 TO Ports DO
    FOR j := 0 TO Chans[ i ] DO
      NEW( InfoDEV[ i ][ j ] );
      WITH InfoDEV[ i ][ j ]^ DO
        active := FALSE;
        link := FALSE;
        gfull := FALSE;
        pfull := FALSE;
        kick := FALSE;
        ghptr := 0;
        gtptr := 0;
        phptr := 0;
        ptptr := 0;
	bsize := PortBufSize[ i ];
	ALLOCATE( InfoDEV[ i ][ j ]^.get, bsize );
	ALLOCATE( InfoDEV[ i ][ j ]^.put, bsize );
      END;
    END;
  END;
  InfoDEV[ 0 ][ 0 ]^.active := TRUE;
  Did[ 0 ] := con;
END Initialize;

PROCEDURE PM;
VAR
  i: BYTE;
  j: CARDINAL;
BEGIN
  IF LONGCARD( StartUpBBS ) = 0 THEN
    RETURN;
  END;
  Initialize;
  Init( Esign );
  FOR i := 0 TO Ports DO
    Init( Dsign[ i ] );
    Init( Csign[ i ] );
  END;
  FOR i := 0 TO Ports DO
    PID := i;
    DM;
    CM;
  END;
  LOOP
    FOR i := 0 TO Ports DO
      FOR j := 0 TO Priority[ i ] DO
        SEND( Dsign[ i ] ); (* deemed as input *)
        SEND( Dsign[ i ] ); (* deemed as output *)
        SEND( Csign[ i ] );
      END;
    END;
    IF NOT InfoDEV[ 0 ][ 0 ]^.active THEN
      RETURN;
    END;
  END;
END PM;

BEGIN
  Heap := 32768;
  
  DevStr[ con ] := 'CON';
  DevStr[ tty ] := 'TTY';
  DevStr[ aea ] := 'AEA';
  DevStr[ tas ] := 'TAS';
  DevStr[ tnc ] := 'TNC';
  DevStr[ mnp ] := 'MNP';
END Manager.
