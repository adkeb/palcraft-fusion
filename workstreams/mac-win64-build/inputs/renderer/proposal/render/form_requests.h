#pragma once
#include <atomic>
#include <cstdint>

// A one-shot explicit mode request, scoped to the actual controls connection.
// Repeated submissions coalesce to the newest desired state; they never toggle.
class PalCraftFormRequests {
 std::atomic<int32_t> generation{-1};
 std::atomic<uint64_t> pending{0};
public:
 void observed_generation(int32_t actual){generation=actual;}
 void submit(bool on){
  const auto actual=generation.load();
  if(actual<0)return;
  pending=(uint64_t(uint32_t(actual))<<2)|(on?2:1);
 }
 int take(int32_t actual,bool eligible,bool new_connection,bool suspended){
  const auto request=pending.exchange(0);
  if(!request||!eligible||new_connection||uint32_t(request>>2)!=uint32_t(actual))return -1;
  const bool on=(request&3)==2;
  return on&&suspended?-1:(on?1:0);
 }
};

// F5, ESC, session exit, and operator requests share the same mode transition.
inline bool palcraft_set_form_mode(std::atomic<bool>& build,std::atomic<bool>& menu,bool on){
 const bool previous=build.exchange(on);
 if(!on)menu=false;
 return previous!=on;
}
