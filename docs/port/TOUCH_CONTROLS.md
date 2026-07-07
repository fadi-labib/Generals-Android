# Touch Controls — Design, Implementation & Debugging

> Everything about how a 2003 mouse-only RTS became playable with fingers, shared by
> the iOS/iPadOS and Android ports. Last updated 2026-07-07 after the Android gesture
> work (commits `c8be2d416`, `ffa4645e9`).

## The problem

The engine understands exactly one input device: a mouse. Its GUI (window gadgets),
unit selection, command issuing, and camera all consume left/right button events,
motion, and a wheel. SDL3 on a touch device delivers raw finger events instead — and
the naive mapping (SDL's built-in touch→mouse synthesis) fails in game-specific ways:
a finger landing is not yet a click (it might become a drag-box or a camera pan), a
stray click has real consequences (it sets rally points and issues orders), and the
2003 GUI expects the cursor to *hover* over a widget before clicking it.

## The gestures (user-facing)

| Gesture | Mouse translation | Game effect |
|---|---|---|
| 1-finger tap | hover motion, then left click at the press point | select / command / activate button |
| 1-finger drag (> threshold) | left-button drag anchored at the press point | selection box; drag scroll bars |
| 1-finger long-press (600 ms, stationary) | right click | deselect |
| 2-finger drag | right-button drag at the finger centroid | camera scroll (classic RTS semantics) |
| 2-finger pinch | mouse wheel ticks (±1 per 3% distance change) | camera zoom |

Two-finger pan and pinch are **mutually exclusive per gesture** (see mode-locking
below): whichever motion crosses the threshold first wins until a finger lifts.

## Where the code lives

| File | What |
|---|---|
| `GeneralsMD/Code/GameEngineDevice/Source/SDL3GameEngine.cpp` | The whole gesture translator (state machine, synthetic event injection, long-press polling) plus the background render-pause. All guarded by `GX_TOUCH_UI` = iOS \|\| Android. |
| `GeneralsMD/Code/Main/SDL3Main.cpp` | `SDL_SetHint(SDL_HINT_TOUCH_MOUSE_EVENTS, "0")` — disables SDL's own touch→mouse synthesis so the translator is the only source of mouse events. |
| `GeneralsMD/Code/GameEngine/Source/GameClient/GUI/GUICallbacks/Menus/MainMenu.cpp` | Touch-only auto-reveal of the main menu (desktop waits for mouse movement; see "The first-tap trap"). |

The translator feeds synthetic `SDL_Event`s into `SDL3Mouse::addSDLEvent` — the same
entry point a physical mouse uses — so everything downstream (coordinate scaling,
message stream, GUI, gameplay) is untouched and cannot tell it's a touchscreen.

## The state machine

```
                     finger1 down                    moved ≥ threshold
          IDLE ───────────────────────► PENDING ─────────────────────► DRAGGING
           ▲   (send hover MOTION only)    │                              │
           │                               │ stationary 600 ms            │ finger1 up
           │                               ▼                              ▼ (LMB up)
           │                          LONGPRESSED                       IDLE
           │                          (RMB click sent,
           │                           swallow until lift)
           │
           │        finger2 down (from PENDING or DRAGGING*)
           │      ┌───────────────────────────────────────────┐
           │      ▼                                           │
           │  TWO_PENDING ──centroid moved ≥ threshold──► PAN (RMB held at centroid)
           │      │                                           │
           │      └──distance changed ≥ threshold───────► PINCH (wheel ticks only)
           │                                                  │
           └──────────────── any tracked finger up ───────────┘
                     (PAN releases RMB; TWO_PENDING/PINCH hold no buttons)

* from DRAGGING, the in-flight drag-box is completed (LMB up) first.
```

States: `IDLE`, `PENDING`, `DRAGGING`, `LONGPRESSED`, `TWO_PENDING`, `PAN`, `PINCH`
(`TouchState::Phase` in SDL3GameEngine.cpp).

## Design decisions and their reasons

Each of these was forced by a real failure, not invented up front.

### 1. Deferred commitment
A finger landing sends **no button event** — only a cursor motion. The gesture could
still become a tap, a drag-box, a long-press, or the first finger of a pan; a
premature left-down+up is a *real click* to the game (e.g. it sets a rally point when
a production building is selected). The button output is decided only when the
gesture identity is known: click at finger-up, drag-anchor at threshold-crossing,
right-click at the 600 ms mark, nothing at all for two-finger gestures.

### 2. Hover before click
The synthetic motion sent at finger-down is not cosmetic. The 2003 GUI has
hover-driven widgets — e.g. the Generals Challenge general-select buttons are
checkboxes that *ignore clicks* unless a prior mouse-enter set their
`WIN_STATE_HILITED`. A real mouse always hovers before clicking; a synthetic tap that
teleports and clicks in the same instant never triggers mouse-enter. Moving the
cursor at finger-down gives the GUI the finger-down→finger-up interval (a human tap
is 80–300 ms ≈ several frames) to process hover before the click commits.

Consequence for automation: `adb shell input tap` has a **0 ms** down-up gap — hover
and click land in the same frame and menus don't activate. Use
`adb shell input swipe X Y X Y 150` to emulate a real tap. This is an artifact of
instant synthetic taps only; real fingers are never that fast.

### 3. Physical (DPI-scaled) thresholds — `gestureThresholdPx()`
The original fixed `8 px` tap/drag threshold is ~0.7 mm on a Galaxy Tab S7+
(2800×1752, ~274 ppi): fingertip jitter crosses it and taps become accidental
drag-boxes. Thresholds are now **3 mm** converted to pixels via
`SDL_GetDisplayContentScale` (px/mm = 160·scale/25.4), clamped to ≥ 8 px so no
platform gets *more* sensitive than the historical behavior. The same physical
threshold drives tap-vs-drag and pan-vs-pinch classification.

### 4. Two-finger mode-locking (pan XOR pinch)
The first implementation ran pan (held RMB at the centroid) and pinch (wheel ticks on
distance change) **simultaneously** from the same two fingers. Physics makes that
unusable: panning fingers never keep their distance constant (spurious zoom steps),
and pinching fingers never keep their centroid still (camera drift while zooming).
`TWO_PENDING` measures both signals from the second finger's landing and locks the
gesture to whichever crosses the threshold first; the loser is ignored until a finger
lifts. Desktop can't scroll and zoom simultaneously either, so this *is* the original
feel. With interference gone, the pinch step was halved (6% → 3% distance change per
wheel tick) for smoother zoom.

### 5. Drag anchoring
When a drag commits (movement ≥ threshold), the left-button-down is sent at the
**original** finger-down position, not the current one — so selection boxes start
where the finger first landed, exactly like a mouse press-then-move.

### 6. Cancelled touches never click
`SDL_EVENT_FINGER_CANCELED` (incoming call, notification shade, palm rejection) in
the `PENDING` state drops the gesture without sending the deferred click. Otherwise a
cancellation would ghost-click at the cancel point — a phantom rally point or move
order.

### 7. Long-press needs frame polling
A perfectly stationary finger emits **no SDL events**, so no event handler could ever
fire the 600 ms right-click. `updateTouchLongPress()` is called once per engine frame
from the event-poll loop to check the timer. Because no left-button was sent yet
(deferred commitment), the right-click is clean.

### 8. Exactly one source of mouse events
`SDL_HINT_TOUCH_MOUSE_EVENTS=0` turns off SDL's built-in synthesis, and the event
loop additionally drops any mouse event whose `which == SDL_TOUCH_MOUSEID`
(belt-and-braces). Without this every tap arrives twice — once from SDL, once from
the translator — producing phantom second clicks.

### 9. Synthetic events carry the real windowID
`SDL3Mouse::scaleMouseCoordinates()` looks the window up by ID to map window points
into the game's internal resolution and **silently skips scaling** when the lookup
fails. Every synthetic event is stamped with `SDL_GetWindowID(window)`.

### 10. The first-tap trap: main menu auto-reveal (touch platforms only)
The main menu is a desktop design: it boots into a hidden state (`notShown`) and
waits for the mouse to move 20 px (`MainMenuInput`, `GWM_MOUSE_POS`) before playing
its reveal transition. On touch there is no idle mouse motion — the first tap's hover
triggered the reveal, and the tap's deferred click landed **mid-transition** while
the buttons were still transition-hidden. Hit-testing (`GameWindow::winPointInChild`)
skips hidden windows, so the click fell through to the parent window and died — the
user's entire first tap was spent "waking" the menu. Fix: on `GX_TOUCH_UI` platforms
`MainMenuUpdate` revives the engine's own (commented-out) auto-show path — the menu
reveals itself after the intro logo delay, and the first tap acts on a button.

## Tunables

All in `SDL3GameEngine.cpp` (anonymous namespace):

| Constant | Value | Meaning |
|---|---|---|
| `LONG_PRESS_MS` | 600 | stationary hold before right-click fires |
| `PINCH_STEP_RATIO` | 0.03 | fractional finger-distance change per wheel tick |
| `GESTURE_THRESHOLD_MM` | 3.0 | physical movement that commits tap→drag and locks pan/pinch |
| (floor) | 8 px | minimum threshold if the display query fails or DPI is very low |

## How a tap flows through the engine (debugging map)

A confirmed-good trace of one tap, stage by stage — instrument any link when touch
misbehaves (this exact method found the first-tap trap):

```
1. SDL_EVENT_FINGER_DOWN/UP        SDL3GameEngine.cpp pollSDL3Events → handleTouchEvent
2. synthetic SDL_Event             sendSyntheticMouse → SDL3Mouse::addSDLEvent (ring buffer)
3. MouseIO events                  SDL3Mouse::getMouseEvent ← Mouse::updateMouseData (drains per frame)
4. GameMessages                    Mouse::createStreamMessages → MSG_RAW_MOUSE_LEFT_BUTTON_DOWN/UP
                                   (position args scaled to game-internal resolution)
5. GWM window messages             WindowXlat::translateGameMessage → winProcessMouseEvent
                                   (findWindowUnderMouse descends to deepest VISIBLE+ENABLED child;
                                    LEFT_DOWN sets m_grabWindow; LEFT_UP routes to the grab window)
6. Gadget action                   GadgetPushButtonInput: LEFT_DOWN sets WIN_STATE_SELECTED,
                                   LEFT_UP fires GBM_SELECTED if still selected
```

Gotchas verified on-device:

- **Hidden ancestors block hit-testing but not necessarily rendering.** During menu
  transitions windows flip `WIN_STATUS_HIDDEN` frame-by-frame; a click routed while a
  container is hidden falls through to the parent even though the button appears on
  screen. If clicks "vanish" on a menu, suspect an in-flight transition first.
- The per-frame `MSG_RAW_MOUSE_POSITION` is appended **before** the event loop runs,
  so it carries the *previous* frame's position; button messages carry their own
  correct positions. Hover state therefore lags clicks by one frame — harmless with
  deferred taps (many frames between hover and click), fatal for 0 ms synthetic taps.
- `git log -S TOUCHDBG` shows the exact probe points used for the 2026-07-07
  investigation (added and removed within the `ffa4645e9` session): translator
  in/out, mouse stream append, window routing + a recursive containing-window dump,
  and button receipt.

## Verifying touch after a change (Tab S7+ recipe)

```bash
# fresh boot to a settled menu (shell map rendered = screenshot > 2MB)
adb shell am force-stop com.generalsx.generalszh
adb shell am start -n com.generalsx.generalszh/.GeneralsXZHActivity
# single tap = 150-300ms swipe-in-place; menu button must activate on ONE tap
adb shell input swipe 2111 393 2111 393 300   # SOLO PLAY on 2800x1752
adb exec-out screencap -p > check.png          # submenu (USA/GLA/CHINA/...) must show
```

Pan/pinch/drag-box feel can't be exercised through adb (no multitouch injection) —
those need fingers on glass in a skirmish.

## Known limitations / future work

- Gesture feel unvalidated in real matches (box-select under pressure, pan/zoom
  mid-battle); thresholds may need per-gesture tuning.
- No edge-of-screen camera scroll (desktop moves the camera when the cursor touches
  a screen edge; with touch the cursor "jumps", so edge scroll triggers spuriously —
  currently mitigated by the game's own scroll handling but worth a dedicated pass).
- No keyboard-dependent controls (control groups, attack-move modifier); an on-screen
  affordance would be needed.
- iOS uses this same code; any tuning change here changes iPhone/iPad feel too —
  test both before shipping.
