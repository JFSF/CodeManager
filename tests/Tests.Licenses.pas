unit Tests.Licenses;

// Testes do reconhecimento de licencas e da leitura do boss.json / boss-lock.json (CM.Licenses).

interface

uses
  System.SysUtils, System.Generics.Collections, DUnitX.TestFramework, CM.Licenses;

type
  [TestFixture]
  TLicensesTests = class
  public
    [Test] procedure RecognisesMit;
    [Test] procedure MitWithLineBreaksAndIndentation;
    [Test] procedure RecognisesApache;
    [Test] procedure RecognisesBsdVariants;
    [Test] procedure RecognisesIscUnlicenseZlibAndBoost;
    [Test] procedure MplIsNotTakenForTheGplItMentions;
    [Test] procedure Gpl3IsNotTakenForTheAgplItMentions;
    [Test] procedure LgplIsNotTakenForTheGpl;
    [Test] procedure GplVersions;
    [Test] procedure AgplByItsTitle;
    [Test] procedure UnknownTextGivesNothing;
    [Test] procedure EmptyTextGivesNothing;
    [Test] procedure NormalizeKnownValues;
    [Test] procedure NormalizeIgnoresCaseAndSeparators;
    [Test] procedure NormalizeUnknownGivesNothing;
    [Test] procedure BossJsonFields;
    [Test] procedure BossJsonWithoutFields;
    [Test] procedure BossJsonInvalidIsRefused;
    [Test] procedure BossLockVersionsByLibraryName;
    [Test] procedure BossLockInvalidIsEmpty;
    [Test] procedure VersionedFolderIsSplit;
    [Test] procedure FolderWithoutVersionIsNotSplit;
    [Test] procedure VersionFolders;
    [Test] procedure DelphiSuffixIsStripped;
  end;

implementation

const
  MitText =
    'MIT License' + sLineBreak + sLineBreak + 'Copyright (c) 2024 Someone' + sLineBreak + sLineBreak +
    'Permission is hereby granted, free of charge, to any person obtaining a copy' + sLineBreak +
    'of this software and associated documentation files (the "Software"), to deal' + sLineBreak +
    'in the Software without restriction.' + sLineBreak + sLineBreak +
    'THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.';

  BsdBody =
    'Redistribution and use in source and binary forms, with or without modification, are permitted provided that ' +
    'the following conditions are met: 1. Redistributions of source code must retain the above copyright notice.';

procedure TLicensesTests.RecognisesMit;
begin
  Assert.AreEqual('MIT', DetectLicenseId(MitText));
end;

procedure TLicensesTests.MitWithLineBreaksAndIndentation;
begin
  Assert.AreEqual('MIT', DetectLicenseId('   Permission is hereby granted,' + sLineBreak + #9 + 'free of charge,   to any person' +
    sLineBreak + 'obtaining a copy of this software. THE SOFTWARE IS PROVIDED "AS IS".'));
end;

procedure TLicensesTests.RecognisesApache;
begin
  Assert.AreEqual('Apache-2.0', DetectLicenseId('                                 Apache License' + sLineBreak +
    '                           Version 2.0, January 2004' + sLineBreak + '                        http://www.apache.org/licenses/'));
end;

procedure TLicensesTests.RecognisesBsdVariants;
begin
  Assert.AreEqual('BSD-2-Clause', DetectLicenseId(BsdBody));
  Assert.AreEqual('BSD-3-Clause', DetectLicenseId(BsdBody + ' 3. Neither the name of the copyright holder nor the names of its contributors'));
  Assert.AreEqual('BSD-4-Clause', DetectLicenseId(BsdBody + ' 3. All advertising materials mentioning features or use of this software must display'));
end;

procedure TLicensesTests.RecognisesIscUnlicenseZlibAndBoost;
begin
  Assert.AreEqual('ISC', DetectLicenseId('Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted'));
  Assert.AreEqual('Unlicense', DetectLicenseId('This is free and unencumbered software released into the public domain.'));
  Assert.AreEqual('Zlib', DetectLicenseId('This software is provided ''as-is'', without any express or implied warranty. 2. Altered source versions must be plainly marked as such, and must not be misrepresented'));
  Assert.AreEqual('BSL-1.0', DetectLicenseId('Boost Software License - Version 1.0 - August 17th, 2003'));
end;

procedure TLicensesTests.MplIsNotTakenForTheGplItMentions;
begin
  Assert.AreEqual('MPL-2.0', DetectLicenseId('Mozilla Public License Version 2.0 ... "Secondary License" means either the GNU General Public License, Version 2.0, the GNU Lesser General Public License, Version 2.1, the GNU Affero General Public License, Version 3.0'));
end;

procedure TLicensesTests.Gpl3IsNotTakenForTheAgplItMentions;
begin
  Assert.AreEqual('GPL-3.0-only', DetectLicenseId('GNU GENERAL PUBLIC LICENSE Version 3, 29 June 2007 ... 13. Use with the GNU Affero General Public License.'));
end;

procedure TLicensesTests.LgplIsNotTakenForTheGpl;
begin
  Assert.AreEqual('LGPL-3.0-only', DetectLicenseId('GNU LESSER GENERAL PUBLIC LICENSE Version 3, 29 June 2007 ... of the GNU General Public License, version 3'));
  Assert.AreEqual('LGPL-2.1-only', DetectLicenseId('GNU LESSER GENERAL PUBLIC LICENSE Version 2.1, February 1999 ... the GNU General Public License'));
end;

procedure TLicensesTests.GplVersions;
begin
  Assert.AreEqual('GPL-2.0-only', DetectLicenseId('GNU GENERAL PUBLIC LICENSE Version 2, June 1991'));
  Assert.AreEqual('GPL-3.0-only', DetectLicenseId('GNU GENERAL PUBLIC LICENSE Version 3, 29 June 2007'));
end;

procedure TLicensesTests.AgplByItsTitle;
begin
  Assert.AreEqual('AGPL-3.0-only', DetectLicenseId('GNU AFFERO GENERAL PUBLIC LICENSE Version 3, 19 November 2007 ... the GNU General Public License'));
end;

procedure TLicensesTests.UnknownTextGivesNothing;
begin
  Assert.AreEqual('', DetectLicenseId('Free for personal use. Commercial use requires written permission from the author.'));
end;

procedure TLicensesTests.EmptyTextGivesNothing;
begin
  Assert.AreEqual('', DetectLicenseId(''));
  Assert.AreEqual('', DetectLicenseId('   ' + sLineBreak));
end;

procedure TLicensesTests.NormalizeKnownValues;
begin
  Assert.AreEqual('MIT', NormalizeLicenseId('MIT'));
  Assert.AreEqual('Apache-2.0', NormalizeLicenseId('Apache-2.0'));
  Assert.AreEqual('BSD-3-Clause', NormalizeLicenseId('BSD-3-Clause'));
  Assert.AreEqual('MPL-2.0', NormalizeLicenseId('MPL-2.0'));
  Assert.AreEqual('LGPL-3.0-only', NormalizeLicenseId('LGPL-3.0'));
end;

procedure TLicensesTests.NormalizeIgnoresCaseAndSeparators;
begin
  Assert.AreEqual('Apache-2.0', NormalizeLicenseId('apache 2.0'));
  Assert.AreEqual('MIT', NormalizeLicenseId('  mit  '));
  Assert.AreEqual('GPL-3.0-only', NormalizeLicenseId('GPL_3.0'));
end;

procedure TLicensesTests.NormalizeUnknownGivesNothing;
begin
  Assert.AreEqual('', NormalizeLicenseId('Proprietary'));
  Assert.AreEqual('', NormalizeLicenseId(''));
  Assert.AreEqual('', NormalizeLicenseId('see LICENSE.txt'));
end;

procedure TLicensesTests.BossJsonFields;
var
  Info: TBossInfo;
begin
  Assert.IsTrue(ParseBossJson('{"name":"horse","description":"web","version":"3.1.0","homepage":"https://github.com/HashLoad/horse","license":"MIT","mainsrc":"src/"}', Info));
  Assert.AreEqual('horse', Info.Name);
  Assert.AreEqual('3.1.0', Info.Version);
  Assert.AreEqual('MIT', Info.License);
  Assert.AreEqual('https://github.com/HashLoad/horse', Info.HomePage);
end;

procedure TLicensesTests.BossJsonWithoutFields;
var
  Info: TBossInfo;
begin
  Assert.IsTrue(ParseBossJson('{"name":"x"}', Info));
  Assert.AreEqual('x', Info.Name);
  Assert.AreEqual('', Info.Version);
  Assert.AreEqual('', Info.License);
end;

procedure TLicensesTests.BossJsonInvalidIsRefused;
var
  Info: TBossInfo;
begin
  Assert.IsFalse(ParseBossJson('not json', Info));
  Assert.IsFalse(ParseBossJson('[1,2]', Info));
  Assert.IsFalse(ParseBossJson('', Info));
end;

procedure TLicensesTests.BossLockVersionsByLibraryName;
var
  Versions: TDictionary<string, string>;
  V: string;
begin
  Versions := ParseBossLock('{"hash":"x","installedModules":{"github.com/hashload/Horse":{"name":"horse","version":"3.1.0"},' +
    '"github.com/hashload/jhonson":{"version":"2.0.1"},"github.com/x/none":{"hash":"h"}}}');
  try
    Assert.AreEqual<NativeInt>(2, Versions.Count);
    Assert.IsTrue(Versions.TryGetValue('horse', V));
    Assert.AreEqual('3.1.0', V);
    Assert.IsTrue(Versions.TryGetValue('jhonson', V));
    Assert.AreEqual('2.0.1', V);
  finally
    Versions.Free;
  end;
end;

procedure TLicensesTests.BossLockInvalidIsEmpty;
var
  Versions: TDictionary<string, string>;
begin
  Versions := ParseBossLock('garbage');
  try
    Assert.AreEqual<NativeInt>(0, Versions.Count);
  finally
    Versions.Free;
  end;
end;

procedure TLicensesTests.VersionedFolderIsSplit;
var
  N, V: string;
begin
  Assert.IsTrue(SplitVersionedFolder('Spring4D-2.0', N, V));
  Assert.AreEqual('Spring4D', N);
  Assert.AreEqual('2.0', V);
  Assert.IsTrue(SplitVersionedFolder('Delphi-Mocks-1.0.3', N, V));
  Assert.AreEqual('Delphi-Mocks', N);
  Assert.AreEqual('1.0.3', V);
  Assert.IsTrue(SplitVersionedFolder('Chart4D_v0.9.1', N, V));
  Assert.AreEqual('Chart4D', N);
  Assert.AreEqual('0.9.1', V);
end;

procedure TLicensesTests.FolderWithoutVersionIsNotSplit;
var
  N, V: string;
begin
  Assert.IsFalse(SplitVersionedFolder('Spring4D', N, V));
  Assert.AreEqual('', N);
  Assert.IsFalse(SplitVersionedFolder('src', N, V));
  Assert.IsFalse(SplitVersionedFolder('2.0', N, V));
end;

procedure TLicensesTests.VersionFolders;
begin
  Assert.IsTrue(IsVersionFolder('1.2.0'));
  Assert.IsTrue(IsVersionFolder('v2.3'));
  Assert.IsFalse(IsVersionFolder('Source'));
  Assert.IsFalse(IsVersionFolder('13'));
  Assert.IsFalse(IsVersionFolder('Chart4D-13'));
end;

procedure TLicensesTests.DelphiSuffixIsStripped;
begin
  Assert.AreEqual('Chart4D', StripDelphiSuffix('Chart4D-13'));
  Assert.AreEqual('Spring4D', StripDelphiSuffix('Spring4D'));
  Assert.AreEqual('13', StripDelphiSuffix('13'));
end;

initialization
  TDUnitX.RegisterTestFixture(TLicensesTests);

end.
