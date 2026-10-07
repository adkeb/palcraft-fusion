#pragma once
#include <string>
#include "ws.h"
void controls_tick(WsClient &, bool active);
void controls_feedback(const std::string &message);
double controls_viewport_aspect();
void controls_suspend_actions(bool paused);
void controls_request_form(bool on);
