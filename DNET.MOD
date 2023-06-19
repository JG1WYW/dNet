
MODULE dNet;

FROM STORAGE IMPORT
  MaxBlocks;
FROM InOut IMPORT
  Write,WriteString,WriteLn,WriteCard;
FROM Init IMPORT
  SetUpDNET, SetDownDNET;
FROM Manager IMPORT
  PM;
FROM BBS IMPORT
  SetUpBBS;

BEGIN
  MaxBlocks := 1;

  WriteString("# dNet Ver.4.05e (FREEWARE) for PC98/FMR/IBM-PC with MCD");
  WriteLn;
  WriteString("# All rights reserved. Copyright (C) 1992,1996 by JF1GMH");
  WriteLn;
  WriteString("# email: Tomio NARITA <narita@mt.cs.keio.ac.jp>");
  WriteLn;
  WriteLn;
  SetUpDNET;
  SetUpBBS;
  PM;
  SetDownDNET;
END dNet.

