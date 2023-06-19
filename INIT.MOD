
IMPLEMENTATION MODULE Init;

FROM SYSTEM IMPORT
  BYTE;
FROM STORAGE IMPORT
  ALLOCATE;
FROM GetEnvName IMPORT
  GetEnvName;
FROM Strings IMPORT
  Concat, Assign;
FROM Streams IMPORT
  STREAM,Direction,Connect,Disconnect,EOS;
FROM InOut IMPORT
  Write,WriteString,WriteLn,WriteCard;
FROM Type IMPORT
  LINEBUF;
FROM Manager IMPORT
  Did,Heap,DevLst,Ports,Chans,PORTS,CHANS,PortBufSize,MAXBUFSIZE,Priority;
FROM BBS IMPORT
  InfoROOM,ROOMS,Rooms,Delay,ShortLimit,LongLimit,PortType,
  Unit, EnvDNET,EnvNAME,EnvTMP,EnvUSR,EnvCALL,OpeningMessage;
FROM Uty IMPORT
  MatchString,ToUppers;
FROM Mcd IMPORT
  Axopen,Axclose;
FROM Stdio IMPORT
  ReadStringStream, ReadCardStream, GetStreamLine;

PROCEDURE CouldNotOpen(s : ARRAY OF CHAR);
BEGIN
  Write(7x);
  WriteString('ファイルがオープンできない. [');
  WriteString(s);
  WriteString(']');
  WriteLn;
END CouldNotOpen;

PROCEDURE SetUpDNET;
VAR
  i,j: BYTE;
  c: CARDINAL;
  fp: STREAM;
  buf: LINEBUF;
BEGIN
  Ports := 0;
  Chans[0] := 0;
  Did[0] := con;
  PortType[0] := 0;
  PortBufSize[0] := 512;
  Priority[0] := 0;

  OpeningMessage := "Welcome to ((( dNet ))) Complete Multi Task BBS";
  
  EnvNAME := "((( dNet )))";

  EnvTMP := "A:";
  EnvUSR := "A:";
  EnvCALL := "ROOT";
  
  IF NOT GetEnvName('DNET',EnvDNET) THEN
    EnvDNET := 'A:';
  END;
  
  Concat(EnvDNET,"\etc\dNet.etc",buf);
  IF 0 <> Connect(fp,buf,input) THEN
    CouldNotOpen(buf);
    HALT;
  END;
  WriteString('Now Reading ');
  WriteString(buf);
  WriteLn;
  i := 0;
  j := 0;
  WHILE NOT EOS(fp) DO
    ReadStringStream(fp,buf);
    IF MatchString(';',buf) > 0 THEN
      GetStreamLine(fp,buf);
    ELSIF MatchString('msg',buf) > 0 THEN
      GetStreamLine(fp,buf);
      Assign(buf,OpeningMessage);
      WriteString('msg: ');
      WriteString(OpeningMessage);
      WriteLn;
    ELSIF MatchString('name',buf) > 0 THEN
      GetStreamLine(fp,buf);
      Assign(buf,EnvNAME);
      WriteString('name: ');
      WriteString(EnvNAME);
      WriteLn;
    ELSIF MatchString('tmp',buf) > 0 THEN
      ReadStringStream(fp,buf);
      Assign(buf,EnvTMP);
      WriteString('tmp: ');
      WriteString(EnvTMP);
      WriteLn;
    ELSIF MatchString('call',buf) > 0 THEN
      ReadStringStream(fp,buf);
      Assign(buf,EnvCALL);
      WriteString('call: ');
      WriteString(EnvCALL);
      WriteLn;
    ELSIF MatchString('delay',buf) > 0 THEN
      ReadCardStream(fp,Delay);
      WriteString('delay: ');
      WriteCard(Delay,0);
      WriteLn;
    ELSIF MatchString('unit',buf) > 0 THEN
      ReadCardStream(fp,Unit);
      WriteString('unit: ');
      WriteCard(Unit,0);
      WriteLn;
    ELSIF MatchString('shortlimit',buf) > 0 THEN
      ReadCardStream(fp,ShortLimit);
      WriteString('shortlimit: ');
      WriteCard(ShortLimit,0);
      WriteLn;
    ELSIF MatchString('longlimit',buf) > 0 THEN
      ReadCardStream(fp,LongLimit);
      WriteString('longlimit: ');
      WriteCard(LongLimit,0);
      WriteLn;
    ELSIF MatchString('heap',buf) > 0 THEN
      ReadCardStream(fp,Heap);
      WriteString('heap: ');
      WriteCard(Heap,0);
      WriteLn;
    ELSIF MatchString('usr',buf) > 0 THEN
      ReadStringStream(fp,buf);
      Assign(buf,EnvUSR);
      WriteString('usr: ');
      WriteString(EnvUSR);
      WriteLn;
    ELSIF MatchString('device',buf) > 0 THEN

      ReadStringStream(fp,buf);
      WriteString('device: ');
      WriteString(buf);

      IF buf = 'con' THEN
	i := 0;
      ELSE
        i := BYTE(Axopen(buf));
        IF i = 0 THEN
          CouldNotOpen(buf);
          HALT;
        END;
	IF i > Ports THEN
	  Ports := i;
          IF Ports > PORTS THEN
            WriteString('ポートの数が多すぎる.');
            WriteLn;
            HALT;
          END;
	END;
      END;
      WriteString(', port: ');
      WriteCard(i,0);
      
      ReadCardStream( fp, PortType[ i ] );
      WriteString(', type: ');
      WriteCard( PortType[ i ],0);

      ReadStringStream(fp,buf);
      WriteString(', DID: ');
      WriteString(buf);

      IF (buf = 'con') AND (i = 0) THEN
        Did[i] := con;
      ELSIF buf = 'tty' THEN
        Did[i] := tty;
      ELSIF buf = 'aea' THEN
        Did[i] := aea;
      ELSIF buf = 'tas' THEN
        Did[i] := tas;
      ELSIF buf = 'tnc' THEN
        Did[i] := tnc;
      ELSIF buf = 'mnp' THEN
        Did[i] := mnp;
      ELSE
        WriteString('デバイス ID が正しくない.');
        WriteLn;
        HALT;
      END;

      ReadCardStream(fp,c);
      Chans[i] := INTEGER(c)-1;
      WriteString(', channel: ');
      WriteCard(1+Chans[i],0);

      ReadCardStream( fp, PortBufSize[ i ] );
      WriteString(', buffer: ');
      WriteCard(PortBufSize[i],0);

      ReadCardStream( fp, Priority[ i ] );
      WriteString(', priority: ');
      WriteCard(Priority[i],0);

      WriteLn;

      IF ( Chans[i] < 0 ) OR ( Chans[i] > CHANS ) THEN
        WriteString('チャンネル数が正しくない.');
        WriteLn;
        HALT;
      END;
      IF PortBufSize[ i ] >= MAXBUFSIZE THEN
        WriteString('バッファサイズが正しくない.');
        WriteLn;
        HALT;
      END;
      IF Priority[ i ] >= 10000 THEN
        WriteString('優先度が正しくない.');
        WriteLn;
        HALT;
      END;
    ELSIF MatchString('room',buf) > 0 THEN
      NEW(InfoROOM[j]);
      WITH InfoROOM[j]^ DO
        ReadStringStream(fp,RoomName);
        ToUppers(RoomName);
        WriteString('room: ');
        WriteString(RoomName);
        Write(09x);
        ReadCardStream(fp,RoomType);
        WriteString(' type: ');
        WriteCard(RoomType,0);
        ReadStringStream(fp,RoomDir);
        ToUppers(RoomDir);
        WriteString(' dir: ');
        WriteString(RoomDir);
        WriteLn;
      END;
      
      INC(j);
      IF j > ROOMS THEN
        WriteString('ルームの数が多すぎる.');
        WriteLn;
        HALT;
      END;
    END;
  END;
  Disconnect(fp,TRUE);

  IF j = 0 THEN
    WriteString('ルームがない.');
    WriteLn;
    HALT;
  END;

  NEW(InfoROOM[j]);
  WITH InfoROOM[j]^ DO
    ToUppers( EnvCALL );
    Assign( EnvCALL, RoomName );
    RoomType := 0;
    RoomDir := "";
  END;
  
  Rooms := j-1;
  WriteString('ポート数: ');
  WriteCard(Ports,0);
  WriteLn;
  WriteString('ルーム数: ');
  WriteCard(1+Rooms,0);
  WriteLn;
END SetUpDNET;

PROCEDURE SetDownDNET;
VAR
  i: INTEGER;
BEGIN
  i := ORD( Ports );
  WHILE i > 0 DO
    Axclose( i );
    DEC( i );
  END;
END SetDownDNET;

END Init.
