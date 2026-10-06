#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstdio>
#include <cwchar>
#include <cstdlib>
HWND game=nullptr;DWORD gamePid=0;
BOOL CALLBACK find(HWND w,LPARAM){DWORD pid;GetWindowThreadProcessId(w,&pid);HANDLE p=OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,FALSE,pid);wchar_t path[1024]{};DWORD n=1024;if(p){QueryFullProcessImageNameW(p,0,path,&n);CloseHandle(p);if(wcsstr(path,L"PalCraft-Client\\Pal\\Binaries\\Win64\\Palworld-Win64-Shipping.exe")&&IsWindowVisible(w)){game=w;gamePid=pid;return FALSE;}}return TRUE;}
int main(int argc,char**argv){EnumWindows(find,0);if(!game)return 2;ShowWindow(game,SW_RESTORE);SetForegroundWindow(game);BringWindowToTop(game);Sleep(250);
 if(argc>2&&!strcmp(argv[1],"key")){int k=atoi(argv[2]),ms=argc>3?atoi(argv[3]):150;INPUT i{};i.type=INPUT_KEYBOARD;i.ki.wScan=(WORD)MapVirtualKeyW(k,MAPVK_VK_TO_VSC);i.ki.dwFlags=KEYEVENTF_SCANCODE;SendInput(1,&i,sizeof i);Sleep(ms);i.ki.dwFlags|=KEYEVENTF_KEYUP;SendInput(1,&i,sizeof i);}
 if(argc>3&&!strcmp(argv[1],"mouse")){INPUT i{};i.type=INPUT_MOUSE;i.mi.dwFlags=MOUSEEVENTF_MOVE;i.mi.dx=atoi(argv[2]);i.mi.dy=atoi(argv[3]);SendInput(1,&i,sizeof i);}
 if(argc>1&&!strcmp(argv[1],"close"))PostMessageW(game,WM_CLOSE,0,0);
 DWORD foreground=0;GetWindowThreadProcessId(GetForegroundWindow(),&foreground);FILE*f=fopen("D:/PalworldServer-LAN/PalCraft-Dev/bridge/game-input-result.json","wb");if(f){fprintf(f,"{\"pid\":%lu,\"foreground\":%lu,\"matched\":%s}",gamePid,foreground,gamePid==foreground?"true":"false");fclose(f);}return 0;
}
