
IMPLEMENTATION MODULE BBS;

FROM SYSTEM IMPORT
  BYTE;
FROM STORAGE IMPORT
  ALLOCATE,Cleanup;
FROM GetDate IMPORT
  TimeRec,GetDateTime,GetFileDateTime,SetFileDateTime;
FROM Strings IMPORT
  Assign,Concat,Pos,StoS,Copy,Length,CompareStr;
FROM Streams IMPORT
  STREAM,EOS,Direction,Connect,Disconnect,WriteChar,ReadChar,
  BufferStream,GetLongPos,DeleteFile,StreamLength;
FROM Stdio IMPORT
  GetStreamLine,
  WriteLnStream,WriteStringStream,WriteCardStream,WriteLongStream,
  ReadStringStream,ReadCardStream;
FROM OtherMSDOS IMPORT
  MakeDir,GetCurDisk;
FROM LM IMPORT
  KickLine,UntilReachLine,BusyLine,WaitLine,
  WriteLine,WriteStringLine,WriteLnLine,WriteCardLine,
  WriteLongLine,ReadLine,ReadStringLine,ReadCardLine;
FROM Uty IMPORT
  GetDiskFree,ToUppers,CtoA,AtoC,MatchString,MatchStringAmbig,CheckKanji;
FROM Manager IMPORT
  CHANS,ID,InfoDEV,StartUpBBS,Chans,Ports,Did,DevStr,DevLst,
  Priority,PortBufSize,
  GetEchoMode, SetEchoMode;
FROM BBSUTY IMPORT
  TailCut, CheckTime, InNumber, Valid, Invalid,
  CopyFile, SetFp, GoEOS, Exist, Cannotopen,
  WriteTimeStream, WriteTimeLine, PutFileLine,
  IsCall, IsAlphabetic,
  MakeIndex, GetIndex, IncIndex, IncIndexContinue;
FROM CallProg IMPORT CallProg;
FROM InOut IMPORT Write,WriteString,WriteLn,WriteInt,WriteCard;

CONST
  CHATS = 9;  (*  É`ÉÉÉbÉgÇÕ 10êlÇ‹Ç≈ *)
  MBS = 9;  (*  ÉÅÅ[ÉãÉ{ÉbÉNÉXÇÕ 10å¬ *)
  PAGE = 20;  (*  Files ÉRÉ}ÉìÉhÇ≈égópÇ∑ÇÈ ÉâÉCÉì/ÉyÅ[ÉW  *)

TYPE
  COM = ( guide,files,new,read,rn,write,kill,log,help,access,
      x,profile,chat,talk,who,set,time,ver,free,task,
      exit,bye,quit,
      shell,fileup,chkusr,byebye,biff,whoami,whochat,su,
      room,nein );
  LEVEL = ( disphelp, dispchat, dispbell );
  LSET = SET OF LEVEL;
  GROUP = ( unchecked, checked, root );
  RoomIndex = ARRAY [0..ROOMS+1] OF CARDINAL;
  TableBBS = RECORD
    start, last, end: TimeRec;
    uid, cons, result: CARDINAL;
    group: GROUP;
    level: LSET;
    CurrentROOM: MINIBUF;
    index: RoomIndex;
  END;
  CALL = ARRAY [0..5] OF CHAR;
  MAILBUF = ARRAY [0..255] OF CHAR;
  MAILBOX = RECORD
    occupy: BOOLEAN;
    from: MINIBUF;
    to: ID;
    str: MAILBUF;
  END;
  CHATBOX = RECORD
    from: ID;
    str: MAILBUF;
  END;
  TITLE = ARRAY [0..39] OF CHAR;
  ComFlags = RECORD
    Com: COM;
    flg_all,flg_whole,flg_number,flg_room,flg_p,
    flg_delete,flg_search,flg_last,flg_call,flg_q,flg_rn:BOOLEAN;
  END;
  ComPacket = RECORD
    Com: COM;
    flg_all,flg_whole,flg_number,flg_room,flg_p,
    flg_delete,flg_search,flg_last,flg_call,flg_q,flg_rn: BOOLEAN;
    Room: MINIBUF;        (* ëŒè€ÉãÅ[ÉÄÅAëŒè€ÉRÅ[Éã *)
    Search: TITLE;        (* åüçıï∂éöóÒ *)
    Start, Stop: CARDINAL;    (* äJénÅEèIóπî‘çÜ *)
  END;

CONST
  COMS = ORD(MAX(COM));

VAR
  ChatPtr: CARDINAL;
  ChatUser: ARRAY [0..CHATS] OF ID;
  ChatBox: ARRAY [0..CHATS] OF CHATBOX;
  ComStr: ARRAY [0..COMS] OF MINIBUF;
  MailBox: ARRAY [0..MBS] OF MAILBOX;
  InfoBBS: ARRAY [0..PORTS],[0..CHANS] OF POINTER TO TableBBS;
  Packet: ARRAY [0..PORTS],[0..CHANS] OF POINTER TO ComPacket;


(*  ÉÜÅ[ÉeÉBÉäÉeÉB -- ÇÕÇ∂Çﬂ  *)



PROCEDURE FindCOM(VAR s:ARRAY OF CHAR):COM;
VAR i: ARRAY [0..COMS] OF CARDINAL;
  j,k,m: CARDINAL;
BEGIN
  FOR j := 0 TO COMS-1 DO
    i[ j ] := MatchStringAmbig(ComStr[ j ],s);
  END;
  m := 0;
  FOR j := 0 TO COMS-1 DO
    IF m < i[ j ] THEN
      m := i[ j ];
      k := j;
    END;
  END;
  IF m = 0 THEN
    RETURN nein;
  ELSE
    RETURN VAL(COM,k);
  END;
END FindCOM;

PROCEDURE FindROOM(VAR s:ARRAY OF CHAR):INTEGER;
VAR i: ARRAY [0..ROOMS] OF CARDINAL;
  j,k,m: CARDINAL;
BEGIN
  FOR j := 0 TO Rooms DO
    i[ j ] := MatchString(InfoROOM[j]^.RoomName,s);
  END;
  m := 0;
  FOR j := 0 TO Rooms DO
    IF m < i[j] THEN
      m := i[j];
      k := j;
    END;
  END;
  IF m = 0 THEN
    RETURN -1;
  ELSE
    RETURN k;
  END;
END FindROOM;

PROCEDURE CatCat(VAR s:ARRAY OF CHAR; r:ARRAY OF CHAR);
BEGIN
  Concat(s,r,s);
END CatCat;

PROCEDURE CatENV(VAR s:ARRAY OF CHAR; r:ARRAY OF CHAR);
BEGIN
  Concat(EnvDNET,r,s);
END CatENV;

PROCEDURE CatSJANK(id:ID;VAR s:ARRAY OF CHAR);
(*VAR
  c: CARDINAL;
*)
BEGIN
(*  c := InfoBBS[id.pid][id.cid]^.group;  (* Ç±ÇÍÇÕ group Ç…ïœÇÌÇ¡ÇΩ *)
  IF c = 2 THEN
    Concat(s,'.euc',s);
  ELSIF c = 1 THEN
    Concat(s,'.ank',s);
  ELSE  *)
    Concat(s,'.sj',s);    (* Ç±Ç±ÇæÇØóLå¯ *)
(*  END;  *)
END CatSJANK;

PROCEDURE NotFoundLine(id:ID; s:ARRAY OF CHAR);
BEGIN
  WriteStringLine(id,'[');
  WriteStringLine(id,s);
  WriteStringLine(id,'] Ç™å©Ç¬Ç©ÇËÇ‹ÇπÇÒ.');
  WriteLnLine(id);
END NotFoundLine;

(*  ÉVÉXÉeÉÄÉtÉ@ÉCÉã  *)

PROCEDURE MakeDNETfile( VAR buf: ARRAY OF CHAR; file: ARRAY OF CHAR );
BEGIN
  Concat( EnvDNET, '\', buf );
  CatCat( buf, file );
END MakeDNETfile;

(*  ÉÜÅ[ÉUÅ[ÉfÉBÉåÉNÉgÉä  *)

PROCEDURE MakeUSRdir( VAR buf: ARRAY OF CHAR; call: ARRAY OF CHAR );
BEGIN
  Concat( EnvUSR, '\', buf );
  CatCat( buf, call );
END MakeUSRdir;

(*  ÉÜÅ[ÉUÅ[ÉtÉ@ÉCÉã  *)

PROCEDURE MakeUSRfile( VAR buf: ARRAY OF CHAR; call, file: ARRAY OF CHAR );
BEGIN
  Concat( EnvUSR, '\', buf );
  CatCat( buf, call );
  CatCat( buf, '\' );
  CatCat( buf, file );
END MakeUSRfile;

(*  ÉÜÅ[ÉUÅ[ÅEî‘çÜÉtÉ@ÉCÉã  *)

PROCEDURE MakeUSRmsg( VAR buf: ARRAY OF CHAR; call: ARRAY OF CHAR; number: CARDINAL );
VAR
  idx: MINIBUF;
BEGIN
  CtoA( number, idx, 4, TRUE );
  Concat( EnvUSR, '\', buf );
  CatCat( buf, call );
  CatCat( buf, '\' );
  CatCat( buf, idx );
  CatCat( buf, '.msg' );
END MakeUSRmsg;

(*  ÉãÅ[ÉÄÉtÉ@ÉCÉã  *)

PROCEDURE MakeBBSfile( VAR buf: ARRAY OF CHAR; room, file: ARRAY OF CHAR; );
VAR
  res: INTEGER;
BEGIN
  res := FindROOM( room );
  Concat( InfoROOM[ res ]^.RoomDir, '\', buf );
  CatCat( buf, file );
END MakeBBSfile;

(*  ÉãÅ[ÉÄÅEî‘çÜÉtÉ@ÉCÉã  *)

PROCEDURE MakeBBSmsg( VAR buf: ARRAY OF CHAR; room: ARRAY OF CHAR; number: CARDINAL );
VAR
  res: INTEGER;
  idx: MINIBUF;
BEGIN
  CtoA( number, idx, 4, TRUE );
  res := FindROOM( room );
  Concat( InfoROOM[ res ]^.RoomDir, '\', buf );
  CatCat( buf, idx );
  CatCat( buf, '.msg' );
END MakeBBSmsg;

(* êVãKÉÜÅ[ÉUÅ[ÇÃìoò^ *)

PROCEDURE AddUser(id:ID);
VAR
  Call: CALL;
  fp: STREAM;
  c, d: CARDINAL;
  buf: LINEBUF;
BEGIN
  WriteStringLine(id,'Ç†Ç»ÇΩÇÕèâÇﬂÇƒÇÃÉAÉNÉZÉXÇ≈Ç∑.');
  WriteLnLine(id);
  KickLine(id);
  
  MakeUSRdir( buf, InfoDEV[id.pid][id.cid]^.call );
  IF NOT MakeDir(buf) THEN
    MakeUSRfile( buf, InfoDEV[id.pid][id.cid]^.call, "check" );
    IF 0 <> Connect(fp,buf,output) THEN
      RETURN
    END;
    Disconnect(fp,TRUE);
    c := DeleteFile( buf );
  END;
  
  MakeBBSfile( buf, "USER", "msg.idx" );
  IncIndex(buf,c,d);
  InfoBBS[id.pid][id.cid]^.uid := d;
  InfoBBS[id.pid][id.cid]^.cons := 1;
  MakeUSRfile( buf, InfoDEV[id.pid][id.cid]^.call, "room.idx" );
  MakeIndex(buf,d,0);
  IF 0 = Connect(fp,buf,inputoutput) THEN
    GetStreamLine(fp,buf);
    FOR c := 0 TO Rooms DO
      WriteStringStream(fp,InfoROOM[c]^.RoomName);
      WriteStringStream(fp,' ');
      WriteCardStream(fp,0,4,TRUE);
      WriteLnStream(fp);
    END;
    Disconnect(fp,TRUE);
  END;
  
  MakeUSRfile( buf, InfoDEV[id.pid][id.cid]^.call, "user.idx" );    (* ÉRÅ[ÉhånÅEÉåÉxÉã *)
  MakeIndex(buf,0,0);
  
  MakeUSRfile( buf, InfoDEV[id.pid][id.cid]^.call, "log.idx" );   (* ÉÜÅ[ÉUÅ[ÉçÉO *)
  MakeIndex(buf,0,0);
  
  MakeUSRfile( buf, InfoDEV[id.pid][id.cid]^.call, "msg.idx" );   (* ÉÅÅ[Éã *)
  MakeIndex(buf,0,0);
  
  MakeBBSfile( buf, "USER", "msg.dir" );
  IF 0 = Connect(fp,buf,inputoutput) THEN
    GoEOS(fp);
    WriteCardStream(fp,InfoBBS[id.pid][id.cid]^.uid,4,TRUE);
    WriteChar(fp,' ');
    c:=StoS(InfoDEV[id.pid][id.cid]^.call,Call,TRUE);
    WriteStringStream(fp,Call);
    WriteChar(fp,' ');
    WriteTimeStream(fp,InfoBBS[id.pid][id.cid]^.start,FALSE);
    WriteStringStream(fp,'  ');
    WriteTimeStream(fp,InfoBBS[id.pid][id.cid]^.start,TRUE);
    WriteStringStream(fp,'  ');
    WriteCardStream(fp,InfoBBS[id.pid][id.cid]^.cons,4,FALSE);
    WriteLnStream(fp);
    Disconnect(fp,TRUE);
  END;
END AddUser;

(* USER ÉäÉXÉgÇÃèCê≥ *)

PROCEDURE FixUserDir(id:ID);
VAR
  fp: STREAM;
  b, e: CARDINAL;
  l: LONGCARD;
  buf: TITLE;
BEGIN
  MakeBBSfile( buf, "USER" , "msg.idx" );
  GetIndex(buf,b,e);
  IF (e < InfoBBS[id.pid][id.cid]^.uid) OR (InfoBBS[id.pid][id.cid]^.uid < b) THEN
    Cannotopen(id,buf);
    RETURN;
  END;
  MakeBBSfile( buf, "USER", "msg.dir" );
  IF 0 <> Connect(fp,buf,inputoutput) THEN
    Cannotopen(id,buf);
    RETURN;
  END;
  
  e := InfoBBS[id.pid][id.cid]^.uid-b;
  l := LONG(e)*44+22;
  
  IF NOT SetFp(fp,l) THEN
    Cannotopen(id,buf);
  ELSE
    WriteTimeStream(fp,InfoBBS[id.pid][id.cid]^.start,TRUE);
    WriteStringStream(fp,'  ');
    WriteCardStream(fp,InfoBBS[id.pid][id.cid]^.cons,4,FALSE);
  END;
  Disconnect(fp,TRUE);
END FixUserDir;

(* ÉeÉìÉ|ÉâÉäÉtÉ@ÉCÉãñºÇçÏÇËÇ‹Ç∑. PID, CID Ç™ÉLÅ[Ç…Ç»ÇËÇ‹Ç∑. *)

PROCEDURE MakeTmp(id:ID;VAR s:ARRAY OF CHAR);
VAR
  ps,cs: ARRAY [0..2] OF CHAR;
BEGIN
  CtoA(id.pid,ps,2,TRUE);
  CtoA(id.cid,cs,2,TRUE);
  s[0] := '\';
  s[1] := ps[0];
  s[2] := ps[1];
  s[3] := 0x;
  CatCat(s,cs);
  CatCat(s,'.tmp');
  Concat(EnvTMP,s,s);
END MakeTmp;


PROCEDURE WriteBoard(id:ID; VAR tmp:ARRAY OF CHAR; VAR size:LONGCARD):BOOLEAN;
VAR
  ch: CHAR;
  fp: STREAM;
  flg_new, flg_end, flg_exit: BOOLEAN;
  c,d: CARDINAL;
  buf: LINEBUF;
BEGIN
  IF Packet[id.pid][id.cid]^.Com = x THEN
    Assign(Packet[id.pid][id.cid]^.Search,tmp);
    WriteStringLine(id,"É^ÉCÉgÉãÇì¸óÕÇµÇƒÇ≠ÇæÇ≥Ç¢.");
    WriteLnLine(id);
  ELSE
    WriteStringLine(id,'ÇPçsñ⁄=É^ÉCÉgÉã  ÇQçsñ⁄Ç©ÇÁ=ñ{ï∂  ç≈èIçs= .(ÉsÉäÉIÉhÇæÇØÇÃçs)  íÜíf= ..');
    WriteLnLine(id);
  END;
  WriteStringLine(id,"+--ç≈ëÂ40ï∂éö-- ");
  WriteStringLine(id,Packet[id.pid][id.cid]^.Room);
  d := Length( Packet[id.pid][id.cid]^.Room );
  WriteLine(id,' ');
  FOR c := 1 TO 22 - d DO
    WriteLine(id,'-');
  END;
  WriteLine(id,'+');
  WriteLnLine(id);
  KickLine(id);
  ReadStringLine(id,buf);
  IF NOT InfoDEV[id.pid][id.cid]^.link THEN
    RETURN FALSE;
  END;
  IF (buf='.') OR (buf='..') THEN
    WriteStringLine(id,'èëÇ´çûÇ›ÇíÜífÇµÇ‹ÇµÇΩ.');
    WriteLnLine(id);
    KickLine(id);
    RETURN FALSE;
  ELSE
    Assign(buf,Packet[id.pid][id.cid]^.Search);
    CheckKanji(Packet[id.pid][id.cid]^.Search,39);
  END;
  IF Packet[id.pid][id.cid]^.Com <> x THEN
    MakeTmp(id,tmp);
    IF 0 <> Connect(fp,tmp,output) THEN
      Cannotopen(id,tmp);
      RETURN FALSE;
    END;
    BufferStream(fp,1024);
    flg_new := TRUE;
    flg_end := FALSE;
    flg_exit := FALSE;
    LOOP
      ReadLine(id,ch);
      IF NOT InfoDEV[id.pid][id.cid]^.link THEN
        Disconnect(fp,TRUE);
        c := DeleteFile(tmp);
        RETURN FALSE;
      END;
      IF ch = 0dx THEN
        IF flg_exit = TRUE THEN
          WriteStringLine(id,'èëÇ´çûÇ›ÇíÜífÇµÇ‹ÇµÇΩ.');
          WriteLnLine(id);
          KickLine(id);
          Disconnect(fp,TRUE);
          c := DeleteFile(tmp);
          RETURN FALSE;
        END;
        IF flg_end = TRUE THEN
          EXIT;
        END;
        flg_new := TRUE;
        WriteChar(fp,0dx);
      ELSE
        IF flg_new = TRUE THEN
          flg_new := FALSE;
          IF ch = '.' THEN
            flg_end:=TRUE;
          ELSE
            WriteChar(fp,ch);
          END;
        ELSIF flg_end = TRUE THEN
          flg_end := FALSE;
          IF ch = '.' THEN
            flg_exit := TRUE;
          ELSE
            WriteChar(fp,'.');
            WriteChar(fp,ch);
          END;
        ELSIF flg_exit = TRUE THEN
          flg_exit := FALSE;
          WriteChar(fp,'.');
          WriteChar(fp,'.');
          WriteChar(fp,ch);
        ELSE
          WriteChar(fp,ch);
        END;
      END;
    END;
    Disconnect(fp,TRUE);
  END;
  IF 0 <> Connect(fp,tmp,input) THEN
    NotFoundLine(id,'MESSAGE');
    RETURN FALSE;
  END;
  size := StreamLength(fp);
  IF size >= 10240 THEN
    WriteStringLine(id,'ÇΩÇæÇ¢Ç‹ÉfÅ[É^ÇèëÇ´çûÇ›íÜÇ≈Ç∑. ÇµÇŒÇÁÇ≠Ç®ë“ÇøÇ≠ÇæÇ≥Ç¢.');
    WriteLnLine(id);
    KickLine(id);
  END;
  Disconnect(fp,TRUE);
  RETURN TRUE;
END WriteBoard;

PROCEDURE More(id:ID;p,q:CARDINAL):INTEGER;
VAR
  c,res:CARDINAL;
  buf:TITLE;
BEGIN
  c := q - p;
  WriteStringLine(id,'----- page');
  WriteCardLine(id,c,4,FALSE);
  WriteLine(id,'/');
  WriteCardLine(id,q,4,FALSE);
  WriteStringLine(id,' ----- (íÜíf=..  ÉXÉLÉbÉv=êîéö  ë±Ç´=ÉäÉ^Å[Éì) :');
  KickLine(id);
  ReadStringLine(id,buf);
  IF (NOT InfoDEV[id.pid][id.cid]^.link ) OR (buf='..') THEN
    RETURN -1;
  END;
  IF buf[0] = 0x THEN
    RETURN 0;
  END;
  c := AtoC(buf,0,res);
  RETURN INTEGER(res);
END More;

PROCEDURE GetNumber(id:ID;VAR res:CARDINAL);
VAR
  c: CARDINAL;
  buf: TITLE;
BEGIN
  WriteStringLine(id,'âΩî‘Ç≈Ç∑Ç©? : ');
  KickLine(id);
  ReadStringLine(id,buf);
  c := AtoC(buf,0,res);
END GetNumber;

(* íTçıï∂éöóÒÇÃçÏê¨ *)

PROCEDURE MakeSearchString(VAR title,room,res:ARRAY OF CHAR);
VAR
  c: CARDINAL;
  buf: ARRAY [0..6] OF CHAR;
BEGIN
  Assign(room,buf);
  c := StoS(buf,buf,TRUE);
  Assign(buf,res);
  Copy(title,2,4,buf);
  CatCat(res,buf);
END MakeSearchString;

PROCEDURE SearchStringStream(VAR fp: STREAM; VAR str: ARRAY OF CHAR; p,q:CARDINAL):BOOLEAN;
VAR
  c: CHAR;
  i: INTEGER;
  l: LONGCARD;
BEGIN
  GoEOS(fp);
  GetLongPos(fp,l);
  INC(l,p);
  LOOP
    IF l < q THEN
      EXIT;
    END;
    DEC(l,q);
    IF NOT SetFp(fp,l) THEN
      EXIT
    END
    i := -1;
    REPEAT
      INC(i);
      ReadChar(fp,c);
    UNTIL EOS(fp) OR (str[i] = 0x) OR (str[i] <> c) OR (i >= HIGH(str));
    IF (str[i] = 0x) OR (i = HIGH(str)) THEN
      IF NOT SetFp(fp,l) THEN
        EXIT
      END;
      RETURN TRUE;
    END;
  END;
  RETURN FALSE;
END SearchStringStream;

(* USER ÉçÉOÇÃèCê≥ *)

PROCEDURE FixUserLog(VAR title,Room:ARRAY OF CHAR; flag:BOOLEAN);
VAR
  fp: STREAM;                 (* TRUE:âÒêî FALSE:çÌèú *)
  Call: CALL;
  c: CARDINAL;
  l: LONGCARD;
  buf: TITLE;
BEGIN
  IF Room = 'USER' THEN
    RETURN;
  END;
  
  FOR c := 0 TO 5 DO
    Call[c] := title[c+7];
    IF Call[c] = ' ' THEN
      Call[c] := 0x;
    END;
  END;
  
  MakeUSRfile( buf, Call, "log.dir" );
  
(*  WriteString('[ÉIÅ[ÉvÉì:');
  WriteString(buf);
  WriteString(']');
  WriteLn;
*)
  
  IF 0 <> Connect(fp,buf,inputoutput) THEN
    RETURN;
  END;
  
  MakeSearchString(title,Room,buf);
  
(*  WriteString('[íTçıï∂éö:');
  WriteString(buf);
  WriteString(']');
  WriteLn;
*)

  IF FALSE = SearchStringStream(fp,buf,7,75) THEN
(*    WriteString('[íTçıé∏îs]');
    WriteLn;
*)
    Disconnect(fp,TRUE);
    RETURN;
  END;
  
(*  WriteString('[íTçıèIóπ]');
  WriteLn;
*)
  GetLongPos(fp,l);
  IF flag THEN
    INC(l,12);
    IF SetFp(fp,l) THEN
      ReadCardStream(fp,c);
      INC(c);
      IF SetFp(fp,l) THEN
        WriteCardStream(fp,c,4,TRUE);
      END
    END;
  ELSE
    DEC(l,2);
    IF SetFp(fp,l) THEN
      WriteChar(fp,'*')
    END
  END;
  Disconnect(fp,TRUE);
END FixUserLog;

PROCEDURE WriteChudanLine(id:ID);
BEGIN
  WriteLnLine(id);
  WriteStringLine( id, " [ íÜífÇµÇ‹ÇµÇΩ! ]" );
  WriteLnLine(id);
END WriteChudanLine;

PROCEDURE ReadBoard(id:ID; VAR title:ARRAY OF CHAR):BOOLEAN;
VAR
  res,begin,number: CARDINAL;
  header: ARRAY [0..69] OF CHAR;
  buf: TITLE;
BEGIN
  WriteLnLine(id);
  WriteLine(id,'[');
  WriteStringLine(id,Packet[id.pid][id.cid]^.Room);
  WriteLine(id,' ');
  IF Packet[id.pid][id.cid]^.Room = "USER"  THEN
    res := AtoC(title,0,number);
    begin := 4;
  ELSE
    res := AtoC(title,2,number);
    begin := 6;
  END;
  WriteCardLine(id,number,4,TRUE);
  WriteLine(id,']');
  Copy(title,begin,70,header);
  TailCut(header);
  WriteStringLine(id,header);
  WriteLnLine(id);
  
  IF Packet[id.pid][id.cid]^.flg_call THEN
    MakeUSRmsg( buf, Packet[id.pid][id.cid]^.Room, number );
  ELSE
    MakeBBSmsg( buf, Packet[id.pid][id.cid]^.Room, number );
  END
  IF Exist(buf) THEN
    res := 0;
    IF Packet[id.pid][id.cid]^.flg_q THEN
      IF Packet[id.pid][id.cid]^.flg_rn THEN
        WriteStringLine(id,"ì«Ç›Ç‹Ç∑Ç©? [ÇÕÇ¢:RET/Ç¢Ç¢Ç¶:'N'/íÜíf:'..'] : ");
        KickLine(id);
        ReadStringLine(id,buf);
        IF buf = ".." THEN
          Packet[id.pid][id.cid]^.flg_rn := FALSE;
          RETURN FALSE;
        ELSIF (buf = 'N') OR (buf = 'n') THEN
          RETURN FALSE
        END
      ELSE
        WriteStringLine(id,'âΩÉoÉCÉgñ⁄Ç©ÇÁì«Ç›Ç‹Ç∑Ç©? : ');
        KickLine(id);
        ReadStringLine(id,buf);
        begin := AtoC(buf,0,res);
      END
    END;
    IF NOT InfoDEV[id.pid][id.cid]^.link THEN
      RETURN FALSE;
    END;
    IF Packet[id.pid][id.cid]^.flg_call THEN
      MakeUSRmsg( buf, Packet[id.pid][id.cid]^.Room, number );
    ELSE
      MakeBBSmsg( buf, Packet[id.pid][id.cid]^.Room, number );
    END
    IF NOT PutFileLine(id,buf,res) THEN
      WriteChudanLine(id);
      RETURN FALSE;
    END
    IF NOT InfoDEV[id.pid][id.cid]^.link THEN
      RETURN FALSE;
    END;
  ELSE
    NotFoundLine(id,'MESSAGE');
    RETURN FALSE;
  END
  WriteLnLine(id);
  WriteStringLine(id,'----- End Of [');
  WriteStringLine(id,Packet[id.pid][id.cid]^.Room);
  WriteLine(id,' ');
  WriteCardLine(id,number,4,TRUE);
  WriteStringLine(id,'] -----');
  WriteLnLine(id);
  RETURN TRUE;
END ReadBoard;

PROCEDURE GetRoomIndex( id:ID; VAR index: RoomIndex );
VAR
  i, c, d: CARDINAL;
  buf: TITLE;
BEGIN
  FOR i := 0 TO Rooms DO
    IF InfoROOM[i]^.RoomName = "MAIL" THEN
      MakeUSRfile( buf, InfoDEV[id.pid][id.cid]^.call, "msg.idx" );
    ELSE
      MakeBBSfile( buf, InfoROOM[i]^.RoomName, "msg.idx" );
    END
    GetIndex(buf,c,d);
    index[ i ] := d;
  END;
  IF InfoBBS[id.pid][id.cid]^.group = root THEN
    MakeUSRfile( buf, EnvCALL, "msg.idx" );
    GetIndex(buf,c,d);
    index[ Rooms+1 ] := d;
  END;
END GetRoomIndex;

PROCEDURE MargeProfile( VAR idx, msg, tmp, title: ARRAY OF CHAR; b:BOOLEAN );
VAR
  c: CHAR;
  fi, fo: STREAM;
  buf: LINEBUF;
BEGIN
  IF 0 = Connect(fo,tmp,output) THEN
    IF 0 = Connect(fi,idx,input) THEN
      GetStreamLine(fi,buf);
      
      GetStreamLine(fi,buf);
      WriteStringStream(fo,"ñºëO: ");
      WriteStringStream(fo,buf);
      WriteLnStream(fo);
      
      GetStreamLine(fi,buf);
      WriteStringStream(fo,"èZèä: ");
      WriteStringStream(fo,buf);
      WriteLnStream(fo);
      
      Disconnect(fi,TRUE);
    ELSE
      WriteLnStream(fo);
      WriteLnStream(fo);
    END;
    IF 0 = Connect(fi,msg,input) THEN
      IF b THEN
        WriteStringStream(fo,title);
        WriteLnStream(fo);
      ELSE
        GetStreamLine(fi,buf);
        GetStreamLine(fi,buf);
      END;
      
      WHILE NOT EOS(fi) DO
        ReadChar(fi,c);
        WriteChar(fo,c);
      END;
      Disconnect(fi,TRUE);
    END;
    Disconnect(fo,TRUE);
  END;
END MargeProfile;

(*  ÉÜÅ[ÉeÉBÉäÉeÉB -- Ç®ÇÌÇË  *)


PROCEDURE MailboxBBS(id:ID): BOOLEAN;
VAR
  flag: BOOLEAN;
  i: CARDINAL;
BEGIN
  flag := FALSE;
  FOR i := 0 TO MBS DO
    IF (MailBox[i].occupy = TRUE) AND (MailBox[i].to.pid = id.pid) AND (MailBox[i].to.cid = id.cid) THEN
      IF NOT flag THEN
        WriteLnLine(id);
        flag := TRUE;
      END;
      IF NOT ( dispbell IN InfoBBS[id.pid][id.cid]^.level ) THEN
        WriteLine(id,07x)
      END;
      WriteStringLine(id,'ìdïÒ [');
      WriteStringLine(id,MailBox[i].from);
      WriteStringLine(id,']: ');
      WriteStringLine(id,MailBox[i].str);
      WriteLnLine(id);
      MailBox[i].occupy := FALSE;
    END;
  END;
  RETURN flag;
END MailboxBBS;


PROCEDURE WhochatBBS(id:ID);
VAR
  flag: BOOLEAN;
  d, i, j, k: CARDINAL;
  Call: CALL;
BEGIN
  flag := FALSE;
  WriteLnLine(id);
  WriteStringLine(id,'åªç›É`ÉÉÉbÉgíÜÇÃÉÜÅ[ÉUÅ[');
  FOR i := 0 TO CHATS DO
    j := ORD(ChatUser[i].pid);
    k := ORD(ChatUser[i].cid);
    IF (j <= ORD(Ports)) AND (k <= ORD(Chans[j])) THEN
      IF NOT flag THEN
        flag := TRUE;
        WriteLnLine(id);
        WriteLnLine(id);
        WriteStringLine(id,'ÉÜÅ[ÉUÅ[ í[ññ PID CID UID  ÉçÉOÉCÉìÉ^ÉCÉÄ');
        WriteLnLine(id);
      END;
      d := StoS(InfoDEV[j][k]^.call,Call,TRUE);
      WriteStringLine(id,Call);
      WriteStringLine(id,'   ');
      WriteStringLine(id,DevStr[ Did[j] ]);
      WriteStringLine(id,'  ');
      WriteCardLine(id,j,2,TRUE);
      WriteStringLine(id,'  ');
      WriteCardLine(id,k,2,TRUE);
      WriteStringLine(id,'  ');
      WriteCardLine(id,InfoBBS[j][k]^.uid,4,TRUE);
      WriteLine(id,' ');
      WriteTimeLine(id,InfoBBS[j][k]^.start);
      WriteLnLine(id);
    END
  END;
  IF NOT flag THEN
    WriteStringLine(id,'ÇÕÇ¢Ç‹ÇπÇÒ.');
    WriteLnLine(id);
  END;
  WriteLnLine(id);
END WhochatBBS;

(*  ÉRÉ}ÉìÉhåQ -- ÇÕÇ∂Çﬂ  *)

PROCEDURE ChatBBS(id:ID);
VAR
  count,c,d,i: CARDINAL;
  buf: MAILBUF;
BEGIN
  i := 0;
  REPEAT
    IF (ChatUser[i].pid = 255) AND (ChatUser[i].cid = 255) THEN
      ChatUser[i] := id;
    ELSE
      INC( i );
    END;
  UNTIL (i > CHATS) OR ((ChatUser[i].pid = id.pid) AND (ChatUser[i].cid = id.cid));
  IF i > CHATS THEN
    WriteLnLine(id);
    WriteStringLine(id,"É`ÉÉÉbÉgÉVÉXÉeÉÄÇ™ÉrÉWÅ[Ç≈Ç∑.");
    WriteLnLine(id);
    WriteLnLine(id);
    RETURN;
  END;
  c := i;   (* É`ÉÉÉbÉgíÜÇÃÇhÇc *)
  
  WhochatBBS(id);
  
  WriteStringLine(id,"É`ÉÉÉbÉgÉÜÅ[ÉUÅ[Çå©ÇÈÇ…ÇÕ '?U', É`ÉÉÉbÉgÇî≤ÇØÇÈÇ…ÇÕ '..' Ç≈Ç∑.");
  WriteLnLine(id);
  WriteLnLine(id);
  KickLine(id);
  
  ChatBox[ ChatPtr ].from := id;
  ChatBox[ ChatPtr ].str := " [36mJOIN [m";
  ChatBox[ ChatPtr ].str[0] := 01bx;
  ChatBox[ ChatPtr ].str[9] := 01bx;
  INC( ChatPtr );
  IF ChatPtr > CHATS THEN
    ChatPtr := 0
  END
  
  d := ChatPtr;   (* é©ï™ÇÃì«ÇÒÇæç≈èIî‘çÜ *)
  count := 0;
  
  LOOP
    IF NOT InfoDEV[id.pid][id.cid]^.link THEN
      EXIT;
    END;
    IF BusyLine(id) THEN
      ReadStringLine(id,buf);
      IF NOT InfoDEV[id.pid][id.cid]^.link THEN
        EXIT;
      END;
      IF buf = '..' THEN
        EXIT;
      END;
      IF (buf = '?u') OR (buf = '?U') THEN
        WhochatBBS(id);
        KickLine(id);
      ELSIF buf[ 0 ] <> 0x THEN
        CheckKanji( buf, HIGH(buf) );
        ChatBox[ ChatPtr ].from := id;
        ChatBox[ ChatPtr ].str := buf;
        INC( ChatPtr );
        IF ChatPtr > CHATS THEN
          ChatPtr := 0
        END
      END
    ELSE
      INC( count );
      IF count > Unit THEN
        count := 0;
        IF MailboxBBS(id) THEN
          KickLine(id);
        END;
      END;
    END;
    IF d <> ChatPtr THEN
      IF (ChatBox[ d ].from.pid <> id.pid) OR (ChatBox[ d ].from.cid <> id.cid) THEN
        WriteLine(id,'[');
        WriteStringLine(id,InfoDEV[ChatBox[ d ].from.pid][ChatBox[ d ].from.cid]^.call);
        WriteStringLine(id,']: ');
        WriteStringLine(id,ChatBox[ d ].str);
        WriteLnLine(id);
        IF MailboxBBS(id) THEN
        END;
        KickLine(id);
      END
      INC( d );
      IF d > CHATS THEN
        d := 0;
      END
    ELSE
      WaitLine(id);
    END;
  END;
  ChatBox[ ChatPtr ].from := id;
  ChatBox[ ChatPtr ].str := " [33mLEFT [m";
  ChatBox[ ChatPtr ].str[0] := 01bx;
  ChatBox[ ChatPtr ].str[9] := 01bx;
  INC( ChatPtr );
  IF ChatPtr > CHATS THEN
    ChatPtr := 0
  END
  ChatUser[c].pid := 255;
  ChatUser[c].cid := 255;
  IF InfoDEV[id.pid][id.cid]^.link THEN
    WriteLnLine(id);
    WriteStringLine(id,"É`ÉÉÉbÉgÇî≤ÇØÇ‹ÇµÇΩ.");
    WriteLnLine(id);
    WriteLnLine(id);
  END;
END ChatBBS;


PROCEDURE TalkBBS(id:ID);
VAR
  i,j: BYTE;
  To: ID;
  buf: MAILBUF;
BEGIN
  WriteLnLine(id);
  IF Packet[id.pid][id.cid]^.flg_room = FALSE THEN
    WriteStringLine(id,'à∂ÇƒêÊ: ');
    KickLine(id);
    ReadStringLine(id,Packet[id.pid][id.cid]^.Room);
    IF (Packet[id.pid][id.cid]^.Room = '..') OR (NOT InfoDEV[id.pid][id.cid]^.link) THEN
      RETURN;
    END;
    ToUppers(Packet[id.pid][id.cid]^.Room);
  END;
  To.pid := 255;
  FOR i := 0 TO Ports DO
    FOR j := 0 TO Chans[i] DO
      IF (InfoDEV[i][j]^.link = TRUE) AND (Packet[id.pid][id.cid]^.Room = InfoDEV[i][j]^.call) THEN
        To.pid := i;
        To.cid := j;
      END;
    END;
  END;
  IF To.pid = 255 THEN
    WriteStringLine(id,'ÉçÉOÉCÉìÇµÇƒÇ¢Ç‹ÇπÇÒ.');
    WriteLnLine(id);
    RETURN;
  END;
  LOOP
    i := 0;
    WHILE i <= MBS DO
      IF MailBox[i].occupy = FALSE THEN
        MailBox[i].occupy := TRUE;
        MailBox[i].to.pid := 255;
        EXIT;
      END;
      INC( i );
    END;
    WriteStringLine(id,'ÉÅÅ[ÉãÉ{ÉbÉNÉXÇ™ÉrÉWÅ[Ç≈Ç∑.');
    WriteLnLine(id);
    RETURN;
  END;
  WriteStringLine(id,"ìdïÒÇëóÇËÇ‹Ç∑. (íÜífÇÕ '..')");
  WriteLnLine(id);
  WriteStringLine(id,'> ');
  KickLine(id);
  ReadStringLine(id,buf);
  IF (buf = '..') OR (NOT InfoDEV[id.pid][id.cid]^.link) THEN
    MailBox[i].occupy := FALSE;
    RETURN;
  END;
  CheckKanji( buf, HIGH(buf) );
  MailBox[i].to := To;
  MailBox[i].from := InfoDEV[id.pid][id.cid]^.call;
  MailBox[i].str := buf;
END TalkBBS;

PROCEDURE WhoBBS(id:ID);
VAR
  c: CARDINAL;
  i,j: BYTE;
  Call: CALL;
  buf: MINIBUF;
BEGIN
  WriteLnLine(id);
  WriteStringLine(id,'åªç›ÉçÉOÉCÉìíÜÇÃÉÜÅ[ÉUÅ[');
  WriteLnLine(id);
  WriteLnLine(id);
  WriteStringLine(id,'ÉÜÅ[ÉUÅ[ í[ññ PID CID UID  ÉRÉ}ÉìÉh ÉçÉOÉCÉìÉ^ÉCÉÄ');
  WriteLnLine(id);
  FOR i := 0 TO Ports DO
    FOR j := 0 TO Chans[i] DO
      IF (InfoDEV[i][j]^.link=TRUE) AND (InfoDEV[i][j]^.call <> "login") THEN
        c := StoS(InfoDEV[i][j]^.call,Call,TRUE);
        WriteStringLine(id,Call);
        WriteStringLine(id,'   ');
        WriteStringLine(id,DevStr[ Did[i] ]);
        WriteStringLine(id,'  ');
        WriteCardLine(id,ORD(i),2,TRUE);
        WriteStringLine(id,'  ');
        WriteCardLine(id,ORD(j),2,TRUE);
        WriteStringLine(id,'  ');
        WriteCardLine(id,InfoBBS[i][j]^.uid,4,TRUE);
        WriteLine(id,' ');
        c := ORD( Packet[i][j]^.Com );
        c := StoS( ComStr[ c ], buf, TRUE );
        WriteStringLine(id,buf);
        WriteLine(id,' ');
        WriteTimeLine(id,InfoBBS[i][j]^.start);
        WriteLnLine(id);
      END;
    END;
  END;
  WriteLnLine(id);
END WhoBBS;

PROCEDURE WhoamiBBS(id:ID);
VAR
  c: CARDINAL;
  Call: CALL;
BEGIN
  WriteLnLine(id);
  WriteStringLine(id,'ÉÜÅ[ÉUÅ[ í[ññ PID CID UID  ÉçÉOÉCÉìÉ^ÉCÉÄ');
  WriteLnLine(id);
  c := StoS(InfoDEV[id.pid][id.cid]^.call,Call,TRUE);
  WriteStringLine(id,Call);
  WriteStringLine(id,'   ');
  WriteStringLine(id,DevStr[ Did[id.pid] ]);
  WriteStringLine(id,'  ');
  WriteCardLine(id,ORD(id.pid),2,TRUE);
  WriteStringLine(id,'  ');
  WriteCardLine(id,ORD(id.cid),2,TRUE);
  WriteStringLine(id,'  ');
  WriteCardLine(id,InfoBBS[id.pid][id.cid]^.uid,4,TRUE);
  WriteLine(id,' ');
  WriteTimeLine(id,InfoBBS[id.pid][id.cid]^.start);
  WriteLnLine(id);
  WriteLnLine(id);
END WhoamiBBS;


PROCEDURE VerBBS(id:ID);
BEGIN
  WriteLnLine(id);
  WriteStringLine(id,'É\ÉtÉgñºÇ®ÇÊÇ—ÉoÅ[ÉWÉáÉì dNet Ver.4.05e (C) 1992,1996 by JF1GMH');
  WriteLnLine(id);
  WriteLnLine(id);
END VerBBS;

PROCEDURE RoomBBS(id:ID);
VAR
  i, c, b, e, r: CARDINAL;
  s: MINIBUF;
  buf: TITLE;
  fp: STREAM;
BEGIN
  CatENV( buf, '\msg\room' );
  CatSJANK(id,buf);
  IF 0 <> Connect(fp,buf,input) THEN
    Cannotopen(id,buf);
    RETURN;
  END;
  WriteLnLine(id);
  WriteStringLine(id,'î‘çÜ ÉãÅ[ÉÄñº êßå¿   ÉÅÉbÉZÅ[ÉW      ì‡óe');
  WriteLnLine(id);
  IF InfoBBS[id.pid][id.cid]^.group = root THEN
    r := Rooms+1;
  ELSE
    r := Rooms;
  END;
  FOR i := 0 TO r DO
    IF i = Rooms+1 THEN
      MakeUSRfile( buf, EnvCALL, "msg.idx" );
    ELSIF InfoROOM[i]^.RoomName = "MAIL" THEN
      MakeUSRfile( buf, InfoDEV[id.pid][id.cid]^.call, "msg.idx" );
    ELSE
      MakeBBSfile( buf, InfoROOM[i]^.RoomName, "msg.idx" );
    END;
    GetIndex(buf,b,e);
    WriteLine(id,' ');
    WriteCardLine(id,i+1,2,FALSE);
    WriteStringLine(id,'. ');
    c := StoS(InfoROOM[i]^.RoomName,s,TRUE);
    WriteStringLine(id,s);
    WriteStringLine(id,'  ');
    WriteCardLine(id,InfoROOM[i]^.RoomType,2,TRUE);
    WriteStringLine(id,'  ');
    WriteCardLine(id,b,4,TRUE);
    WriteStringLine(id,' --> ');
    WriteCardLine(id,e,4,TRUE);
    WriteStringLine(id,'  : ');
    IF i = Rooms+1 THEN
      WriteStringLine(id,"ÇrÉÅÅ[Éã");
    ELSE
      GetStreamLine(fp,buf);
      WriteStringLine(id,buf);
    END;
    WriteLnLine(id);
  END;
  WriteLnLine(id);
  Disconnect(fp,TRUE);
END RoomBBS;

PROCEDURE FreeBBS(id:ID);
VAR
  i,disk,c,d: CARDINAL;
  l: LONGCARD;
  s: MINIBUF;
BEGIN
  WriteLnLine(id);
  WriteStringLine(id,"ÉãÅ[ÉÄ   DRV   ÉfÉBÉXÉNécó ");
  WriteLnLine(id);
  FOR i := 0 TO Rooms DO
    IF InfoROOM[i]^.RoomDir[1] = ':' THEN
      disk := ORD(InfoROOM[i]^.RoomDir[0]) - ORD('A') + 1;
    ELSE
      disk := GetCurDisk();
    END;
    c := StoS(InfoROOM[i]^.RoomName,s,TRUE);
    WriteStringLine(id,s);
    WriteStringLine(id,"  ");
    WriteLine(id,CHR(disk + ORD('A') - 1));
    WriteStringLine(id,"    ");
    IF GetDiskFree(disk,c,d) THEN
      l := LONG(c) * LONG(d);
      WriteLongLine(id,l,9,FALSE);
    END;
    WriteLnLine(id);
  END;
  WriteLnLine(id);
END FreeBBS;

PROCEDURE TimeBBS(id:ID);
VAR t:TimeRec;
BEGIN
  GetDateTime(t);
  WriteLnLine(id);
  WriteStringLine(id,'åªç›ÇÃéûçè ');
  WriteCardLine(id,t.Year,4,TRUE);
  WriteStringLine(id,' îN ');
  WriteCardLine(id,t.Month,2,TRUE);
  WriteStringLine(id,' åé ');
  WriteCardLine(id,t.Day,2,TRUE);
  WriteStringLine(id,' ì˙ ');
  WriteCardLine(id,t.Hour,2,TRUE);
  WriteStringLine(id,' éû ');
  WriteCardLine(id,t.Minute,2,TRUE);
  WriteStringLine(id,' ï™ ');
  WriteCardLine(id,t.Second,2,TRUE);
  WriteStringLine(id,' ïb Ç≈Ç∑.');
  WriteLnLine(id);
  WriteLnLine(id);
END TimeBBS;

PROCEDURE Owner( id:ID ): BOOLEAN;
VAR
  c,begin,end: CARDINAL;
  res: INTEGER;
  l: LONGCARD;
  fp: STREAM;
  buf: LINEBUF;
BEGIN
  IF Packet[id.pid][id.cid]^.Room = 'USER' THEN
    NotFoundLine(id,'MESSAGE');
    RETURN FALSE;
  END;
  
  IF Packet[id.pid][id.cid]^.flg_call THEN
    MakeUSRfile( buf, Packet[id.pid][id.cid]^.Room, "msg.idx" );
  ELSE
    MakeBBSfile( buf, Packet[id.pid][id.cid]^.Room, "msg.idx" );
  END;
  GetIndex(buf,begin,end);
  
  IF Packet[id.pid][id.cid]^.flg_last THEN
    Packet[id.pid][id.cid]^.Start := end;
  ELSIF NOT Packet[id.pid][id.cid]^.flg_number THEN
    GetNumber(id,Packet[id.pid][id.cid]^.Start);
    IF NOT InfoDEV[id.pid][id.cid]^.link THEN
      RETURN FALSE;
    END;
  END;
  
  IF begin > end THEN
    IF ((begin>Packet[id.pid][id.cid]^.Start) AND (Packet[id.pid][id.cid]^.Start>end)) OR ((end<Packet[id.pid][id.cid]^.Start) AND (Packet[id.pid][id.cid]^.Start<begin)) OR (9999<Packet[id.pid][id.cid]^.Start) OR (1>Packet[id.pid][id.cid]^.Start) THEN
      NotFoundLine(id,'MESSAGE');
      RETURN FALSE;
    END;
  ELSE
    IF (Packet[id.pid][id.cid]^.Start<begin) OR (end<Packet[id.pid][id.cid]^.Start) THEN
      NotFoundLine(id,'MESSAGE');
      RETURN FALSE;
    END;
  END;
  
  IF Packet[id.pid][id.cid]^.Room <> InfoDEV[id.pid][id.cid]^.call THEN
    IF Packet[id.pid][id.cid]^.flg_call THEN
      MakeUSRfile( buf, Packet[id.pid][id.cid]^.Room, "msg.dir" );
    ELSE
      MakeBBSfile( buf, Packet[id.pid][id.cid]^.Room, "msg.dir" );
    END;
    IF 0 <> Connect(fp,buf,inputoutput) THEN
      NotFoundLine(id,Packet[id.pid][id.cid]^.Room);
      RETURN FALSE;
    END;
    
    IF Packet[id.pid][id.cid]^.Start < begin THEN
      l := 7 + 78 * ( LONG(Packet[id.pid][id.cid]^.Start)+9999-begin );
    ELSE
      l := 7 + 78 * ( LONG(Packet[id.pid][id.cid]^.Start) - begin );
    END;
    
    IF NOT SetFp(fp,l) THEN
      Cannotopen(id,buf);
      Disconnect(fp,TRUE);
      RETURN FALSE;
    END;
    ReadStringStream(fp,buf);
    Disconnect(fp,TRUE);
    c := MatchString(buf,InfoDEV[id.pid][id.cid]^.call);
    IF c = 0 THEN
      NotFoundLine(id,'MESSAGE');
      RETURN FALSE;
    END;
  END;
  RETURN TRUE;
END Owner;

PROCEDURE KillBBS(id:ID);
VAR
  c,begin,end: CARDINAL;
  res: INTEGER;
  l: LONGCARD;
  fp: STREAM;
  buf: LINEBUF;
BEGIN
  
  IF Packet[id.pid][id.cid]^.Room = "MAIL" THEN
    Packet[id.pid][id.cid]^.Room := InfoDEV[id.pid][id.cid]^.call;
    Packet[id.pid][id.cid]^.flg_call := TRUE;
  END;
  
  Packet[id.pid][id.cid]^.flg_p := FALSE;
  IF Packet[id.pid][id.cid]^.Room = 'USER' THEN
    NotFoundLine(id,'MESSAGE');
    RETURN;
  END;
  
  IF Packet[id.pid][id.cid]^.flg_call THEN
    MakeUSRfile( buf, Packet[id.pid][id.cid]^.Room, "msg.idx" );
  ELSE
    MakeBBSfile( buf, Packet[id.pid][id.cid]^.Room, "msg.idx" );
  END;
  GetIndex(buf,begin,end);
  
  IF Packet[id.pid][id.cid]^.flg_last THEN
    Packet[id.pid][id.cid]^.Start := end;
  ELSIF NOT Packet[id.pid][id.cid]^.flg_number THEN
    GetNumber(id,Packet[id.pid][id.cid]^.Start);
    IF NOT InfoDEV[id.pid][id.cid]^.link THEN
      RETURN
    END
  END;
  
  IF begin > end THEN
    IF ((begin>Packet[id.pid][id.cid]^.Start) AND (Packet[id.pid][id.cid]^.Start>end)) OR ((end<Packet[id.pid][id.cid]^.Start) AND (Packet[id.pid][id.cid]^.Start<begin)) OR (9999<Packet[id.pid][id.cid]^.Start) OR (1>Packet[id.pid][id.cid]^.Start) THEN
      NotFoundLine(id,'MESSAGE');
      RETURN;
    END;
  ELSE
    IF (Packet[id.pid][id.cid]^.Start<begin) OR (end<Packet[id.pid][id.cid]^.Start) THEN
      NotFoundLine(id,'MESSAGE');
      RETURN;
    END;
  END;
  
  IF Packet[id.pid][id.cid]^.flg_call THEN
    MakeUSRfile( buf, Packet[id.pid][id.cid]^.Room, "msg.dir" );
  ELSE
    MakeBBSfile( buf, Packet[id.pid][id.cid]^.Room, "msg.dir" );
  END;
  IF 0 <> Connect(fp,buf,inputoutput) THEN
    NotFoundLine(id,Packet[id.pid][id.cid]^.Room);
    RETURN;
  END;
  
  IF Packet[id.pid][id.cid]^.Start < begin THEN
    l := 7 + 78 * ( LONG(Packet[id.pid][id.cid]^.Start)+9999-begin );
  ELSE
    l := 7 + 78 * ( LONG(Packet[id.pid][id.cid]^.Start) - begin );
  END;
  
  IF NOT SetFp(fp,l) THEN
    Cannotopen(id,buf);
    Disconnect(fp,TRUE);
    RETURN;
  END;
  ReadStringStream(fp,buf);
  IF Packet[id.pid][id.cid]^.Room <> InfoDEV[id.pid][id.cid]^.call THEN
    c := MatchString(buf,InfoDEV[id.pid][id.cid]^.call);
    IF c = 0 THEN
      NotFoundLine(id,'MESSAGE');
      Disconnect(fp,TRUE);
      RETURN;
    END;
  END;
  
  DEC(l,7);
  IF SetFp(fp,l) THEN
    WriteChar(fp,'*');
    IF SetFp(fp,l) THEN
      GetStreamLine(fp,buf);
      FixUserLog(buf,Packet[id.pid][id.cid]^.Room,FALSE);
    END
  END;
  Disconnect(fp,TRUE);
  
  WriteLine(id,'[');
  WriteStringLine(id,Packet[id.pid][id.cid]^.Room);
  WriteStringLine(id,'] ÉãÅ[ÉÄÇÃ [');
  WriteCardLine(id,Packet[id.pid][id.cid]^.Start,4,TRUE);
  WriteStringLine(id,'] î‘Çè¡ÇµÇ‹ÇµÇΩ.');
  WriteLnLine(id);
END KillBBS;

PROCEDURE ProfileBBS( id:ID );
VAR
  c, d: CARDINAL;
  s: LSET;
  size: LONGCARD;
  fp: STREAM;
  buf, tmp: LINEBUF;
  idx: TITLE;
BEGIN
  Packet[id.pid][id.cid]^.Room := "USER";
  WriteLnLine(id);
  WriteStringLine(id,'ÉÜÅ[ÉUÅ[ê›íËÇçsÇ¢Ç‹Ç∑.');
  LOOP
    WriteLnLine(id);
    WriteStringLine(id,'  1. ÉwÉãÉvÉåÉxÉãÇÃê›íËÇÇµÇ‹Ç∑');
    WriteLnLine(id);
    WriteStringLine(id,'  2. ñºëOÇ∆èZèäÇìoò^ÇµÇ‹Ç∑');
    WriteLnLine(id);
    WriteStringLine(id,'  3. ÉvÉçÉtÉBÅ[ÉãÇèëÇ´Ç‹Ç∑ (ï∂éöêîÇÕñ≥êßå¿)');
    WriteLnLine(id);
    WriteStringLine(id,'  0. ñﬂÇÈ');
    WriteLnLine(id);
    WriteStringLine(id,'î‘çÜ = ');
    KickLine(id);
    ReadCardLine(id,c);
    IF ( c = 0 ) OR ( NOT InfoDEV[id.pid][id.cid]^.link ) THEN
      RETURN;
    END;
    CASE c OF
    1:
      s := LSET { };
      WriteLnLine(id);
(*      WriteStringLine(id,'ï∂éöÉRÅ[Éhån (0=SJIS 1=ANK 2=EUC) ? :');
      KickLine(id);
      ReadCardLine(id,c);
      IF NOT InfoDEV[id.pid][id.cid]^.link THEN
        RETURN;
      END;
*)
      c := ORD( InfoBBS[id.pid][id.cid]^.group );
      
      WriteStringLine(id,'ÉwÉãÉvï\é¶ (0=Ç†ÇË 1=Ç»Çµ) ? :');
      KickLine(id);
      ReadCardLine(id,d);
      IF NOT InfoDEV[id.pid][id.cid]^.link THEN
        RETURN;
      END;
      IF d = 1 THEN
        s := s + LSET { disphelp }
      END;
      
      WriteStringLine(id,'ÉçÉOÉCÉìéûÇÃÉ`ÉÉÉbÉgèÓïÒ (0=Ç†ÇË 1=Ç»Çµ) ? :');
      KickLine(id);
      ReadCardLine(id,d);
      IF NOT InfoDEV[id.pid][id.cid]^.link THEN
        RETURN;
      END;
      IF d = 1 THEN
        s := s + LSET { dispchat }
      END;
      
      WriteStringLine(id,'ìdïÒÇ∆àÍèèÇ…ÉxÉãÇñ¬ÇÁÇ∑ (0=Ç†ÇË 1=Ç»Çµ) ? :');
      KickLine(id);
      ReadCardLine(id,d);
      IF NOT InfoDEV[id.pid][id.cid]^.link THEN
        RETURN;
      END;
      IF d = 1 THEN
        s := s + LSET { dispbell }
      END;
      
      d := CARDINAL( s );
      
      MakeUSRfile( idx, InfoDEV[id.pid][id.cid]^.call, "user.idx" );
      IF 0 = Connect(fp,idx,inputoutput) THEN
        WriteCardStream(fp,c,4,TRUE);
        WriteChar(fp,09x);
        WriteCardStream(fp,d,4,TRUE);
        WriteLnStream(fp);
        Disconnect(fp,TRUE);
      END;
      
      InfoBBS[id.pid][id.cid]^.group := GROUP(c);
      InfoBBS[id.pid][id.cid]^.level := s;
      WriteStringLine(id,'ÉwÉãÉvÉåÉxÉãÇê›íËÇµÇ‹ÇµÇΩ.');
      WriteLnLine(id);|
    2:
      WriteLnLine(id);
      WriteStringLine(id,'ñºëO: ');
      KickLine(id);
      ReadStringLine(id,buf);
      IF NOT InfoDEV[id.pid][id.cid]^.link THEN
        RETURN;
      END;
      CheckKanji(buf,HIGH(buf));
      WriteStringLine(id,'èZèä: ');
      KickLine(id);
      ReadStringLine(id,tmp);
      IF NOT InfoDEV[id.pid][id.cid]^.link THEN
        RETURN;
      END;
      CheckKanji(tmp,HIGH(tmp));
      MakeUSRfile( idx, InfoDEV[id.pid][id.cid]^.call, "user.idx" );
      IF 0 = Connect(fp,idx,inputoutput) THEN
        GetStreamLine(fp,idx);
        
        WriteStringStream(fp,buf);
        WriteLnStream(fp);
        WriteStringStream(fp,tmp);
        WriteLnStream(fp);
        Disconnect(fp,TRUE);
      END;
      MakeUSRfile( idx, InfoDEV[id.pid][id.cid]^.call, "user.idx" );
      MakeBBSmsg( buf, "USER", InfoBBS[id.pid][id.cid]^.uid );
      MakeTmp( id, tmp );
      MargeProfile( idx, buf, tmp, tmp, FALSE );
      CopyFile( id, tmp, buf );
      c := DeleteFile(tmp);
      WriteStringLine(id,'ñºëOÅAèZèäÇê›íËÇµÇ‹ÇµÇΩ.');
      WriteLnLine(id);|
    3:
      WriteLnLine(id);
      IF TRUE = WriteBoard(id,tmp,size) THEN
        MakeUSRfile( idx, InfoDEV[id.pid][id.cid]^.call, "user.idx" );
        MakeBBSmsg( buf, "USER", InfoBBS[id.pid][id.cid]^.uid );
        MakeTmp( id, tmp );
        MargeProfile( idx, tmp, buf, Packet[id.pid][id.cid]^.Search, TRUE );
        c := DeleteFile(tmp);
        WriteStringLine(id,'ÉvÉçÉtÉBÅ[ÉãÇèëÇ´çûÇ›Ç‹ÇµÇΩ.');
        IF InfoBBS[id.pid][id.cid]^.group = unchecked THEN
          InfoBBS[id.pid][id.cid]^.group := checked;
        END
      END;
      WriteLnLine(id);
    END
  END
END ProfileBBS;

PROCEDURE WriteBBS( id:ID );
VAR
  c,d,begin,end: CARDINAL;
  res: INTEGER;
  size: LONGCARD;
  Call: CALL;
  fp: STREAM;
  t: TimeRec;
  buf,tmp: TITLE;
BEGIN
  IF Packet[id.pid][id.cid]^.Room = "USER" THEN
    ProfileBBS(id);
    RETURN;
  END;
  IF Packet[id.pid][id.cid]^.Room = "MAIL" THEN
    WriteStringLine( id, "à∂ÇƒêÊ: " );
    KickLine( id );
    ReadStringLine( id, buf );
    IF NOT InfoDEV[id.pid][id.cid]^.link THEN
      RETURN;
    END;
    ToUppers( buf );
    Assign( buf, Packet[id.pid][id.cid]^.Room );
    res := FindROOM( Packet[id.pid][id.cid]^.Room );
    IF (res = (-1)) AND IsCall( Packet[id.pid][id.cid]^.Room ) THEN
      Packet[id.pid][id.cid]^.flg_call := TRUE;
    END
  END;
  IF Packet[id.pid][id.cid]^.flg_call THEN
    MakeUSRfile( buf, Packet[id.pid][id.cid]^.Room, "msg.idx" );
  ELSE
    MakeBBSfile( buf, Packet[id.pid][id.cid]^.Room, "msg.idx" );
  END;
  IF NOT Exist(buf) THEN
    NotFoundLine(id,Packet[id.pid][id.cid]^.Room);
    RETURN;
  END;
  
  IF FALSE = WriteBoard(id,tmp,size) THEN
    RETURN
  END
  
  IncIndex( buf, begin, end );
  IF Packet[id.pid][id.cid]^.flg_call THEN
    MakeUSRmsg( buf, Packet[id.pid][id.cid]^.Room, end );
  ELSE
    MakeBBSmsg( buf, Packet[id.pid][id.cid]^.Room, end );
  END;
  CopyFile( id, tmp, buf );
  IF Packet[id.pid][id.cid]^.Com <> x THEN
    c := DeleteFile( tmp );
  END;
  IF Packet[id.pid][id.cid]^.flg_call THEN
    MakeUSRfile( buf, Packet[id.pid][id.cid]^.Room, "msg.dir" );
  ELSE
    MakeBBSfile( buf, Packet[id.pid][id.cid]^.Room, "msg.dir" );
  END;
  c := StoS(InfoDEV[id.pid][id.cid]^.call,Call,TRUE);
  c := StoS(Packet[id.pid][id.cid]^.Search,Packet[id.pid][id.cid]^.Search,TRUE);
  GetDateTime(t);
  
  IF 0 = Connect(fp,buf,inputoutput) THEN
    GoEOS(fp);
    WriteStringStream(fp,'  ');
    WriteCardStream(fp,end,4,TRUE);
    WriteChar(fp,' ');
    WriteStringStream(fp,Call);
    WriteChar(fp,' ');
    WriteTimeStream(fp,t,TRUE);
    WriteLongStream(fp,size,7,FALSE);
    WriteChar(fp,' ');
    WriteStringStream(fp,Packet[id.pid][id.cid]^.Search);
    WriteLnStream(fp);
    Disconnect(fp,TRUE);
  END;
  
  MakeUSRfile( buf, InfoDEV[id.pid][id.cid]^.call, "log.idx" );
  IncIndex( buf, Packet[id.pid][id.cid]^.Start, Packet[id.pid][id.cid]^.Stop );
  MakeUSRfile( buf, InfoDEV[id.pid][id.cid]^.call, "log.dir" );
  c := StoS( Packet[id.pid][id.cid]^.Room, Call, TRUE );
  IF 0 = Connect(fp,buf,inputoutput) THEN
    GoEOS(fp);
    WriteCardStream(fp,Packet[id.pid][id.cid]^.Stop,4,FALSE);
    WriteStringStream(fp,'   ');
    WriteStringStream(fp,Call);
    WriteChar(fp,' ');
    WriteCardStream(fp,end,4,TRUE);
    WriteStringStream(fp,' 0000 ');
    WriteTimeStream(fp,t,FALSE);
    WriteChar(fp,' ');
    WriteStringStream(fp,Packet[id.pid][id.cid]^.Search);
    WriteLnStream(fp);
    Disconnect(fp,TRUE);
  END;
  
  WriteLine(id,'[');
  WriteStringLine(id,Packet[id.pid][id.cid]^.Room);
  WriteLine(id,' ');
  WriteCardLine(id,end,4,TRUE);
  WriteStringLine(id,"] Ç÷ ");
  WriteLongLine(id,size,6,FALSE);
  WriteStringLine(id," ï∂éö èëÇ´çûÇ›Ç‹ÇµÇΩ.");
  WriteLnLine(id);
END WriteBBS;

PROCEDURE CannotXrossPost(id:ID);
BEGIN
  WriteStringLine(id,"[USER] ÇÕÉNÉçÉXÉ|ÉXÉgÇ≈Ç´Ç‹ÇπÇÒ.");
  WriteLnLine(id);
END CannotXrossPost;

PROCEDURE XrossBBS(id:ID);
VAR
  FlgCall, flag: BOOLEAN;
  c, d, start: CARDINAL;
  res: INTEGER;
  room: MINIBUF;
  calls: LINEBUF;
BEGIN
  
  IF Packet[id.pid][id.cid]^.Room = "MAIL" THEN
    Packet[id.pid][id.cid]^.Room := InfoDEV[id.pid][id.cid]^.call;
    Packet[id.pid][id.cid]^.flg_call := TRUE;
  END;
  
  IF NOT Owner(id) THEN
    RETURN;
  END
  flag := TRUE;
  FlgCall := Packet[id.pid][id.cid]^.flg_call;
  room := Packet[id.pid][id.cid]^.Room;
  start := Packet[id.pid][id.cid]^.Start;
  IF NOT Packet[id.pid][id.cid]^.flg_search THEN
    WriteStringLine(id,"ÉNÉçÉXÉ|ÉXÉgëŒè€ÉãÅ[ÉÄ (ÉJÉìÉ}Ç≈ãÊêÿÇÈ. íÜíf = '..')");
    WriteLnLine(id);
    WriteLine(id,'>');
    KickLine(id);
    ReadStringLine(id,calls);
    IF (calls = '..') OR (NOT InfoDEV[id.pid][id.cid]^.link) THEN
      RETURN
    END
  ELSE
    Assign(Packet[id.pid][id.cid]^.Search,calls);
  END;
  c := 0;
  WHILE flag AND (InfoDEV[id.pid][id.cid]^.link) AND (c <= HIGH(calls)) AND (calls[ c ] <> 0x) DO
    d := 0;
    WHILE flag AND (c <= HIGH(calls)) AND (calls[ c ] <> 0x) AND (calls[ c ] <> ' ') AND (calls[ c ] <> '.') AND (calls[ c ] <> ',') AND (calls[ c ] <> 09x) DO
      IF d <= HIGH(Packet[id.pid][id.cid]^.Room) THEN
        Packet[id.pid][id.cid]^.Room[ d ] := calls[ c ];
        INC( d );
      END;
      INC( c );
    END;
    IF calls[ c ] = 0x THEN
      flag := FALSE;
    END;
    IF d <= HIGH(Packet[id.pid][id.cid]^.Room) THEN
      Packet[id.pid][id.cid]^.Room[ d ] := 0x;
    END;
    IF FlgCall THEN
      MakeUSRmsg( Packet[id.pid][id.cid]^.Search, room, start );
    ELSE
      MakeBBSmsg( Packet[id.pid][id.cid]^.Search, room, start );
    END;
    ToUppers( Packet[id.pid][id.cid]^.Room );
    res := FindROOM( Packet[id.pid][id.cid]^.Room );
    IF Packet[id.pid][id.cid]^.Room = "USER" THEN
      CannotXrossPost(id);
    ELSIF (res <> -1) OR IsCall( Packet[id.pid][id.cid]^.Room ) THEN
      IF res <> -1 THEN
        Packet[id.pid][id.cid]^.flg_call := FALSE;
        Packet[id.pid][id.cid]^.Room := InfoROOM[ res ]^.RoomName;
      ELSE
        Packet[id.pid][id.cid]^.flg_call := TRUE;
      END;
      WriteBBS(id);
    ELSE
      NotFoundLine(id,Packet[id.pid][id.cid]^.Room);
    END;
    INC( c );
  END;
END XrossBBS;

PROCEDURE Condition1( id:ID; VAR buf:LINEBUF ): BOOLEAN;
BEGIN
  IF  ( Packet[id.pid][id.cid]^.Com = access ) OR
    Packet[id.pid][id.cid]^.flg_delete OR
    ( (Packet[id.pid][id.cid]^.Com = log) AND (buf[5] <> '*') ) OR
    ( ((Packet[id.pid][id.cid]^.Com = files) OR (Packet[id.pid][id.cid]^.Com = read)) AND (buf[0] <> '*') )
  THEN
    RETURN TRUE
  ELSE
    RETURN FALSE
  END
END Condition1;

PROCEDURE Condition2( id:ID; VAR buf:LINEBUF ): BOOLEAN;
BEGIN
  IF (Packet[id.pid][id.cid]^.flg_search=FALSE) OR (Pos(Packet[id.pid][id.cid]^.Search,buf,0) <= HIGH(buf)) THEN
    RETURN TRUE
  ELSE
    RETURN FALSE
  END;
END Condition2;

PROCEDURE Condition3( id:ID; VAR buf:LINEBUF ): BOOLEAN;
VAR
  tmp: MINIBUF;
BEGIN
  IF NOT Packet[id.pid][id.cid]^.flg_call THEN
    RETURN TRUE
  END;
  IF InfoBBS[id.pid][id.cid]^.group = root THEN
    RETURN TRUE
  END;
  IF Packet[id.pid][id.cid]^.Room = InfoDEV[id.pid][id.cid]^.call THEN
    RETURN TRUE
  END;
  Copy( buf, 7, 6, tmp );
  tmp[ 6 ] := 0x;
  TailCut( tmp );
  IF (tmp = InfoDEV[id.pid][id.cid]^.call) AND (tmp <> "GUEST") THEN
    RETURN TRUE
  END;
  RETURN FALSE
END Condition3;


PROCEDURE FilesBBS( id:ID );
VAR
  FlgDisp, FlgRn: BOOLEAN;
  step,c,d,begin,end:CARDINAL;
  res:INTEGER;
  l,m,n:LONGCARD;
  fp:STREAM;
  buf:LINEBUF;
BEGIN
  
  IF Packet[id.pid][id.cid]^.Room = "MAIL" THEN
    Packet[id.pid][id.cid]^.Room := InfoDEV[id.pid][id.cid]^.call;
    Packet[id.pid][id.cid]^.flg_call := TRUE;
  END;
  
  IF Packet[id.pid][id.cid]^.flg_search AND (NOT Packet[id.pid][id.cid]^.flg_number) AND (NOT Packet[id.pid][id.cid]^.flg_last) THEN
    Packet[id.pid][id.cid]^.flg_number := TRUE;
    Packet[id.pid][id.cid]^.flg_all := TRUE;
    Packet[id.pid][id.cid]^.flg_p := TRUE;
  END;
  
  IF (Packet[id.pid][id.cid]^.Com = files) OR (Packet[id.pid][id.cid]^.Com = read) THEN
    IF Packet[id.pid][id.cid]^.flg_call THEN
      MakeUSRfile( buf, Packet[id.pid][id.cid]^.Room, "msg.idx" );
    ELSE
      MakeBBSfile( buf, Packet[id.pid][id.cid]^.Room, "msg.idx" );
    END;
  ELSIF Packet[id.pid][id.cid]^.Com = log THEN
    MakeUSRfile( buf, InfoDEV[id.pid][id.cid]^.call, "log.idx" );
  ELSIF Packet[id.pid][id.cid]^.Com = access THEN
    MakeDNETfile( buf, "log\msg.idx" );
  END;
  IF NOT Exist( buf ) THEN
    NotFoundLine(id,Packet[id.pid][id.cid]^.Room);
    RETURN;
  ELSE
    GetIndex( buf, begin, end );
    IF begin = 0 THEN
      NotFoundLine(id,"MESSAGE");
      RETURN;
    END;
  END;
  IF Packet[id.pid][id.cid]^.flg_number = FALSE THEN
    IF Packet[id.pid][id.cid]^.flg_last = TRUE THEN
      Packet[id.pid][id.cid]^.Start := end;
      Packet[id.pid][id.cid]^.Stop := end;
    ELSE
      IF (Packet[id.pid][id.cid]^.Com = files) OR (Packet[id.pid][id.cid]^.Com = log) OR (Packet[id.pid][id.cid]^.Com = access) THEN
        IF (begin > end) AND ((end+9999-begin+1) > PAGE) THEN
          Packet[id.pid][id.cid]^.Start := end+9999-PAGE+1;
        ELSIF (begin < end) AND ((end-begin+1) > PAGE) THEN
          Packet[id.pid][id.cid]^.Start := end-PAGE+1;
        ELSE
          Packet[id.pid][id.cid]^.Start := begin;
        END;
        Packet[id.pid][id.cid]^.Stop := end;
      ELSIF Packet[id.pid][id.cid]^.Com = read THEN
        GetNumber(id,Packet[id.pid][id.cid]^.Start);
        IF NOT InfoDEV[id.pid][id.cid]^.link THEN
          RETURN;
        END;
        Packet[id.pid][id.cid]^.Stop := Packet[id.pid][id.cid]^.Start;
      END;
    END;
  ELSE
    IF Packet[id.pid][id.cid]^.flg_last = TRUE THEN
      Packet[id.pid][id.cid]^.Stop := end;
    END;
  END;
  IF Packet[id.pid][id.cid]^.flg_all = TRUE THEN
    Packet[id.pid][id.cid]^.Start := begin;
    Packet[id.pid][id.cid]^.Stop := end;
  END;
  
  IF begin > end THEN
    IF ((begin>Packet[id.pid][id.cid]^.Start) AND (Packet[id.pid][id.cid]^.Start>end)) OR ((end<Packet[id.pid][id.cid]^.Stop) AND (Packet[id.pid][id.cid]^.Stop<begin)) OR (9999<Packet[id.pid][id.cid]^.Start) OR (1>Packet[id.pid][id.cid]^.Stop) THEN
      NotFoundLine(id,'MESSAGE');
      RETURN;
    END;
  ELSE
    IF (Packet[id.pid][id.cid]^.Start<begin) OR (end<Packet[id.pid][id.cid]^.Stop) THEN
      NotFoundLine(id,'MESSAGE');
      RETURN;
    END;
  END;
  
  IF (Packet[id.pid][id.cid]^.Com = files) OR (Packet[id.pid][id.cid]^.Com = read) THEN
    IF Packet[id.pid][id.cid]^.flg_call THEN
      MakeUSRfile( buf, Packet[id.pid][id.cid]^.Room, "msg.dir" );
    ELSE
      res := FindROOM(Packet[id.pid][id.cid]^.Room);
      IF (InfoROOM[res]^.RoomType >= 3) AND (InfoBBS[id.pid][id.cid]^.group = unchecked) THEN
        WriteStringLine(id,"ÉVÉXÉIÉyÇ™ÉÜÅ[ÉUÅ[ìoò^ÇÉ`ÉFÉbÉNÇ∑ÇÈÇ‹Ç≈èoóàÇ‹ÇπÇÒ.");
        WriteLnLine(id);
        RETURN;
      ELSIF (Packet[id.pid][id.cid]^.Com = read) AND (InfoROOM[res]^.RoomType >= 2) AND (NOT CheckTime()) THEN
        MakeDNETfile( buf, "msg\limit" );
        CatSJANK( id, buf );
        IF PutFileLine( id, buf, 0 ) THEN
        END;
        RETURN;
      END;
      MakeBBSfile( buf, Packet[id.pid][id.cid]^.Room, "msg.dir" );
    END
  ELSIF Packet[id.pid][id.cid]^.Com = log THEN
    MakeUSRfile( buf, InfoDEV[id.pid][id.cid]^.call, "log.dir" );
  ELSIF Packet[id.pid][id.cid]^.Com = access THEN
    MakeDNETfile( buf, "log\msg.dir" );
  END;
  IF 0 <> Connect(fp,buf,inputoutput) THEN
    NotFoundLine(id,'MESSAGE');
    RETURN;
  END;
  IF (Packet[id.pid][id.cid]^.Com = files) OR (Packet[id.pid][id.cid]^.Com = read) THEN
    IF Packet[id.pid][id.cid]^.Room = 'USER' THEN
      step := 44;
    ELSE
      step := 78;
    END;
  ELSIF Packet[id.pid][id.cid]^.Com = log THEN
    step := 75;
  ELSIF Packet[id.pid][id.cid]^.Com = access THEN
    step := 60;
  END;
  
  IF Packet[id.pid][id.cid]^.Start < begin THEN
    l := LONG(step)*(LONG(Packet[id.pid][id.cid]^.Start)+9999-begin);
  ELSE
    l := LONG(step)*(LONG(Packet[id.pid][id.cid]^.Start)-begin);
  END;
  IF Packet[id.pid][id.cid]^.Start > Packet[id.pid][id.cid]^.Stop THEN
    c := Packet[id.pid][id.cid]^.Stop+9999-Packet[id.pid][id.cid]^.Start;
  ELSE
    c := Packet[id.pid][id.cid]^.Stop-Packet[id.pid][id.cid]^.Start;
  END;
  d := c+1;
  
  IF Packet[id.pid][id.cid]^.Com = files THEN
    WriteLnLine(id);
    WriteStringLine(id,'ÉãÅ[ÉÄ ');
    WriteStringLine(id,Packet[id.pid][id.cid]^.Room);
    WriteLnLine(id);
  END;
  IF Packet[id.pid][id.cid]^.Com = files THEN
    IF Packet[id.pid][id.cid]^.Room = 'USER' THEN
      WriteStringLine(id,' No. ñºëO   èââÒì˙ït  ëOâÒì˙ït éûä‘   âÒêî');
    ELSE
      WriteStringLine(id,'   No. ñºëO   ì˙ït     éûä‘  ï∂éöêî É^ÉCÉgÉã');
    END;
    WriteLnLine(id);
  ELSIF Packet[id.pid][id.cid]^.Com = log THEN
    WriteLnLine(id);
    WriteStringLine(id, " No.   î≠êMêÊ î‘çÜ ämîF ì˙ït     É^ÉCÉgÉã" );
    WriteLnLine(id);
  ELSIF Packet[id.pid][id.cid]^.Com = access THEN
    WriteLnLine(id);
    WriteStringLine(id, " No.    ÉRÅ[ÉãÉTÉCÉì   ì˙ït   éûçè óòópéûä‘ PI CI éÌï ");
    WriteLnLine(id);
  END;
  
  IF NOT SetFp(fp,l) THEN
    Cannotopen( id, buf );
    Disconnect( fp, TRUE );
    RETURN;
  END;
  LOOP
    WHILE NOT EOS(fp) DO
      IF NOT InfoDEV[id.pid][id.cid]^.link THEN
        EXIT;
      END;
      IF BusyLine(id) THEN
        ReadStringLine( id, buf );
        IF NOT InfoDEV[id.pid][id.cid]^.link THEN
          EXIT;
        END;
        IF buf = '..' THEN
          WriteChudanLine(id);
          EXIT;
        END
      END
      GetLongPos(fp,n);
      GetStreamLine(fp,buf);
      IF Condition1(id,buf) AND Condition2(id,buf) AND Condition3(id,buf) THEN
        FlgDisp := TRUE;
        IF (Packet[id.pid][id.cid]^.Com = files) OR (Packet[id.pid][id.cid]^.Com = log) OR (Packet[id.pid][id.cid]^.Com = access) THEN
          TailCut(buf);
          WriteStringLine(id,buf);
          WriteLnLine(id);
          IF Packet[id.pid][id.cid]^.flg_search THEN
            KickLine(id);
          END;
        ELSIF Packet[id.pid][id.cid]^.Com = read THEN
          IF Packet[id.pid][id.cid]^.flg_rn THEN
            FlgRn := TRUE
          ELSE
            FlgRn := FALSE
          END;
          IF ReadBoard(id,buf) THEN
            FixUserLog(buf,Packet[id.pid][id.cid]^.Room,TRUE);
            IF Packet[id.pid][id.cid]^.Room = InfoDEV[id.pid][id.cid]^.call THEN
              GetLongPos(fp,m);
              IF SetFp(fp,n) THEN
                WriteChar(fp,'R')
              END;
              IF SetFp(fp,m) THEN
              END
            END
            res := FindROOM(Packet[id.pid][id.cid]^.Room);
            IF (res <> -1) AND (PortType[ id.pid ] >= 2) AND (InfoROOM[ res ]^.RoomType >= 4) THEN
              InfoBBS[id.pid][id.cid]^.result := 3;
              WriteStringLine(id,"[SYSOP]: Ç±ÇÃÉ|Å[ÉgÇÕòAë±É_ÉEÉìÉçÅ[ÉhÇ≈Ç´Ç‹ÇπÇÒ. ÉçÉOÉAÉEÉgÇµÇƒâ∫Ç≥Ç¢.");
              WriteLnLine(id);
	      EXIT;
            END;
          END
          IF FlgRn AND (NOT Packet[id.pid][id.cid]^.flg_rn) THEN
            EXIT
          END
        END
      ELSE
        FlgDisp := FALSE;
        WaitLine(id);
      END;
      IF c = 0 THEN
        EXIT;
      END;
      IF (Packet[id.pid][id.cid]^.flg_p=FALSE) AND (((Packet[id.pid][id.cid]^.Com = read) AND FlgDisp) OR ((d-c)<>0) AND (((d-c) MOD PAGE)=0)) THEN
        IF (Packet[id.pid][id.cid]^.Com = files) OR (Packet[id.pid][id.cid]^.Com = log) OR (Packet[id.pid][id.cid]^.Com = access) THEN
          res := More(id,(c DIV PAGE)+1,(d DIV PAGE)+1)
        ELSIF Packet[id.pid][id.cid]^.Com = read THEN
          res := More(id,c,d)
        END;
        IF res = (-1) THEN
          EXIT;
        ELSE
          IF (Packet[id.pid][id.cid]^.Com = files) OR (Packet[id.pid][id.cid]^.Com = log) OR (Packet[id.pid][id.cid]^.Com = access) THEN
            IF c > PAGE * CARDINAL( res ) THEN
              DEC( c, PAGE * res );
            ELSE
              c := 0;
            END;
          ELSIF Packet[id.pid][id.cid]^.Com = read THEN
            IF c > CARDINAL( res ) THEN
              DEC( c, res );
            ELSE
              c := 0;
            END;
          END;
          IF (c > 0) AND (NOT SetFp(fp,l+LONG(step)*LONG(d-c))) THEN
            Cannotopen(id,'dir file');
            EXIT;
          END;
        END;
      END;
      IF c = 0 THEN
        EXIT;
      END;
      DEC( c );
    END;
    EXIT;
  END;
  Disconnect(fp,TRUE);
  
END FilesBBS;

PROCEDURE NewBBS( id:ID );
VAR
  FlgFound: BOOLEAN;
  flags: ComFlags;
  i,c,d,r: CARDINAL;
  j: INTEGER;
  fp:STREAM;
  index: RoomIndex;
  room:MINIBUF;
  buf:TITLE;
BEGIN
  
  IF (Packet[id.pid][id.cid]^.Com <> biff) AND (Packet[id.pid][id.cid]^.flg_room) AND (Packet[id.pid][id.cid]^.Room <> "MAIL") THEN
    IF Packet[id.pid][id.cid]^.flg_call THEN
      MakeUSRfile( buf, Packet[id.pid][id.cid]^.Room, "msg.idx" );
    ELSE
      MakeBBSfile( buf, Packet[id.pid][id.cid]^.Room, "msg.idx" );
    END;
    IF NOT Exist( buf ) THEN
      NotFoundLine(id,Packet[id.pid][id.cid]^.Room);
      RETURN;
    END;
  END;
  
  IF Packet[id.pid][id.cid]^.Com = new THEN
    WriteStringLine(id,"[");
    WriteTimeLine(id,InfoBBS[id.pid][id.cid]^.last);
    WriteStringLine(id,"] à»å„ÇÃÉÅÉbÉZÅ[ÉWÇÕéüÇÃÇ∆Ç®ÇËÇ≈Ç∑.");
    WriteLnLine(id);
  END;
  
  IF (Packet[id.pid][id.cid]^.Com <> biff) AND (InfoBBS[id.pid][id.cid]^.cons = 1) THEN
    WriteLnLine(id);
    WriteStringLine(id,"êVÇµÇ¢ÉÅÉbÉZÅ[ÉWÇÕÇ†ÇËÇ‹ÇπÇÒ.");
    WriteLnLine(id);
    RETURN;
  END
  
  GetRoomIndex( id, index );
  MakeUSRfile( buf, InfoDEV[id.pid][id.cid]^.call, "room.idx" );
  
  flags.Com := Packet[id.pid][id.cid]^.Com;
  flags.flg_all := Packet[id.pid][id.cid]^.flg_all;
  flags.flg_whole := Packet[id.pid][id.cid]^.flg_whole;
  flags.flg_number := Packet[id.pid][id.cid]^.flg_number;
  flags.flg_room := Packet[id.pid][id.cid]^.flg_room;
  flags.flg_p := Packet[id.pid][id.cid]^.flg_p;
  flags.flg_delete := Packet[id.pid][id.cid]^.flg_delete;
  flags.flg_search := Packet[id.pid][id.cid]^.flg_search;
  flags.flg_last := Packet[id.pid][id.cid]^.flg_last;
  flags.flg_call := Packet[id.pid][id.cid]^.flg_call;
  room := Packet[id.pid][id.cid]^.Room;
  
  IF Packet[id.pid][id.cid]^.Com = rn THEN
    Packet[id.pid][id.cid]^.flg_rn := TRUE
  END;
  
  FlgFound := FALSE;
  IF 0 = Connect(fp,buf,input) THEN
    GetStreamLine(fp,buf);
    i := 0;
    IF InfoBBS[id.pid][id.cid]^.group = root THEN
      r := Rooms + 1;
    ELSE
      r := Rooms;
    END;
    WHILE InfoDEV[id.pid][id.cid]^.link AND (NOT EOS(fp)) AND (i <= r) AND ((flags.Com <> rn) OR Packet[id.pid][id.cid]^.flg_rn) DO
      ReadStringStream(fp,buf);
      j := FindROOM(buf);
      ReadCardStream(fp,c);
      IF j = (-1) THEN
        IF 0 = CompareStr(buf,EnvCALL) THEN
          j := Rooms+1;
          IF c > index[j] THEN
            d := index[j]+9999-c;
          ELSE
            d := index[j]-c;
          END;
        ELSE
          d := 0;
        END;
      ELSE
        IF c > index[j] THEN
          d := index[j]+9999-c;
        ELSE
          d := index[j]-c;
        END;
      END;
      IF (d > 0) AND (d < 5000) AND (NOT ((flags.Com = rn) AND (InfoROOM[j]^.RoomType >= 1))) THEN
        IF (flags.Com = new) AND flags.flg_all AND (NOT FlgFound) THEN
          FlgFound := TRUE;
          WriteLnLine(id);
          WriteStringLine(id,"ÉãÅ[ÉÄñº  ÉÅÉbÉZÅ[ÉW       åèêî");
          WriteLnLine(id);
        END;
        IF (flags.Com = biff) OR ((flags.Com = new) AND flags.flg_all) THEN
          IF (flags.Com = biff) AND ((InfoROOM[j]^.RoomName = 'INFO') OR (InfoROOM[j]^.RoomName = "MAIL") OR (CARDINAL(j) = Rooms+1)) THEN
            IF InfoROOM[j]^.RoomName = "INFO" THEN
              WriteStringLine(id,"[Ç®ímÇÁÇπÇ™");
            ELSIF InfoROOM[j]^.RoomName = "MAIL" THEN
              WriteStringLine(id,"[ÉÅÅ[ÉãÇ™  ");
            ELSIF CARDINAL(j) = Rooms+1 THEN
              WriteStringLine(id,"[ÇrÉÅÅ[ÉãÇ™");
            END;
            IF c > index[j] THEN
              d := index[j]+9999-c;
            ELSE
              d := index[j]-c;
            END;
            WriteCardLine(id,d,4,FALSE);
            WriteStringLine(id," åèÇ†ÇËÇ‹Ç∑]: ");
          END;
          IF (flags.Com = new) OR ((flags.Com = biff) AND ((InfoROOM[j]^.RoomName = 'INFO') OR (InfoROOM[j]^.RoomName = "MAIL") OR (CARDINAL(j) = Rooms+1))) THEN
            d := StoS(InfoROOM[j]^.RoomName,room,TRUE);
            WriteStringLine(id,room);
            WriteLine(id,' ');
            IF c = 9999 THEN
              d := 1;
            ELSE
              d := c+1;
            END;
            WriteCardLine(id,d,4,TRUE);
            WriteStringLine(id,' --> ');
            WriteCardLine(id,index[j],4,TRUE);
            IF flags.Com = new THEN
              WriteStringLine(id,'  : ');
              IF c > index[j] THEN
                d := index[j]+9999-c;
              ELSE
                d := index[j]-c;
              END;
              WriteCardLine(id,d,4,FALSE);
            END
            WriteLnLine(id);
          END;
        ELSIF flags.flg_all OR flags.flg_whole OR (FindROOM(room) = INTEGER(j)) OR ((buf = "MAIL") AND (room = InfoDEV[id.pid][id.cid]^.call)) OR ((CARDINAL(j) = Rooms+1) AND (0 = CompareStr(room,EnvCALL))) THEN
          FlgFound := TRUE;
          Packet[id.pid][id.cid]^.Room := InfoROOM[j]^.RoomName;
          IF CARDINAL(j) = Rooms+1 THEN
            Packet[id.pid][id.cid]^.flg_call := TRUE;
          ELSE
            Packet[id.pid][id.cid]^.flg_call := FALSE;
          END;
          Packet[id.pid][id.cid]^.flg_room := TRUE;
          Packet[id.pid][id.cid]^.flg_all := FALSE;
          Packet[id.pid][id.cid]^.flg_whole := FALSE;
          Packet[id.pid][id.cid]^.flg_number := TRUE;
          IF c = 9999 THEN
            Packet[id.pid][id.cid]^.Start := 1;
          ELSE
            Packet[id.pid][id.cid]^.Start := c+1;
          END;
          Packet[id.pid][id.cid]^.Stop := index[j];
          IF flags.Com = new THEN
            Packet[id.pid][id.cid]^.Com := files;
          ELSIF flags.Com = rn THEN
            Packet[id.pid][id.cid]^.flg_p := TRUE;
            Packet[id.pid][id.cid]^.Com := read;
          END;
          FilesBBS(id);
        END;
      END;
      
      INC( i );
    END;
    Disconnect(fp,TRUE);
  END;
  IF InfoDEV[id.pid][id.cid]^.link AND (flags.Com <> biff) AND (NOT FlgFound) THEN
    WriteLnLine(id);
    WriteStringLine(id,"êVÇµÇ¢ÉÅÉbÉZÅ[ÉWÇÕÇ†ÇËÇ‹ÇπÇÒ.");
    WriteLnLine(id);
  END
END NewBBS;

PROCEDURE TaskBBS(id:ID);
VAR
  i,j:BYTE;
BEGIN
  WriteLnLine(id);
  WriteStringLine(id,'åªç›ÉAÉNÉeÉBÉuÇ»É^ÉXÉN');
  WriteLnLine(id);
  WriteLnLine(id);
  WriteStringLine(id,'í[ññ óDêÊìx ÉoÉbÉtÉ@ êßå¿ PID CID');
  WriteLnLine(id);
  FOR i := 0 TO Ports DO
    WriteStringLine(id,DevStr[ Did[i] ]);
    WriteStringLine(id,'   ');
    WriteCardLine(id,Priority[i],4,TRUE);
    WriteStringLine(id,'    ');
    WriteCardLine(id,PortBufSize[i],4,TRUE);
    WriteStringLine(id,'    ');
    WriteCardLine(id,PortType[i],2,TRUE);
    WriteStringLine(id,'  ');
    WriteCardLine(id,ORD(i),2,TRUE);
    WriteStringLine(id,'  ');
    FOR j := 0 TO Chans[i] DO
      WriteCardLine(id,ORD(j),2,TRUE);
      WriteLine(id,' ');
    END;
    WriteLnLine(id);
  END;
  WriteLnLine(id);
END TaskBBS;

PROCEDURE SetBBS(id:ID);
VAR
  fp: STREAM;
  buf: TITLE;
BEGIN
  MakeDNETfile( buf, "msg\limit" );
  CatSJANK(id,buf);
  IF PutFileLine(id,buf,0) THEN
  END
END SetBBS;

PROCEDURE HelpBBS(id:ID);
VAR
  c, d: CARDINAL;
  res: INTEGER;
  Com: COM;
  buf: TITLE;
BEGIN
  IF Packet[id.pid][id.cid]^.Room = 'ROOM' THEN
    RoomBBS(id);
    WriteStringLine(id,'(ÉãÅ[ÉÄÇÃè–âÓÇÕÅAH BBS, H MAIL, H USER...ÇÃÇÊÇ§Ç…ÇµÇƒÇ‡å©ÇÍÇ‹Ç∑)');
    WriteLnLine(id);
    WriteStringLine(id,'(ÉãÅ[ÉÄÇÃè–âÓ= î‘çÜ, ÉãÅ[ÉÄÇ…ì¸ÇÈ= ÉãÅ[ÉÄñº, ñﬂÇÈ= ÉäÉ^Å[Éì):');
    KickLine(id);
    ReadStringLine(id,buf);
    IF NOT InfoDEV[id.pid][id.cid]^.link THEN
      RETURN;
    END;
    ToUppers(buf);
    res := FindROOM(buf);
    IF res<>(-1) THEN
      Assign(InfoROOM[res]^.RoomName,InfoBBS[id.pid][id.cid]^.CurrentROOM);
      RETURN;
    END;
    d := AtoC(buf,0,c);
    IF (c>=1) AND (c<=Rooms+1) THEN
      CatENV( buf, '\msg\' );
      CatCat(buf,InfoROOM[c-1]^.RoomName);
      CatSJANK(id,buf);
      IF PutFileLine(id,buf,0) THEN
      END
    END;
    RETURN;
  END;
  
  IF Packet[id.pid][id.cid]^.flg_room = FALSE THEN
    Packet[id.pid][id.cid]^.Room := 'HELP';
    CatENV( buf, '\msg\help' );
  ELSE
    Com := FindCOM(Packet[id.pid][id.cid]^.Room);
    res := FindROOM(Packet[id.pid][id.cid]^.Room);
    IF Com <> nein THEN
      IF Com = room THEN
        Packet[id.pid][id.cid]^.Room := 'ROOM';
        Packet[id.pid][id.cid]^.flg_room := TRUE;
        HelpBBS(id);
        RETURN;
      END;
      Packet[id.pid][id.cid]^.Room := ComStr[ ORD(Com) ];
    ELSIF res <> (-1) THEN
      Packet[id.pid][id.cid]^.Room := InfoROOM[ res ]^.RoomName;
    ELSIF IsCall( Packet[id.pid][id.cid]^.Room ) THEN
      MakeUSRfile( buf, Packet[id.pid][id.cid]^.Room, "room.idx" );
      
(*      WriteString(buf);
      WriteLn;
*)
      IF Exist(buf) THEN
        GetIndex(buf,c,d);
        Packet[id.pid][id.cid]^.Room := "USER";
        Packet[id.pid][id.cid]^.flg_call := FALSE;
        Packet[id.pid][id.cid]^.flg_number := TRUE;
        Packet[id.pid][id.cid]^.Start := c;
        Packet[id.pid][id.cid]^.Stop := c;
        Packet[id.pid][id.cid]^.Com := read;
        FilesBBS(id);
        RETURN;
      ELSE
        NotFoundLine(id,'MESSAGE');
        RETURN;
      END;
    ELSE
      NotFoundLine(id,Packet[id.pid][id.cid]^.Room);
      RETURN;
    END;
    CatENV( buf, '\msg\' );
    CatCat(buf,Packet[id.pid][id.cid]^.Room);
  END;
  CatSJANK(id,buf);
  IF NOT Exist(buf) THEN
    NotFoundLine(id,"MESSAGE");
    RETURN;
  ELSE
    IF PutFileLine(id,buf,0) THEN
    END
    IF NOT InfoDEV[id.pid][id.cid]^.link THEN
      RETURN;
    END;
  END;
  
  IF Packet[id.pid][id.cid]^.Room = 'HELP' THEN
    WriteStringLine(id,'(ÉRÉ}ÉìÉhÇÃê‡ñæ= î‘çÜ, ñﬂÇÈ= ÉäÉ^Å[Éì):');
    KickLine(id);
    ReadCardLine(id,c);
    IF NOT InfoDEV[id.pid][id.cid]^.link THEN
      RETURN;
    END;
    IF c = 1 THEN
      Packet[id.pid][id.cid]^.Room := 'GUIDE';
      Packet[id.pid][id.cid]^.flg_room := TRUE;
      HelpBBS(id);
      RETURN;
    END;
    IF c = 2 THEN
      Packet[id.pid][id.cid]^.Room := 'ROOM';
      Packet[id.pid][id.cid]^.flg_room := TRUE;
      HelpBBS(id);
      RETURN;
    END;
    IF (c>=3) AND (c<=COMS) THEN
      c := c-2;
      CatENV( buf, '\msg\' );
      CatCat(buf,ComStr[c]);
      CatSJANK(id,buf);
      IF PutFileLine(id,buf,0) THEN
      END
      IF NOT InfoDEV[id.pid][id.cid]^.link THEN
        RETURN;
      END;
    END;
  END;
END HelpBBS;

PROCEDURE ByebyeBBS(id:ID);
VAR
  c,d: CARDINAL;
BEGIN
  IF (InfoBBS[id.pid][id.cid]^.group <> root) OR (NOT Packet[id.pid][id.cid]^.flg_call) OR (NOT Packet[id.pid][id.cid]^.flg_number) THEN
    RETURN;
  END;
  c := Packet[id.pid][id.cid]^.Start;
  d := Packet[id.pid][id.cid]^.Stop;
  IF (c > ORD(Ports)) OR (d > ORD(Chans[c])) THEN
    RETURN;
  END;
  IF InfoDEV[c][d]^.call <> Packet[id.pid][id.cid]^.Room THEN
    RETURN;
  END;
  InfoDEV[c][d]^.link := FALSE;
  WriteStringLine(id,"ã≠êßÉfÉBÉXÉRÉlÉNÉgé¿çs: ÉÜÅ[ÉUÅ[ [");
  WriteStringLine(id,Packet[id.pid][id.cid]^.Room);
  WriteStringLine(id,"] PID=");
  WriteCardLine(id,Packet[id.pid][id.cid]^.Start,2,TRUE);
  WriteStringLine(id," CID=");
  WriteCardLine(id,Packet[id.pid][id.cid]^.Stop,2,TRUE);
  WriteLnLine(id);
END ByebyeBBS;

PROCEDURE FileupBBS(id:ID);
VAR
  ch: CHAR;
  fp: STREAM;
  dir: TITLE;
  buf: LINEBUF;
BEGIN
  IF InfoBBS[id.pid][id.cid]^.group <> root THEN
    RETURN;
  END;
  WriteStringLine(id,"ÉtÉ@ÉCÉãñº: ");
  KickLine(id);
  ReadStringLine(id,dir);
  IF NOT InfoDEV[id.pid][id.cid]^.link THEN
    RETURN;
  END;
  IF 0 <> Connect( fp, dir, output ) THEN
    Cannotopen( id, dir );
    RETURN;
  END;
  LOOP
    ReadStringLine(id,buf);
    IF (buf = '.') OR (NOT InfoDEV[id.pid][id.cid]^.link) THEN
      EXIT;
    END;
    WriteStringStream(fp,buf);
    WriteLnStream(fp);
  END;
  Disconnect(fp,TRUE);
  WriteStringLine(id,"ÉAÉbÉvÉçÅ[Éh. [");
  WriteStringLine(id,dir);
  WriteLine(id,']');
  WriteLnLine(id);
END FileupBBS;

PROCEDURE ChkusrBBS(id:ID);
VAR
  c,d: CARDINAL;
  fp: STREAM;
  idx: TITLE;
BEGIN
  IF (InfoBBS[id.pid][id.cid]^.group <> root) OR (NOT Packet[id.pid][id.cid]^.flg_call) THEN
    RETURN;
  END;
  MakeUSRfile( idx, Packet[id.pid][id.cid]^.Room, "user.idx" );
  GetIndex(idx,c,d);
  IF 0 = Connect(fp,idx,inputoutput) THEN
    IF Packet[id.pid][id.cid]^.flg_p THEN
      WriteStringLine(id, "ãtÉ`ÉFÉbÉN. ÉÜÅ[ÉUÅ[ [");
      c := ORD( unchecked );
    ELSE
      WriteStringLine(id, "É`ÉFÉbÉN. ÉÜÅ[ÉUÅ[ [");
      c := ORD( checked );
    END;
    WriteStringLine(id, Packet[id.pid][id.cid]^.Room );
    WriteLine(id,']');
    WriteLnLine(id);
    WriteCardStream(fp,c,4,TRUE);
    WriteChar(fp,09x);
    WriteCardStream(fp,d,4,TRUE);
    WriteLnStream(fp);
    Disconnect(fp,TRUE);
  ELSE
    Cannotopen(id,idx);
  END;
END ChkusrBBS;

PROCEDURE SuBBS(id:ID);
VAR
  c,d: CARDINAL;
  fp: STREAM;
  idx: TITLE;
BEGIN
  IF (InfoBBS[id.pid][id.cid]^.group <> root) OR (NOT Packet[id.pid][id.cid]^.flg_call) THEN
    RETURN;
  END;
  MakeUSRfile( idx, Packet[id.pid][id.cid]^.Room, "user.idx" );
  IF Exist( idx ) THEN
    InfoDEV[id.pid][id.cid]^.call := Packet[id.pid][id.cid]^.Room;
    WriteStringLine(id,"Ç†Ç»ÇΩÇÕ [");
    WriteStringLine( id, Packet[id.pid][id.cid]^.Room );
    WriteStringLine( id, "] Ç≈Ç∑. [31míçà”!! ïKÇ∏é©ï™ÇÃÉRÅ[ÉãÇ…ñﬂÇ¡ÇƒÉçÉOÉAÉEÉgÇ∑ÇÈÇ±Ç∆!![m" );
    WriteLnLine(id);
  ELSE
    WriteLine(id,'[');
    WriteStringLine( id, Packet[id.pid][id.cid]^.Room );
    WriteStringLine( id, "] Ç™å©Ç¬Ç©ÇËÇ‹ÇπÇÒ" );
    WriteLnLine(id);
  END;
END SuBBS;


(*  ÉRÉ}ÉìÉhåQ -- Ç®ÇÌÇË  *)




(*  ÉgÉbÉvÉåÉxÉãÇ©ÇÁåƒÇ—èoÇ≥ÇÍÇÈÉvÉçÉVÉWÉÉåQ -- ÇÕÇ∂Çﬂ  *)

PROCEDURE GetLoggedinTime(id:ID; VAR span:TimeRec);
VAR
  year, month, day, hour, minute, second: INTEGER;
BEGIN
  WITH InfoBBS[id.pid][id.cid]^ DO
    year := INTEGER(end.Year)-INTEGER(start.Year);
    month := INTEGER(end.Month)-INTEGER(start.Month);
    day := INTEGER(end.Day)-INTEGER(start.Day);
    hour := INTEGER(end.Hour)-INTEGER(start.Hour);
    minute := INTEGER(end.Minute)-INTEGER(start.Minute);
    second := INTEGER(end.Second)-INTEGER(start.Second);
  END;
  IF second < 0 THEN
    INC( second, 60 );
    DEC( minute );
  END;
  IF minute < 0 THEN
    INC( minute, 60 );
    DEC( hour );
  END;
  IF hour < 0 THEN
    INC( hour, 24 );
    DEC( day );
  END;
  IF day < 0 THEN
    INC( day, 30 );
    DEC( month );
  END;
  IF month < 0 THEN
    INC( month, 12 );
    DEC( year );
  END;
  IF year < 0 THEN
    year := 0;
  END;
  WITH span DO
    Year := year;
    Month := month;
    Day := day;
    Hour := hour;
    Minute := minute;
    Second := second;
  END;
END GetLoggedinTime;


PROCEDURE MakeLog(id:ID; b:BOOLEAN);
VAR
  fp: STREAM;
  Call: CALL;
  i, c, d: CARDINAL;
  begin, end: CARDINAL;
  span: TimeRec;
  buf: TITLE;
BEGIN
  MakeUSRfile( buf, InfoDEV[id.pid][id.cid]^.call, "room.idx" );
  IF b = TRUE THEN  (* Connect *)
    GetDateTime(InfoBBS[id.pid][id.cid]^.start);
    IF 0 = GetFileDateTime(buf,InfoBBS[id.pid][id.cid]^.last) THEN
      GetIndex(buf,InfoBBS[id.pid][id.cid]^.uid,InfoBBS[id.pid][id.cid]^.cons);
      INC(InfoBBS[id.pid][id.cid]^.cons);
    ELSE
      InfoBBS[id.pid][id.cid]^.last := InfoBBS[id.pid][id.cid]^.start;
      AddUser(id);
    END;
    MakeUSRfile( buf, InfoDEV[id.pid][id.cid]^.call, "user.idx" );
    GetIndex(buf,c,d);
    InfoBBS[id.pid][id.cid]^.group := GROUP(c);
    InfoBBS[id.pid][id.cid]^.level := LSET(d);
    GetRoomIndex( id, InfoBBS[id.pid][id.cid]^.index );
  ELSE
    (* disconnect *)
    GetDateTime(InfoBBS[id.pid][id.cid]^.end);
    IF InfoDEV[id.pid][id.cid]^.link
         AND (InfoBBS[id.pid][id.cid]^.result <> 1) (* time up *)
         AND (InfoBBS[id.pid][id.cid]^.result <> 2) (* no input *)
    THEN
      IncIndex(buf,InfoBBS[id.pid][id.cid]^.uid, InfoBBS[id.pid][id.cid]^.cons);
      IF 0 = Connect(fp,buf,inputoutput) THEN
        GetStreamLine(fp,buf);
        FOR i := 0 TO Rooms DO
          WriteStringStream(fp,InfoROOM[i]^.RoomName);
          WriteStringStream(fp,' ');
          WriteCardStream(fp,InfoBBS[id.pid][id.cid]^.index[i],4,TRUE);
          WriteLnStream(fp);
        END;
        IF InfoBBS[id.pid][id.cid]^.group = root THEN
          WriteStringStream(fp,EnvCALL);
          WriteStringStream(fp,' ');
          WriteCardStream(fp, InfoBBS[id.pid][id.cid]^.index[Rooms+1],4,TRUE);
          WriteLnStream(fp);
        END;
        Disconnect(fp,TRUE);
      END;
      FixUserDir(id);
      MakeUSRfile( buf, InfoDEV[id.pid][id.cid]^.call, "room.idx" );
      IF 0 <> SetFileDateTime(buf,InfoBBS[id.pid][id.cid]^.start) THEN
        (* ÉGÉâÅ[ *)
        RETURN;
      END;
    END;
  END;
  MakeDNETfile( buf, "log\msg.idx" );
  IncIndexContinue(buf,end);
  MakeDNETfile( buf, "log\msg.dir" );
  IF 0 <> Connect(fp,buf,inputoutput) THEN
    Cannotopen(id,buf);
    RETURN;
  END;
  GoEOS(fp);
  WriteChar(fp,' ');
  WriteLongStream(fp,end,5,TRUE);
  WriteChar(fp,' ');
  c := StoS(InfoDEV[id.pid][id.cid]^.call,Call,TRUE);
  IF b THEN
    WriteStringStream(fp,Call);
    WriteStringStream(fp,"       ");
  ELSE
    WriteStringStream(fp,"       ");
    WriteStringStream(fp,Call);
  END;
  WriteChar(fp,' ');
  IF b THEN
    WriteTimeStream(fp,InfoBBS[id.pid][id.cid]^.start,TRUE);
    WriteStringStream(fp,"        ");
  ELSE
    WriteTimeStream(fp,InfoBBS[id.pid][id.cid]^.end,TRUE);
    GetLoggedinTime(id,span);
    WriteChar(fp,' ');
    IF (span.Year>0)OR(span.Month>0)OR(span.Day>0)OR(span.Hour>0) THEN
      WriteChar(fp,'~');
    ELSE
      WriteChar(fp,'(');
    END;
    WriteCardStream(fp,span.Minute,2,TRUE);
    WriteChar(fp,"'");
    WriteCardStream(fp,span.Second,2,TRUE);
    WriteChar(fp,')');
  END;
  WriteChar(fp,' ');
  WriteCardStream(fp,id.pid,2,TRUE);
  WriteChar(fp,' ');
  WriteCardStream(fp,id.cid,2,TRUE);
  WriteChar(fp,' ');
  IF b THEN
    WriteStringStream(fp,"login   ");
  ELSE
    IF InfoDEV[id.pid][id.cid]^.link THEN
      CASE InfoBBS[id.pid][id.cid]^.result OF
        1:  WriteStringStream(fp,"time up ");|
        2:  WriteStringStream(fp,"no input");|
        3:  WriteStringStream(fp,"download");
      ELSE
        WriteStringStream(fp,"logout  ");
      END;
    ELSE
      WriteStringStream(fp,"disconne");
    END;
  END;
  WriteLnStream(fp);
  Disconnect(fp,TRUE);
END MakeLog;

PROCEDURE Opening(id:ID);
VAR
  buf: TITLE;
BEGIN
  WriteLnLine(id);
  WriteStringLine(id,EnvNAME);
  WriteStringLine(id,' ÉXÉ^Å[Ég ');
  WriteTimeLine(id,InfoBBS[id.pid][id.cid]^.start);
  WriteStringLine(id,'  PID:[');
  WriteCardLine(id,id.pid,2,TRUE);
  WriteStringLine(id,'] CID:[');
  WriteCardLine(id,id.cid,2,TRUE);
  WriteLine(id,']');
  WriteLnLine(id);
  WriteLnLine(id);
  WriteLine(id,'[');
  WriteStringLine(id,InfoDEV[id.pid][id.cid]^.call);
  WriteStringLine(id,']: ÉAÉNÉZÉXâÒêî ');
  WriteCardLine(id,InfoBBS[id.pid][id.cid]^.cons,4,FALSE);
  WriteStringLine(id,' âÒ  ëOâÒÇÃÉAÉNÉZÉX ');
  WriteTimeLine(id,InfoBBS[id.pid][id.cid]^.last);
  WriteStringLine(id,' Ç≈Ç∑.');
  WriteLnLine(id);
  IF InfoDEV[id.pid][id.cid]^.call = "GUEST" THEN
    MakeDNETfile( buf, "msg\guest" );
    CatSJANK( id, buf );
    IF Exist( buf ) THEN
      IF NOT PutFileLine( id, buf, 0 ) THEN
      END
    END
  ELSIF InfoBBS[id.pid][id.cid]^.cons = 1 THEN
    MakeDNETfile( buf, "msg\first" );
    CatSJANK( id, buf );
    IF Exist( buf ) THEN
      IF NOT PutFileLine( id, buf, 0 ) THEN
      END
    END
  END;
  MakeDNETfile( buf, "msg\login" );
  CatSJANK( id, buf );
  IF Exist( buf ) THEN
    IF NOT PutFileLine( id, buf, 0 ) THEN
    END
  END;
  IF NOT (disphelp IN InfoBBS[id.pid][id.cid]^.level ) THEN
    MakeDNETfile( buf, "msg\loghlp" );
    CatSJANK( id, buf );
    IF Exist( buf ) THEN
      IF NOT PutFileLine( id, buf, 0 ) THEN
      END
    END;
  END;
END Opening;

PROCEDURE Ending(id:ID);
VAR
  span: TimeRec;
BEGIN
  WriteLnLine(id);
  WriteStringLine(id,EnvNAME);
  WriteStringLine(id,' èIóπ ');
  WriteTimeLine(id,InfoBBS[id.pid][id.cid]^.end);
  WriteStringLine(id,' [');
  WriteStringLine(id,InfoDEV[id.pid][id.cid]^.call);
  WriteStringLine(id,']: óòópéûä‘ÇÕ');
  GetLoggedinTime(id,span);
  WITH span DO
    IF Year>0 THEN
      WriteCardLine(id,Year,2,FALSE);
      WriteStringLine(id,'îN');
    END;
    IF Month>0 THEN
      WriteCardLine(id,Month,2,FALSE);
      WriteStringLine(id,'Éñåé');
    END;
    IF Day>0 THEN
      WriteCardLine(id,Day,2,FALSE);
      WriteStringLine(id,'ì˙');
    END;
    IF Hour>0 THEN
      WriteCardLine(id,Hour,2,FALSE);
      WriteStringLine(id,'éûä‘');
    END;
    IF Minute>0 THEN
      WriteCardLine(id,Minute,2,FALSE);
      WriteStringLine(id,'ï™');
    END;
    IF Second>0 THEN
      WriteCardLine(id,Second,2,FALSE);
      WriteStringLine(id,'ïb');
    END;
  END;
  WriteStringLine(id,'Ç≈Ç∑.');
  WriteLnLine(id);
  WriteStringLine(id,"Ç≤óòópÇ†ÇËÇ™Ç∆Ç§Ç≤Ç¥Ç¢Ç‹ÇµÇΩ. Åô Ç‹ÇΩÇÀÅ`ÅÙ");
  WriteLnLine(id);
  KickLine(id);
END Ending;

PROCEDURE ComAnalyze(id:ID;VAR s:ARRAY OF CHAR);
VAR
  c,d,len,over: CARDINAL;
  rid: INTEGER;
  buf: LINEBUF;
BEGIN
  c := Valid( s, 0 );
  IF ( c > 0 ) AND ( c < HIGH(s) ) THEN
    Copy( s, c, HIGH(s)-c+1, s );
  END;
  WITH Packet[id.pid][id.cid]^ DO
    ToUppers(s);
    Com := FindCOM(s);
    CASE Com OF
      guide,
      profile,chat,
      who,set,time,ver,free,task,
      exit,bye,quit,shell,fileup,biff,whoami,whochat,room,nein:
        RETURN;
    END;
    flg_all := FALSE;
    flg_whole := FALSE;
    flg_room := FALSE;
    flg_number := FALSE;
    flg_delete := FALSE;
    flg_search := FALSE;
    flg_last := FALSE;
    flg_p := FALSE;
    flg_q := FALSE;
    flg_rn := FALSE;
    flg_call := FALSE;
    Start := 0;
    Stop := 0;
    over := Length( s );
    c := Invalid(s,0);
    IF ( c > 0 ) AND (s[c-1] = '1') THEN
      flg_whole := TRUE;    (* f1 r1 k1 ìôÇ≈ÉtÉâÉOÇ™óßÇ¬ÇÃÇ≈íçà” *)
    END;
    IF ( c > 0 ) AND (s[c-1] = '0') THEN
      flg_all := TRUE;
    END;
    IF ( c > 0 ) AND (s[c-1] = '$') THEN
      flg_last := TRUE;
    END;
    IF over > 1 THEN
      d := InNumber(s,0);
      IF (c > d) AND (NOT ((d = c-1) AND (s[d]='0'))) THEN
        c := d;
      ELSIF c < over THEN
        c := Valid(s,c);
      END;
      
  (* Ç±ÇÍà»å„ c Ç…ÇÕéüÇÃóLå¯ï∂éöÇÃìYÇ¶éö *)
      
    (* ÉfÉäÅ[Égì«Ç›éwíËÉtÉBÅ[ÉãÉh *)
      
      IF c < over THEN
        IF s[c] = '-' THEN
          IF (s[c+1] = 'd') OR (s[c+1] = 'D') THEN
            flg_delete := TRUE;
          END;
          c := Invalid(s,c);
          IF c < over THEN
            c := Valid(s,c);
          END;
        END;
      END;
      
    (* ÉãÅ[ÉÄéwíËÉtÉBÅ[ÉãÉh *)
      
      IF c < over THEN
        d := Invalid(s,c);
        Copy(s,c,d-c,buf);
        IF (buf <> 'P') AND (buf <> 'Q') THEN
          rid := FindROOM(buf);
          IF ( rid <> -1 ) OR IsAlphabetic( buf ) THEN
            flg_room := TRUE;
            IF rid <> (-1) THEN
              Assign(InfoROOM[rid]^.RoomName,Room);
            ELSE
              flg_call := TRUE;
              Assign(buf,Room);
            END;
            c := Valid(s,d);
          END
        END
      END;
      
    (* î‘çÜéwíËÉtÉBÅ[ÉãÉh *)
      
      IF c < over THEN
        d := InNumber(s,c);
        IF s[c] = '$' THEN
          flg_last := TRUE;
          c := Invalid(s,c);
          IF c < over THEN
            c := Valid(s,c);
          END;
        ELSIF c = d THEN
          flg_number := TRUE;
          d := AtoC(s,c,Start);
          IF d < over THEN
            c := Valid( s, d );
          ELSE
            c := over;
          END;
          IF (c < over) AND ((s[c] = ',') OR (s[c] = '.')) THEN
            c := Valid( s, c+1 );
            IF c < over THEN
              d := InNumber(s,c);
            END;
            IF (c < over) AND ((s[c] = '$') OR (c = d)) THEN
              IF s[c] = '$' THEN
                flg_last := TRUE;
              ELSE
                d := AtoC(s,c,Stop);
              (*  IF Start > Stop THEN
                  Stop := Start;
                END;
              *)
              END;
              c := Invalid(s,c);
              IF c < over THEN
                c := Valid(s,c);
              END;
            ELSE
              Stop := Start;
            END;
          ELSE
            Stop := Start;
          END;
        END;
      END;
      
    (* åüçıï∂éöéwíËÉtÉBÅ[ÉãÉh *)
      
      IF c < over THEN
        IF s[c] = '/' THEN
          d := Pos('/',s,c+1);
          IF d < over THEN
            IF (c+1) <> d THEN
              flg_search := TRUE;
              Copy(s,c+1,d-c-1,Search);
            END;
            c := Invalid(s,d);
            IF c < over THEN
              c := Valid(s,c);
            END;
          ELSE
            c := over;
          END;
        END;
      END;
      
    (* òAë±ì«Ç›éwíËÉtÉBÅ[ÉãÉh *)
      
      IF (c < over) AND ( (s[c] = 'P') OR (s[c] = 'Q')) THEN
        IF s[c] = 'P' THEN
          flg_p := TRUE;
        ELSIF s[c] = 'Q' THEN
          flg_q := TRUE;
        END
      END
    END;
    
    IF flg_room = FALSE THEN
      Room := InfoBBS[id.pid][id.cid]^.CurrentROOM;
    END;
    
(*    IF flg_all=TRUE THEN
      WriteString('all éwíËÇ≈Ç∑');
      WriteLn;
    END;
    IF flg_whole THEN
      WriteString('whole éwíËÇ≈Ç∑');
      WriteLn;
    END;
    IF flg_room=TRUE THEN
      WriteString('ÉãÅ[ÉÄéwíË:[');
      WriteString(Room);
      WriteString('] Ç≈Ç∑');
      WriteLn;
    ELSE
      WriteString('ÉJÉåÉìÉgÉãÅ[ÉÄ:[');
      WriteString(InfoBBS[id.pid][id.cid]^.CurrentROOM);
      WriteString('] Ç≈Ç∑');
      WriteLn;
    END;
    IF flg_number=TRUE THEN
      WriteString('î‘çÜéwíË: ');
      WriteCard(Start,4);
      WriteString(' Ç©ÇÁ ');
      WriteCard(Stop,4);
      WriteString(' Ç‹Ç≈');
      WriteLn;
    END;
    IF flg_delete=TRUE THEN
      WriteString('ÉfÉäÅ[Égì«Ç›éwíË');
      WriteLn;
    END;
    IF flg_last=TRUE THEN
        WriteString('ç≈èIî‘çÜéwíË');
      WriteLn;
    END;
    IF flg_search=TRUE THEN
      WriteString('åüçıéwíË:[');
      WriteString(Search);
      WriteString('] Ç≈Ç∑');
      WriteLn;
    END;
    IF flg_p=TRUE THEN
      WriteString('òAë±ì«Ç›éwíË');
      WriteLn;
    END;
*)
    
  END;
END ComAnalyze;

PROCEDURE ClearMailbox(id:ID);
VAR
  i: INTEGER;
BEGIN
  FOR i := 0 TO MBS DO
    WITH MailBox[i] DO
      IF (occupy=TRUE) AND (to.pid=id.pid) AND (to.cid=id.cid) THEN
        occupy := FALSE;
      END;
    END;
  END
END ClearMailbox;

(* ÉÅÉCÉìÉãÅ[Év *)

PROCEDURE Body(id:ID);
VAR
  i,j: CARDINAL;
  res: INTEGER;
  laptime, tmptime, span: TimeRec;
  buf: LINEBUF;
BEGIN
  InfoBBS[id.pid][id.cid]^.result := 0;
  tmptime := InfoBBS[id.pid][id.cid]^.start;
  
  IF NOT ( dispchat IN InfoBBS[id.pid][id.cid]^.level ) THEN
    Packet[id.pid][id.cid]^.Com := whochat;
    WhochatBBS(id);
  END;
  
  Packet[id.pid][id.cid]^.Com := biff;
  NewBBS(id);
  
  IF InfoBBS[id.pid][id.cid]^.cons = 1 THEN
    Packet[id.pid][id.cid]^.Com := profile;
    ProfileBBS(id)
  END;
  
  LOOP
    IF NOT InfoDEV[id.pid][id.cid]^.link THEN
      RETURN;
    END;
    
    IF NOT ( disphelp IN InfoBBS[id.pid][id.cid]^.level ) THEN
      CatENV( buf, '\msg\command' );
      CatSJANK(id,buf);
      IF PutFileLine(id,buf,0) THEN
      END
    END;
    
    IF MailboxBBS(id) THEN
    END;
    
    Packet[id.pid][id.cid]^.Com := nein;
    
    WriteStringLine(id,InfoBBS[id.pid][id.cid]^.CurrentROOM);
    WriteLine(id,'>');
    KickLine(id);
    GetDateTime(laptime);
    
    i := 0;
    WHILE NOT BusyLine(id) DO
      IF NOT InfoDEV[id.pid][id.cid]^.link THEN
        RETURN;
      END;
      INC( i );
      IF i > Unit THEN
        i := 0;
        IF MailboxBBS(id) THEN
          WriteStringLine(id,InfoBBS[id.pid][id.cid]^.CurrentROOM);
          WriteLine(id,'>');
          KickLine(id);
        END;
        IF PortType[ id.pid ] >= 1 THEN
          InfoBBS[id.pid][id.cid]^.start := laptime;
          GetDateTime(InfoBBS[id.pid][id.cid]^.end);
          GetLoggedinTime(id,span);
          InfoBBS[id.pid][id.cid]^.start := tmptime;
          IF span.Minute >= ShortLimit THEN
            InfoBBS[id.pid][id.cid]^.result := 2;
            WriteStringLine(id," ì¸óÕÇ™Ç»Ç¢ÇÃÇ≈ÉçÉOÉAÉEÉgÇµÇ‹Ç∑.");
            WriteLnLine(id);
            RETURN;
          END;
        END;
      END;
      WaitLine(id);
    END;
    ReadStringLine(id,buf);
    IF NOT InfoDEV[id.pid][id.cid]^.link THEN
      RETURN;
    END;
    
    IF InfoBBS[id.pid][id.cid]^.result <> 0 THEN
      RETURN;
    END;
    
    ComAnalyze(id,buf);
    
    CASE Packet[id.pid][id.cid]^.Com OF
      files, read, log, access:
          FilesBBS(id)|
      rn, new, biff:
          NewBBS(id)|
      write:  WriteBBS(id)|
      kill: KillBBS(id)|
      guide:  Packet[id.pid][id.cid]^.Room := 'GUIDE';
          Packet[id.pid][id.cid]^.flg_room := TRUE;
          HelpBBS(id)|
      help: HelpBBS(id)|
      x:    XrossBBS(id)|
      profile:
          ProfileBBS(id)|
      chat: ChatBBS(id)|
      room: RoomBBS(id)|
      talk: TalkBBS(id)|
      who:  WhoBBS(id)|
      set:  SetBBS(id)|
      free: FreeBBS(id)|
      time: TimeBBS(id)|
      ver:  VerBBS(id)|
      task: TaskBBS(id)|
      fileup: FileupBBS(id)|
      chkusr: ChkusrBBS(id)|
      shell:
          IF (id.pid = 0) AND (InfoBBS[id.pid][id.cid]^.group = root) THEN
            Cleanup;
            CallProg("command","",i,j)
          END|
      byebye: ByebyeBBS(id)|
      su:   SuBBS(id)|
      whoami: WhoamiBBS(id)|
      whochat:
          WhochatBBS(id)|
      exit, bye, quit:
          RETURN|
      nein:
        res := FindROOM(buf);
        IF res <> -1 THEN
          InfoBBS[id.pid][id.cid]^.CurrentROOM := InfoROOM[res]^.RoomName;
          IF NOT(disphelp IN InfoBBS[id.pid][id.cid]^.level) THEN
            CatENV( buf, '\msg\' );
            CatCat(buf,InfoROOM[res]^.RoomName);
            CatSJANK(id,buf);
            IF PutFileLine(id,buf,0) THEN
            END
          END;
        ELSE
          WriteStringLine(id,'??');
          WriteLnLine(id);
        END;
    END; (* case *)
    IF PortType[ id.pid ] >= 1 THEN
      GetDateTime(InfoBBS[id.pid][id.cid]^.end);
      GetLoggedinTime(id,span);
      IF ( span.Hour * 60 + span.Minute ) >= LongLimit THEN
        InfoBBS[id.pid][id.cid]^.result := 1;
        WriteStringLine(id,"[SYSOP]: éûä‘ÉIÅ[ÉoÅ[Ç≈Ç∑. ÉçÉOÉAÉEÉgÇµÇƒÇ≠ÇæÇ≥Ç¢.");
        WriteLnLine(id);
      END;
    END;
  END
END Body;

PROCEDURE Login(id:ID): BOOLEAN;
VAR
  i: CARDINAL;
  flag: BOOLEAN;
  fp: STREAM;
  ident: MINIBUF;
  passwd, buf: TITLE;
BEGIN
  WITH InfoDEV[id.pid][id.cid]^ DO
    WriteLnLine(id);
    WriteStringLine(id,OpeningMessage);
    WriteLnLine(id);
    WriteLnLine(id);
    FOR i := 1 TO 3 DO
      WriteStringLine(id,"login: ");
      KickLine(id);
      ReadStringLine(id,ident);
      IF NOT link THEN
        RETURN FALSE;
      END;
      ToUppers(ident);
      IF ident = 'GUEST' THEN
        call := ident;
        RETURN TRUE;
      END;
      IF Did[id.pid] = con THEN
        IF (ident = 'ROOT') OR (ident = 'DOWN') THEN
          call := ident;
          RETURN TRUE;
        END;
      END;
      MakeUSRfile( buf, ident, "passwd" );
      IF 0 = Connect( fp, buf, input ) THEN
        ReadStringStream(fp,passwd);
        Disconnect(fp,TRUE);
        WriteStringLine(id,"password: ");
        KickLine(id);
        flag := GetEchoMode(id.pid);
        SetEchoMode(id.pid,FALSE);
        ReadStringLine(id,buf);
        SetEchoMode(id.pid,flag);
	WriteLnLine(id);
        IF NOT link THEN
          RETURN FALSE;
        END;
        IF passwd = buf THEN
          call := ident;
          RETURN TRUE;
        END;
      END;
      WriteStringLine(id,"login incorrect");
      WriteLnLine(id);
      KickLine(id);
    END;
    RETURN FALSE;
  END;
END Login;


(*  ÉgÉbÉvÉåÉxÉãÇ©ÇÁåƒÇ—èoÇ≥ÇÍÇÈÉvÉçÉVÉWÉÉåQ -- Ç®ÇÌÇË  *)






(* ÉgÉbÉvÉåÉxÉãÉvÉçÉVÉWÉÉ
  BBS ñ{ëÃÇÕÇ±ÇÍà»å„ÅAÇ∑Ç◊Çƒ ID (id.pid = É|Å[ÉgID, id.cid = É`ÉÉÉìÉlÉãID)
  Ç≈é©ï™Ç…äÑÇËìñÇƒÇÁÇÍÇΩÉ|Å[ÉgÅAÉ`ÉÉÉìÉlÉãÇéØï Ç∑ÇÈÅB
*)

PROCEDURE StartBBS(id:ID);
BEGIN
  IF (Did[id.pid] = con) OR (Did[id.pid] = tty) OR (Did[id.pid] = mnp) THEN
    IF NOT Login(id) THEN
      InfoDEV[id.pid][id.cid]^.link := FALSE;
      RETURN;
    END;
    IF InfoDEV[id.pid][id.cid]^.call = 'DOWN' THEN
      InfoDEV[id.pid][id.cid]^.link := FALSE;
      InfoDEV[id.pid][id.cid]^.active := FALSE;
      RETURN;
    END;
  END;
  InfoBBS[id.pid][id.cid]^.CurrentROOM := InfoROOM[0]^.RoomName;
  ClearMailbox(id);
  MakeLog(id,TRUE);
  Opening(id);
  Body(id);
  MakeLog(id,FALSE);
  IF InfoDEV[id.pid][id.cid]^.link THEN
    Ending(id);
  END;
  ClearMailbox(id);
  IF InfoDEV[id.pid][id.cid]^.link THEN
    IF (Did[ id.pid ] <> con) AND (Did[ id.pid ] <> tty) AND (Did[ id.pid ] <> mnp) THEN
      UntilReachLine(id,Delay)
    ELSE
      UntilReachLine(id,1)
    END
  END;
  InfoDEV[id.pid][id.cid]^.link := FALSE;
END StartBBS;

(*  èâä˙âª  *)

PROCEDURE SetUpBBS;
VAR
  i, j: CARDINAL;
BEGIN
  FOR i := 0 TO ORD(Ports) DO
    FOR j := 0 TO ORD(Chans[i]) DO
      NEW(InfoBBS[i][j]);
      NEW(Packet[i][j]);
    END;
  END;
  
  ChatPtr := 0;
  FOR i := 0 TO CHATS DO
    ChatUser[i].pid := 255;
    ChatUser[i].cid := 255;
  END;
  
  FOR i := 0 TO MBS DO
    MailBox[i].occupy := FALSE
  END;
  
END SetUpBBS;

BEGIN
  Delay := 10;
  Unit := 5000;
  ShortLimit := 5;
  LongLimit := 20;
  
  StartUpBBS := StartBBS;
  
  ComStr[ ORD(guide) ] := 'GUIDE';
  ComStr[ ORD(files) ] := 'FILES';
  ComStr[ ORD(new) ] := 'NEW';
  ComStr[ ORD(read) ] := 'READ';
  ComStr[ ORD(rn) ] := 'RN';
  ComStr[ ORD(write) ] := 'WRITE';
  ComStr[ ORD(kill) ] := 'KILL';
  ComStr[ ORD(log) ] := 'LOG';
  ComStr[ ORD(help) ] := 'HELP';
  ComStr[ ORD(access) ] := 'ACCESS';
  ComStr[ ORD(x) ] := 'X';
  ComStr[ ORD(profile) ] := 'PROFILE';
  ComStr[ ORD(chat) ] := 'CHAT';
  ComStr[ ORD(talk) ] := 'TALK';
  ComStr[ ORD(who) ] := 'WHO';
  ComStr[ ORD(set) ] := 'SET';
  ComStr[ ORD(time) ] := 'TIME';
  ComStr[ ORD(ver) ] := 'VER';
  ComStr[ ORD(free) ] := 'FREE';
  ComStr[ ORD(task) ] := 'TASK';
  ComStr[ ORD(fileup) ] := 'FILEUP';
  ComStr[ ORD(chkusr) ] := 'CHKUSR';
  ComStr[ ORD(shell) ] := 'SHELL';
  ComStr[ ORD(exit) ] := 'EXIT';
  ComStr[ ORD(bye) ] := 'BYE';
  ComStr[ ORD(quit) ] := 'QUIT';
  ComStr[ ORD(biff) ] := 'BIFF';
  ComStr[ ORD(byebye) ] := 'BYEBYE';
  ComStr[ ORD(su) ] := 'SU';
  ComStr[ ORD(whoami) ] := 'WHOAMI';
  ComStr[ ORD(whochat) ] := 'WHOCHAT';
  ComStr[ ORD(room) ] := 'ROOM';
  ComStr[ ORD(nein) ] := 'wait';
END BBS.
