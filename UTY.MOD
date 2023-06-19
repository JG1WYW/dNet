
IMPLEMENTATION MODULE Uty;

FROM MSDOS IMPORT
  xmffc, MSDOS, Carry, Registers, GetSegs;

VAR
  r: Registers;

PROCEDURE GetDiskFree(drive: CARDINAL; VAR claster,size: CARDINAL):BOOLEAN;
VAR
  regs: Registers;
BEGIN
  regs.AH := 036h;
  regs.DL := drive;
  MSDOS( regs );
  IF regs.AX = 0ffffh THEN
    RETURN FALSE;
  ELSE
    claster := regs.BX;
    size := CARDINAL(regs.CX) * CARDINAL(regs.AX);
    RETURN TRUE;
  END;
END GetDiskFree;

(*  ストリング s に関して、位置 p からサーチして
  文字列が数字である部分のカーディナルを res に返す。
  また、数字でない文字が現れた位置を関数値として返す。
  ただし s を最後まで数値化した場合は HIGH(s)+1 を返す。
*)

PROCEDURE AtoC(s:ARRAY OF CHAR;p:CARDINAL;VAR res:CARDINAL):CARDINAL;
VAR
  d: CARDINAL;
BEGIN
  res := 0;
  FOR d := p TO HIGH(s) DO
    IF (s[d]>='0') AND (s[d]<='9') AND (res < 6553) THEN
      res := res * 10 + ORD(s[d]) - ORD('0');
    ELSE
      RETURN d;
    END
  END;
  RETURN HIGH(s)+1;
END AtoC;

(* AtoC のロングバージョン *)

PROCEDURE AtoL(s:ARRAY OF CHAR;p:CARDINAL;VAR res:LONGCARD):CARDINAL;
VAR
  d: CARDINAL;
BEGIN
  res := 0;
  FOR d := p TO HIGH(s) DO
    IF (s[d]>='0') AND (s[d]<='9') AND (res < 429496729) THEN
      res := res * 10 + ORD(s[d]) - ORD('0');
    ELSE
      RETURN d;
    END;
  END;
  RETURN HIGH(s)+1;
END AtoL;

(*  カーディナル i を文字列に変換する。その際、桁数を j にセット。
  このとき、論理値 b が TRUE ならば余った桁を '0' で fill.
  FALSE だとスペースで fill.
*)

PROCEDURE CtoA(i:CARDINAL; VAR s:ARRAY OF CHAR; j:CARDINAL;b:BOOLEAN);
VAR k: CARDINAL;
  t: ARRAY [0..15] OF CARDINAL;
BEGIN
  IF (j<1) OR (j>15) OR (HIGH(s)<j) OR (HIGH(t)<j) THEN
    RETURN;
  END;
  FOR k := 0 TO j-1 DO
    IF i>0 THEN
      t[k] := i MOD 10;
      i := i DIV 10;
    ELSE
      t[k] := 10;
    END;
  END;
  FOR k := 0 TO j-1 DO
    IF t[j-k-1] = 10 THEN
      IF b = TRUE THEN
        s[k] := '0';
      ELSE
        s[k] := ' ';
      END;
    ELSE
      s[k] := CHR( ORD('0') + t[j-k-1] );
    END;
  END;
  s[j] := 0x;
END CtoA;

(* CtoA のロングバージョン *)

PROCEDURE LtoA(i:LONGCARD; VAR s:ARRAY OF CHAR; j:CARDINAL;b:BOOLEAN);
VAR k: CARDINAL;
  t: ARRAY [0..15] OF LONGCARD;
BEGIN
  IF (j<1) OR (j>15) OR (HIGH(s)<j) OR (HIGH(t)<j) THEN
    RETURN;
  END;
  FOR k := 0 TO j-1 DO
    IF i <> 0 THEN
      t[k] := LONG(i MOD 10);
      i := LONG(i DIV 10);
    ELSE
      t[k] := 10;
    END;
  END;
  FOR k := 0 TO j-1 DO
    IF t[j-k-1] = 10 THEN
      IF b = TRUE THEN
        s[k] := '0';
      ELSE
        s[k] := ' ';
      END;
    ELSE
      s[k] := CHR( ORD('0') + SHORT(t[j-k-1]) );
    END;
  END;
  s[j] := 0x;
END LtoA;

PROCEDURE MatchString(s,r:ARRAY OF CHAR):CARDINAL;
VAR i,c:CARDINAL;
BEGIN
  i := 0;
  c := 0;
  WHILE ( i <= HIGH(r) ) AND ( r[i] <> 0x ) DO
    IF ( i > HIGH(s) ) OR ( s[i] = 0x ) THEN
      i := HIGH(r);
      c := 0;
    ELSIF (s[i]=r[i]) THEN
      INC(c);
    ELSE
      i := HIGH(r);
      c := 0;
    END;
    INC(i);
  END;
  RETURN c;
END MatchString;

PROCEDURE MatchStringAmbig(s,r:ARRAY OF CHAR):CARDINAL;
VAR i,c:CARDINAL;
BEGIN
  i := 0;
  c := 0;
  WHILE (i<=HIGH(s)) AND (i<=HIGH(r)) AND (s[i] <> 0x) AND (r[i] <> 0x) DO
    IF (s[i]=r[i]) THEN
      INC(c);
    ELSIF (r[i]=' ') OR (r[i]='$') OR ((r[i]>='0') AND (r[i]<='9')) THEN
      i := HIGH(r);
    ELSE
      i := HIGH(r);
      c := 0;
    END;
    INC(i);
  END;
  RETURN c;
END MatchStringAmbig;

PROCEDURE IsMsKanji(c: CHAR):BOOLEAN;
BEGIN
  IF ((c>=081x) AND (c <=09fx)) OR ((c>=0e0x) AND (c<=0fcx)) THEN
    RETURN TRUE;
  ELSE
    RETURN FALSE;
  END;
END IsMsKanji;

PROCEDURE ToUppers(VAR s:ARRAY OF CHAR);
VAR
  flagQuote, flagOption, flagKanji: BOOLEAN;
  i: CARDINAL;
BEGIN
  flagQuote := FALSE;
  flagOption := FALSE;
  flagKanji := FALSE;
  FOR i := 0 TO HIGH(s) DO
    IF s[i] = 0x THEN
      RETURN;
    END;
    IF (NOT flagOption) AND (NOT flagKanji) AND (NOT flagQuote) THEN
      IF (s[i]>='a') AND (s[i]<='z') THEN
        s[i] := CHR( ORD(s[i]) - ORD(020x) );
      END;
    END;
    IF flagKanji = TRUE THEN
      flagKanji := FALSE;
    ELSIF IsMsKanji(s[i]) THEN
      flagKanji := TRUE;
    ELSIF (s[i] = '/') THEN
      IF flagQuote = TRUE THEN
        flagQuote := FALSE;
      ELSE
        flagQuote := TRUE;
      END;
    ELSIF (s[i] = '-') THEN
      flagOption := TRUE;
    ELSE
      IF (s[i] = ' ') AND (flagOption = TRUE) THEN
        flagOption := FALSE;
      END;
    END;
  END;
END ToUppers;

PROCEDURE CheckKanji(VAR str:ARRAY OF CHAR; p:CARDINAL);
VAR
  flagKanji: BOOLEAN;
  i: CARDINAL;
BEGIN
  flagKanji := TRUE;
  i := 0;
  WHILE (i <= HIGH(str)) AND (str[i] <> 0x) DO
    IF flagKanji = TRUE THEN
      flagKanji := FALSE;
    ELSIF IsMsKanji(str[i]) THEN
      flagKanji := TRUE
    ELSE
      flagKanji := FALSE
    END
    IF (i = p) AND flagKanji THEN
      str[p] := ' ';
    END;
    INC( i );
  END;
END CheckKanji;

END Uty.
