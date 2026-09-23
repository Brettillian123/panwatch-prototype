# PanWatch prototype

The vision trigger from the cooking assistant, as a working iPhone app. Prop the phone at
the back of the stove, draw a box around the pan, and when you add an ingredient during
a step that calls for it, the app says "Looks like the pasta went in. Start a 9-minute
timer?"

It uses only what ships with iOS: the camera, Apple's built-in hand-pose model (Vision),
and on-device speech. No trained model, no network, and no video is saved.

## How it decides

1. **The recipe decides when to look.** The camera only judges steps that add something
   ("Add the pasta"). During "Bring water to a boil" it is switched off, so stirring and
   walking past are never judged.
2. **Lock the camera.** When you confirm the pan box, exposure, white balance, and focus
   lock. The picture of the pan then only changes when the pan does.
3. **A hand has to visit.** Apple's hand-pose model tracks hands 15 times a second. A
   visit counts when a hand spends at least 0.3 s over the pan, then leaves.
4. **Compare before and after.** Once the pan stops moving, a 64-pixel color thumbnail of
   it is compared with one taken just before the hand arrived. If at least 5% of the pan
   changed in brightness or color, it's an addition. If the whole pan shifted evenly, it's
   a light switching on, and it's ignored.
5. **Offer, never act.** An addition becomes a spoken offer. A volume button or Camera
   Control press accepts it. A false alarm costs one tap; a miss costs nothing.

The decision logic (`PanWatch/Core`) is plain Swift with no Apple frameworks, and is
covered by unit tests in `Tests/` (`swift test` runs them on any machine with Swift).

## First-time setup on the Mac

You need an Xcode version at least as new as your iPhone's iOS (iOS 27 needs Xcode 27).

1. **Install Xcode** from the Mac App Store and open it once so it can install its
   components. If it asks which platforms to download, iOS is the one you need.
2. **Sign in:** Xcode > Settings > Accounts > `+` > Apple ID. A free Apple ID works.
3. **Connect to GitHub:** Xcode > Settings > Accounts > `+` > GitHub. Xcode asks for a
   token. On github.com go to Settings > Developer settings > Personal access tokens >
   Tokens (classic) > Generate new token, tick **repo**, generate, and paste it into Xcode.
4. **Get the code:** close Settings, then File > Clone (or "Clone Git Repository" on the
   welcome window), pick `panwatch-prototype`, and choose a folder. If Xcode asks what to
   open, pick **PanWatch.xcodeproj** (not Package.swift).
5. **Set signing:** click the blue PanWatch project at the top of the left sidebar, then
   the PanWatch target > Signing & Capabilities > Team > pick your name (Personal Team).
   If it says the bundle identifier is taken, change `com.brettillian123.panwatch` to
   anything unique, like `com.brettillian123.panwatch2`.
6. **Connect the iPhone** with a USB-C cable, unlock it, and tap **Trust**. In Xcode's top
   bar, click the device menu (next to "PanWatch") and pick your iPhone.
7. **Turn on Developer Mode** on the iPhone: Settings > Privacy & Security > Developer
   Mode > On. The phone restarts and asks you to confirm.
8. **Run:** press the ▶ button (or Cmd-R). The first build takes a few minutes.
9. **Trust yourself on the phone:** the first launch is blocked as an "Untrusted
   Developer". On the iPhone go to Settings > General > VPN & Device Management, tap your
   Apple ID, tap Trust, then press ▶ in Xcode again.

If Xcode offers to "Update to recommended settings", either choice is fine.

**Free Apple ID builds stop opening after 7 days.** Plug in and press ▶ again to renew.
Do this the day before any presentation.

## Getting updates

Xcode menu: Integrate > Pull. Then press ▶.

If the build fails, copy the red error text from Xcode's Issue navigator (the ⚠ icon in
the left sidebar) and send it over.

## Using it

- **Mark the pan:** tap the pan for a quick box, or drag to draw one, then **Start
  watching**. Keep the phone still from then on. If you move the phone, mark the pan again.
- **Next step / Back:** buttons along the bottom, or press a volume button for Next.
- **Waveform button:** opens the detection panel: live state, hand tracking dots, a meter
  of how much the pan differs from its before-picture, the last decision with before, after,
  and changed-pixel pictures, and sliders for tuning. Tuning is saved between launches.
- **Fast timers** (in the panel): timers count seconds instead of minutes, for rehearsing.
- The volume buttons control the app while it's open, so set the volume before launching.

## Demo: cold pan on a table

1. Set the phone in landscape, propped so the front camera sees a pan on the table in
   front of it, raised a little above the rim and angled down into the pan. Good, even
   lighting helps. A dark pan with pale dry pasta gives the clearest result.
2. Launch, draw the box around the inside of the pan, tap **Start watching**.
3. Step 1 shows "Camera not needed for this step". Press **Next step**.
4. Step 2, "Add the pasta", shows **Watching for the pasta** and the box turns green.
5. Reach over the pan, drop in a handful of dry pasta, pull your hand away. The box turns
   yellow while your hand is there, orange while it checks, and then the offer appears.
6. Press a volume button. The 9-minute timer starts and the recipe moves to step 3.

To show the gating, reach into the pan during step 3: nothing happens, because that step
doesn't add anything.

## Layout

```
PanWatch/
  Core/       Detection logic, pure Swift, unit-tested (AdditionDetector, PanPatch, geometry, recipe)
  Camera/     Capture session, hand-pose detection, frame analysis
  Session/    Recipe state, suggestions, timers, speech
  Views/      SwiftUI screens
Tests/        Unit tests for Core
Package.swift Builds Core and its tests with `swift test`
```
