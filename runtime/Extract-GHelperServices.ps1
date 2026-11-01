#requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Path)
$ErrorActionPreference = 'Stop'
# Only PE metadata and IL bytes are read. No target assembly is loaded or invoked.
if (-not ('GHelperStaticReader' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Reflection.Metadata;
using System.Reflection.Metadata.Ecma335;
using System.Reflection.PortableExecutable;
public static class GHelperStaticReader {
 static void Require(bool ok,string message){if(!ok)throw new InvalidDataException(message);}
 static void ListType(MetadataReader md, EntityHandle h){
  Require(h.Kind==HandleKind.TypeSpecification,"Expected List<string> type specification");
  var r=md.GetBlobReader(md.GetTypeSpecification((TypeSpecificationHandle)h).Signature);
  Require(r.ReadByte()==0x15 && r.ReadByte()==0x12,"Expected generic class");
  int coded=r.ReadCompressedInteger();
  Require((coded&3)==1,"Expected type reference");
  var t=md.GetTypeReference(MetadataTokens.TypeReferenceHandle(coded>>2));
  Require(md.GetString(t.Namespace)=="System.Collections.Generic" && md.GetString(t.Name)=="List`1", "Expected List<T>");
  Require(r.ReadCompressedInteger()==1 && r.ReadByte()==0x0e && r.RemainingBytes==0,"Expected List<string>");
 }
 static void Method(MetadataReader md,int token,string name,byte[] signature){
  var h=MetadataTokens.EntityHandle(token);Require(h.Kind==HandleKind.MemberReference,"Expected member reference");
  var m=md.GetMemberReference((MemberReferenceHandle)h);ListType(md,m.Parent);
  Require(md.GetString(m.Name)==name && md.GetBlobBytes(m.Signature).SequenceEqual(signature),"Unexpected list method signature");
 }
 public static Dictionary<string,string[]> Read(byte[] bytes){
  using(var pe=new PEReader(new MemoryStream(bytes,false))){
   var md=pe.GetMetadataReader();
   var types=md.TypeDefinitions.Where(h=>md.GetString(md.GetTypeDefinition(h).Name)=="AsusService").ToArray();
   Require(types.Length==1,"Expected exactly one AsusService type");
   var t=md.GetTypeDefinition(types[0]);
   var ctors=t.GetMethods().Where(h=>md.GetString(md.GetMethodDefinition(h).Name)==".cctor").ToArray();
   Require(ctors.Length==1,"Expected one static initializer");
   var body=pe.GetMethodBody(md.GetMethodDefinition(ctors[0]).RelativeVirtualAddress);
   Require(body.ExceptionRegions.Length==0,"Unsupported initializer exception handling");
   var il=body.GetILBytes();int i=0;
   var result=new Dictionary<string,string[]>();
   // Accept only new List<string> { literal, ... }; stsfld, repeated, then ret.
   // Fail closed if a later GHelper version changes the initializer's structure.
   while(i<il.Length && il[i]!=0x2a){
    Require(il[i++]==0x73,"Expected newobj");
    Method(md,BitConverter.ToInt32(il,i),".ctor",new byte[]{0x20,0,1});i+=4;
    var values=new List<string>();
    while(i<il.Length && il[i]==0x25){
     i++;Require(il[i++]==0x72,"Expected literal string");int tok=BitConverter.ToInt32(il,i);i+=4;
     Require((tok & unchecked((int)0xff000000))==0x70000000,"Expected user string token");
     values.Add(md.GetUserString(MetadataTokens.UserStringHandle(tok&0xffffff)));
     Require(il[i++]==0x6f,"Expected List.Add");
     Method(md,BitConverter.ToInt32(il,i),"Add",new byte[]{0x20,1,1,0x13,0});i+=4;
    }
    Require(il[i++]==0x80,"Expected static field assignment");
    var fh=MetadataTokens.EntityHandle(BitConverter.ToInt32(il,i));i+=4;
    Require(fh.Kind==HandleKind.FieldDefinition && t.GetFields().Contains((FieldDefinitionHandle)fh),"Field belongs to another type");
    var field=md.GetFieldDefinition((FieldDefinitionHandle)fh);
    Require((field.Attributes & System.Reflection.FieldAttributes.Static)!=0,"Expected static field");
    string name=md.GetString(field.Name);
    Require((name=="services" || name=="servicesAC") && values.Count>0 && !result.ContainsKey(name),"Unexpected or duplicate field");
    result.Add(name,values.ToArray());
   }
   Require(i==il.Length-1 && il[i]==0x2a && result.Count==2,"Unsupported initializer tail or missing field");
   return result;
  }
 }
}
'@
}
$resolved = (Resolve-Path -LiteralPath $Path).ProviderPath
$b = [IO.File]::ReadAllBytes($resolved)
$hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($b))
$sig = '8B1202B96A612038727B930214D7A03213F5B9E6EFAE3318EE3B2DCE24B36AAE'
$offset = 0L
for ($i=8; $i -le $b.Length-32; $i++) {
    if ($b[$i] -eq 139 -and [Convert]::ToHexString($b,$i,32) -eq $sig) {
        $offset = [BitConverter]::ToInt64($b,$i-8); break
    }
}
$bundleVersion = $null; $entryOffset = 0L; $entrySize = $b.LongLength
if ($offset -gt 0) {
    if ($offset -ge $b.LongLength) { throw 'Invalid bundle header offset.' }
    $stream = [IO.MemoryStream]::new($b,$false)
    $reader = [IO.BinaryReader]::new($stream)
    try {
        $stream.Position=$offset
        $major=$reader.ReadUInt32(); $minor=$reader.ReadUInt32(); $count=$reader.ReadInt32()
        if ($major -notin 1,2,6 -or $minor -ne 0 -or $count -lt 1 -or $count -gt 10000) { throw 'Unsupported bundle format.' }
        $bundleVersion="$major.$minor"; $null=$reader.ReadString()
        if ($major -ge 2) { $stream.Position+=40 }
        $entries=@(for ($j=0;$j -lt $count;$j++) {
            $o=$reader.ReadInt64(); $s=$reader.ReadInt64()
            $c=if ($major -ge 6) {$reader.ReadInt64()} else {0L}
            $type=$reader.ReadByte(); $name=$reader.ReadString()
            if ($o -lt 0 -or $s -lt 0 -or $c -lt 0 -or $o -gt $b.LongLength -or ([Math]::Max($s,$c) -gt $b.LongLength-$o)) { throw 'Invalid bundle entry bounds.' }
            if ($type -eq 1 -and $name -ceq 'GHelper.dll') { [pscustomobject]@{Offset=$o;Size=$s;Compressed=$c} }
        })
        if ($entries.Count -ne 1) { throw 'Expected exactly one embedded GHelper.dll.' }
        $entryOffset=$entries[0].Offset; $entrySize=$entries[0].Size
        if ($entries[0].Compressed -ne 0) { throw 'Compressed assembly: unsupported by this validated extractor. No services changed.' }
        $assembly=[byte[]]::new($entrySize)
        [Array]::Copy($b,$entryOffset,$assembly,0,$entrySize)
    } finally { $reader.Dispose(); $stream.Dispose() }
} else { $assembly=$b }
$lists=[GHelperStaticReader]::Read($assembly)
[pscustomobject]@{
    Executable=$resolved; SHA256=$hash; IsSingleFileBundle=($offset -gt 0)
    BundleVersion=$bundleVersion; AssemblyOffset=$entryOffset; AssemblySize=$entrySize
    services=[string[]]$lists['services']; servicesAC=[string[]]$lists['servicesAC']
}


