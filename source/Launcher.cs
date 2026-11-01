using System;
using System.Diagnostics;
using System.IO;
using System.Security.Principal;
using System.Windows.Forms;
class Launcher {
 [STAThread] static void Main(){try{
  string dir=AppDomain.CurrentDomain.BaseDirectory;
  string pathFile=Path.Combine(dir,"runtime","powershell-path.txt");
  string pwsh=File.Exists(pathFile)?File.ReadAllText(pathFile).Trim():"";
  if(!File.Exists(pwsh)){
   string regular=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),"PowerShell","7","pwsh.exe");
   pwsh=File.Exists(regular)?regular:Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Microsoft","WindowsApps","pwsh.exe");
  }
  bool admin=new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator);
  var info=new ProcessStartInfo(pwsh,"-NoProfile -STA -WindowStyle Hidden -File \""+Path.Combine(dir,"runtime","Tray.ps1")+"\"");
  info.WorkingDirectory=dir;info.UseShellExecute=true;info.WindowStyle=ProcessWindowStyle.Hidden;
  if(!admin)info.Verb="runas";
  Process.Start(info);
 }catch(Exception e){MessageBox.Show(e.Message,"GHelper Companion",MessageBoxButtons.OK,MessageBoxIcon.Error);}}
}


