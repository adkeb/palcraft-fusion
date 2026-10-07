# Camera stall retains selected form intent

The player-selected build/menu mode now survives a temporary inactive camera while the same websocket connection remains and actions are not suspended. The original750ms camera rule remains in the unchanged palcraft object. Input/live eligibility, focus, lost-focus key/button release, movement/use, camera transmission and the two-engine exclusive hook are unchanged. This separates remembered choice from permission to execute input.

Websocket disconnect, new connection generation, and inactive+suspended stop still clear the original mode/menu setter. The existing active F5 branch and non-menu ESC remain as before. An added exit-only F5 branch during an inactive camera requires already-selected build, a new key-down edge, the same connection, actual foreground process and original fresh platform focus, and no suspension. It can only call the original false setter, never enable form or stale input.

The existing generation-scoped one-shot form request now applies eligibility only to on requests. An explicit same-generation off can clear retained intent during a stall. On still requires eligibility and no suspension; new-generation/mismatched requests remain rejected. The normal Stop still suspends actions before cleanup and publishes inactive camera, allowing native clear so Title input is not swallowed.

Four bounded native source cases use the actual form-request header/setter and reset/live/exit predicates extracted from production source. All proof/focus data are synthetic. Run `c++ -std=c++17 -O2 checks/form_intent.cpp -o LOCAL_CHECK` and `LOCAL_CHECK`. They do not activate a Game window or issue input.

Actual build compiled only controls.cpp and linked original exact f4dad palcraft/ws/compositor objects, using existing Zig0.15.2, sequential nice19. Seven exports/imports/AMD64 PE format, binary snapshot headers, SourceRoot paths and the nine diagnostic fields are preserved. This isolated DLL was not installed or executed; actual play/Title acceptance remains the sole runtime owner's work.
