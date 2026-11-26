$ErrorActionPreference = 'Stop'
# Diagnostic only: disposable files, no application build or security-policy changes.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.ComponentModel;
using Microsoft.Win32.SafeHandles;
public static class MrAclProbe {
  [StructLayout(LayoutKind.Sequential)] public struct SA { public int nLength; public IntPtr lpSecurityDescriptor; public int bInheritHandle; }
  [StructLayout(LayoutKind.Sequential)] public struct SIDATTR { public IntPtr Sid; public uint Attributes; }
  [StructLayout(LayoutKind.Sequential)] public struct MAP { public uint Read, Write, Execute, All; }
  [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool ConvertStringSecurityDescriptorToSecurityDescriptor(string s, uint rev, out IntPtr sd, IntPtr size);
  [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool ConvertStringSidToSid(string s, out IntPtr sid);
  [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool ConvertSecurityDescriptorToStringSecurityDescriptor(IntPtr sd, uint rev, uint flags, out IntPtr s, IntPtr size);
  [DllImport("advapi32.dll", CharSet=CharSet.Unicode)] static extern uint GetNamedSecurityInfo(string name, uint type, uint info, out IntPtr owner, out IntPtr group, out IntPtr dacl, out IntPtr sacl, out IntPtr sd);
  [DllImport("advapi32.dll", CharSet=CharSet.Unicode)] static extern uint SetNamedSecurityInfo(string name, uint type, uint info, IntPtr owner, IntPtr group, IntPtr dacl, IntPtr sacl);
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool CreateRestrictedToken(IntPtr token, uint flags, uint count, ref SIDATTR disable, uint delCount, IntPtr del, uint restrictCount, IntPtr restrict, out IntPtr result);
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool DuplicateToken(IntPtr token, int level, out IntPtr result);
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool AccessCheck(IntPtr sd, IntPtr token, uint desired, ref MAP map, IntPtr privileges, ref uint size, out uint granted, out bool allowed);
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool ImpersonateLoggedOnUser(IntPtr token);
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool RevertToSelf();
  [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr p);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true, EntryPoint="CreateFileW")] static extern SafeFileHandle CreateFile(string path,uint access,uint share,ref SA sa,uint creation,uint flags,IntPtr template);
  static void Check(bool ok) { if(!ok) throw new Win32Exception(Marshal.GetLastWin32Error()); }
  static void CheckCode(uint code) { if(code!=0) throw new Win32Exception((int)code); }
  static string Sddl(IntPtr sd) { IntPtr str; Check(ConvertSecurityDescriptorToStringSecurityDescriptor(sd,1,7,out str,IntPtr.Zero)); try { return Marshal.PtrToStringUni(str); } finally { LocalFree(str); } }
  static void ReadDescriptor(string label,string path,IntPtr token) {
    IntPtr o,g,d,s,sd; CheckCode(GetNamedSecurityInfo(path,1,7,out o,out g,out d,out s,out sd));
    try {
      Console.WriteLine(label+"_SDDL="+Sddl(sd));
      var map=new MAP{Read=0x120089,Write=0x120116,Execute=0x1200a0,All=0x1f01ff};
      uint size=1024,granted; bool allowed; IntPtr privileges=Marshal.AllocHGlobal((int)size);
      try { Check(AccessCheck(sd,token,0x02000000,ref map,privileges,ref size,out granted,out allowed)); Console.WriteLine(label+"_ACCESSCHECK="+allowed+"; MASK=0x"+granted.ToString("X8")); }
      finally { Marshal.FreeHGlobal(privileges); }
    } finally { LocalFree(sd); }
    Check(ImpersonateLoggedOnUser(token));
    try {
      foreach(uint mask in new uint[]{0x120089,0x1200a0,0x00000002,0x00040000}) {
        var sa=new SA{nLength=Marshal.SizeOf(typeof(SA))};
        using(var h=CreateFile(path,mask,7,ref sa,3,0x80,IntPtr.Zero)) {
          int err=Marshal.GetLastWin32Error();
          Console.WriteLine(label+"_OPEN_"+mask.ToString("X8")+"="+(!h.IsInvalid)+"; ERROR="+(h.IsInvalid?err:0));
        }
      }
    } finally { Check(RevertToSelf()); }
  }
  public static void Run(string root) {
    IntPtr original=IntPtr.Zero,restricted=IntPtr.Zero,token=IntPtr.Zero,admin=IntPtr.Zero,user=IntPtr.Zero,sd=IntPtr.Zero;
    string sid=WindowsIdentity.GetCurrent().User.Value;
    try {
      Check(OpenProcessToken(GetCurrentProcess(),0x000a,out original));
      Check(ConvertStringSidToSid("S-1-5-32-544",out admin));
      Check(ConvertStringSidToSid(sid,out user));
      var disabled=new SIDATTR{Sid=admin};
      Check(CreateRestrictedToken(original,1,1,ref disabled,0,IntPtr.Zero,0,IntPtr.Zero,out restricted));
      Check(DuplicateToken(restricted,2,out token));
      foreach(string variant in new string[]{"default","owner_at_creation","owner_after_creation"}) {
        string path=System.IO.Path.Combine(root,variant+".tmp");
        string dacl="D:P(A;;FA;;;SY)(A;;FA;;;BA)(A;;FRFX;;;OW)";
        string spec=variant=="owner_at_creation"?"O:"+sid+dacl:dacl;
        Check(ConvertStringSecurityDescriptorToSecurityDescriptor(spec,1,out sd,IntPtr.Zero));
        try {
          var sa=new SA{nLength=Marshal.SizeOf(typeof(SA)),lpSecurityDescriptor=sd};
          using(var h=CreateFile(path,0xc0010000,1,ref sa,1,0x80,IntPtr.Zero)) { Check(!h.IsInvalid); }
        } finally { LocalFree(sd); sd=IntPtr.Zero; }
        if(variant=="owner_after_creation") CheckCode(SetNamedSecurityInfo(path,1,1,user,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero));
        ReadDescriptor(variant,path,token);
      }
    } finally {
      if(sd!=IntPtr.Zero)LocalFree(sd); if(user!=IntPtr.Zero)LocalFree(user); if(admin!=IntPtr.Zero)LocalFree(admin);
      if(token!=IntPtr.Zero)CloseHandle(token); if(restricted!=IntPtr.Zero)CloseHandle(restricted); if(original!=IntPtr.Zero)CloseHandle(original);
    }
  }
}
'@
$root = Join-Path $env:TEMP ("mr-acl-probe-" + [Guid]::NewGuid())
New-Item -ItemType Directory -Path $root | Out-Null
try { [MrAclProbe]::Run($root); Write-Host 'WINDOWS_ACL_PROBE_COMPLETED (diagnostic, not a security test pass)' }
finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Continue }
