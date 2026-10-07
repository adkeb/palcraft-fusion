#pragma once
// Production expressions extracted exactly; focus/time data in tests are synthetic.
inline bool actual_reset(bool active,bool connected,bool newConnection,bool suspended){return !connected||newConnection||(!active&&suspended);}
inline bool actual_live(bool active,bool connected,bool ownForeground,bool platformFocus,bool suspended){return active&&connected&&ownForeground&&platformFocus&&!suspended;}
inline bool actual_exit_only(bool active,bool selectedBuild,bool newConnection,bool f5Down,bool f5Was,bool connected,bool ownForeground,bool suspended,bool platformFocus){return !active&&selectedBuild&&!newConnection&&f5Down&&!f5Was&&connected&&ownForeground&&!suspended&&platformFocus;}
