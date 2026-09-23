# Kalfa

**A macOS menu bar app with two halves.** Displays — resolution and HiDPI
switching, per-layout profiles, hardware brightness over DDC/CI, smooth mouse
scrolling. And DPI — opening blocked sites through a bundled engine, driven by
rules that turn themselves on and off.

*[Türkçe README](README.md)*

Kalfa started as Klapa, written for one specific failure: close a MacBook's lid
to drive an external monitor, and the desktop stops being Retina. macOS quietly
stops offering the HiDPI mode it was using a moment earlier, and System Settings
has no way to get it back. The DPI half arrived from
[ezDPI](https://github.com/aliakpoyraz/ezdpi), which is now retired — one menu
bar app instead of two.

---

## What it does

| | |
|---|---|
| **Every resolution mode** | Merges the CoreGraphics list with the window server's own, longer one |
| **Hidden HiDPI modes** | The Retina modes macOS withholds when the lid is closed |
| **Refresh rate** | Submenu per resolution, plus a high/60 Hz switch |
| **Pixel-grid check** | Labels every mode `pixel for pixel` / `clean 2×` / `scaled · soft` |
| **Native timing marker** | Says when the active mode is one macOS synthesized rather than one the monitor advertises |
| **Cable signal readout** | Colour format and framebuffer bit depth, e.g. `10-bit YCbCr 4:2:2` |
| **Layout profiles** | Saved per set of connected panels; re-applied automatically when that set appears |
| **DDC/CI brightness + contrast** | Apple Silicon, via `IOAVService` |
| **Confirm-or-revert** | Unverified modes roll back after 15 seconds unless kept |
| **Turkish / English** | Switchable in-app, independent of the system language |
| **Smooth mouse scrolling** | Replays each wheel detent as pixel scrolling, trackpad-style (optional) |
| **Blocked sites** | Kalfa's own proxy engine plus the system proxy, opened only for the domains you list |
| **Rules** | The DPI half turns itself on by app, network or time of day, and off again afterwards |
| **Launch at login** | `SMAppService` |

No network access. Display management needs no permissions; smooth scrolling is
the one exception — reading the scroll wheel requires Accessibility, and it is
only asked for when that switch is turned on.

---

## Smooth scrolling

Off by default, and the only feature that asks for a permission: reading the
scroll wheel means an event tap, and an event tap means Accessibility.

What it does is replace a detent's single jump with the same distance spread
over the next frames, played back on the display's own vertical sync. Its
behaviour is modelled on [Mos](https://github.com/Caldis/Mos) — a floor under
how far one detent travels, a two-stage filter rather than a single decay, the
gesture's own event reposted to the process under the pointer, and no scroll
phases (they make apps add a second layer of inertia). Mos is licensed CC BY-NC,
so none of its code is here; this is a separate implementation of what it does.

Trackpads and the Magic Mouse are passed straight through — they already scroll
in pixels, and re-animating them would fight the driver's own inertia.

---

## Why it reads the window server's private mode list

`CGDisplayCopyAllDisplayModes` only returns modes carrying IOKit's "safe" flag.
SkyLight — the window server — keeps a longer list, and the modes it withholds
on a clamshell MacBook are the ones worth having.

Measured on a MacBook Pro driving an MSI MAG 274QF with the lid closed:

```
CoreGraphics :  139 modes — largest HiDPI is 1280 × 720 (2560 × 1440 px)
SkyLight     :  304 modes — including 2560 × 1440 HiDPI (5120 × 2880 px) at 180 Hz
```

That missing mode is the entire problem. Kalfa finds it in SkyLight's list and
applies it with `CGSConfigureDisplayMode`, staged inside a normal
`CGDisplayConfiguration` transaction so it is atomic and honours the same
persistence rules as any other mode change.

These modes lack the "safe" flag, so selecting one arms a 15-second
**"Does the picture look right?"** countdown. Say nothing and the previous mode
comes back.

---

## The pixel-grid check

A HiDPI switch keeps the logical desktop size and only changes the backing
store. Which combination you land on decides how sharp the result is:

| Logical | Backing store | On a 2560 × 1440 panel | |
|---|---|---|---|
| 2560 × 1440 | 2560 × 1440 | 1:1 | **pixel for pixel** |
| 2560 × 1440 | 5120 × 2880 | exact 2× downscale | **clean 2×** |
| 1920 × 1080 | 3840 × 2160 | 1.5× fractional downscale | **scaled · soft** |

The third row is easy to select by accident and is the usual reason "HiDPI
looks blurry". Kalfa labels every mode and offers a one-click jump to the
sharpest option when you are on a fractional one.

---

## The cable signal readout

The row is deliberately read-only:

```
Cable signal
10-bit YCbCr 4:2:2 · 10-bit framebuffer
```

`YCbCr 4:2:2` halves horizontal colour resolution. Text edges soften and can
fringe. On the machine this was developed against, the link runs 8-bit
YCbCr 4:4:4 with the lid open and 10-bit YCbCr 4:2:2 with it closed — same
resolution, same refresh rate.

**There is no supported way to change this.** It was checked properly:

- No display mode advertises anything but 8 bits per channel, so the mode is not
  the lever.
- HDR is off (EDR reports 1.0), so it is not HDR forcing a 10-bit framebuffer.
- Lowering the refresh rate to 165, 144 or 120 Hz does not change the format, so
  it is not link bandwidth.
- SkyLight exports `SLSGetDisplayPixelEncodingOfLength` and
  `SLSCopyDisplayModePixelEncoding` — getters only. There is no setter.
- DDC/CI has no standard VCP code for link pixel encoding.

So Kalfa reports the value instead of pretending to control it. If yours is
subsampled, the things that can actually help are the monitor's own OSD (DisplayPort
version / input colour format), a different cable, or a different port.

---

## Install

```bash
brew install xcodegen
git clone https://github.com/aliakpoyraz/klapa.git
cd klapa
./build.sh
cp -R dist/Kalfa.app /Applications/
```

The engine is Kalfa's own code (`Packages/EzDPIKit/Sources/EzDPIKit/Proxy`): a local HTTP proxy that reshapes the TLS ClientHello before sending it. No bundled binary, no child process, no third-party licence.

The app is ad-hoc signed. On first launch, right-click → **Open**.

Ad-hoc signing has a cost: the Accessibility grant is tied to the signature, so
every rebuild loses it and smooth scrolling stops until it is granted again. A
real certificate ends that.

### Building a release

```bash
./release.sh 1.0
```

Signs, notarises, staples and produces `dist/Kalfa-1.0.zip`. Two things are
needed first, once: a **Developer ID Application** certificate and a notarisation
credential stored with `xcrun notarytool store-credentials`. The steps are at the
top of `release.sh`.

It uses `ditto` rather than `zip`, which breaks the signature.

**Not on the Mac App Store, and cannot be.** Sandboxing is mandatory there and
most of what Kalfa does is forbidden inside it: the window server's private mode
list (`CGSConfigureDisplayMode` — private API use is a rejection on its own),
`CGEventTap`, the system proxy, scanning and trashing across the home directory,
DDC, AppleScript with administrator rights. None of the apps in this category
are there.

Xcode is required; the Command Line Tools alone cannot build an app bundle.
`build.sh` sets `DEVELOPER_DIR` itself, so `xcode-select` pointing at the
Command Line Tools is not a problem.

**Requirements:** macOS 14 or later. Apple Silicon for DDC brightness; everything
else works on Intel too.

---

## Diagnostics

```bash
/Applications/Kalfa.app/Contents/MacOS/Kalfa --dump
```

Prints every connected display, its active mode, the cable signal, the DDC
reading, and the full mode list with IOKit flags. It calls out an active mode
that is not the panel's native timing.

```
MAG 274QF
  displayID   3
  uuid        A1B2C3D4-0000-0000-0000-000000000000
  active mode 2560 × 1440 (5120 × 2880 px)       180 Hz   [HiDPI,skylight-only,unverified] id=193
  native mode 2560 × 1440 (2560 × 1440 px)       180 Hz   [native] id=130
  link        10-bit YCbCr 4:2:2
  DDC         brightness 100% (100/100), contrast 75% (75/100)
```

---

## Profiles

Stored as plain JSON at `~/Library/Application Support/Klapa/profiles.json` —
the folder keeps its old name so the rename to Kalfa orphans nobody's profiles.
The DPI half keeps its own rules in `~/Library/Application Support/ezDPI/` for
the same reason.

A profile is keyed by **layout**: the sorted set of connected panel UUIDs. This
is the same key macOS uses for its own per-arrangement display settings, which
is why lid-open and lid-closed are two separate records and why one can be
correct while the other is wrong.

Modes are stored by geometry, never by `IODisplayModeID` — the window server
renumbers those after a reconfiguration, so a stored ID goes stale.

---

## Architecture

```
Kalfa/
  Core/        ScreenMode · ScreenInfo · DisplaySetKey · L10n · Watchdog · Diagnostics
  Services/    ModeService     CoreGraphics enumeration and application
               SkyLightModes   the private mode list
               LinkInfo        cable signal and framebuffer readings
               DisplayCenter   state, reconfiguration callback, auto-apply
               ProfileStore · DDCService · AppSettings · LaunchAtLogin
               ScrollService   the wheel event tap and its pixel playback
  Views/       RootView · DisplayCardView · ModePickerView · ScaleToggleView
               LinkRow · DDCControlsView · ProfilesSectionView · SaveProfileView
               SettingsView · ScrollSettingsView · AboutView · SwitchRow
  Bridging/    IOAVService and CGS declarations

Packages/EzDPIKit/   the DPI half, as its own module
  Core/        Supervisor · Engine · SystemProxyController · TOMLGenerator
  Watchers/    AppWatcher · NetworkWatcher · ScheduleWatcher
  UI/          MenuPanel (the DPI tab) · SettingsView (the DPI window)
  Facade.swift what the app target may touch: start, shutdown, URLs, two views
```

Both halves arrived as separate menu bar apps, and both define a `Log`, a
`Diagnostics`, a `SettingsView` and an `L10n`. The module boundary settles that
without renaming a type on either side; `Facade.swift` is the only public
surface.

Every window server call goes through `Watchdog`.
`CGCompleteDisplayConfiguration` can block indefinitely during a
reconfiguration, which is exactly when Kalfa is doing its work, and the menu bar
must not freeze.

### Private API notes

- `CGSConfigureDisplayMode`'s first parameter is a `CGDisplayConfigRef` from
  `CGBeginDisplayConfiguration`, **not** a CGS connection ID. Passing a
  connection ID segfaults inside SkyLight, which dereferences it as the config
  object.
- `CGSGetDisplayModeDescriptionOfLength` expects a 212-byte (`0xD4`) struct.
  Offsets: mode number `0x00`, flags `0x04`, width `0x08`, height `0x0C`,
  depth `0x10`, refresh rate `0xBE` (`uint16`), density `0xD0` (`float`).
- SkyLight exists only inside the dyld shared cache, so `SLS*` symbols cannot be
  linked. They are resolved with `dlopen` + `dlsym` and degrade to "unavailable"
  if missing.
- A `ScrollView` inside a `MenuBarExtra` window resolves to zero ideal height and
  silently swallows its content.

---

## Not included

Virtual displays, gamma and colour temperature, ICC profile switching, notch
hiding, brightness-key interception. [BetterDisplay](https://github.com/waydabber/BetterDisplay)
and [FreeDisplay](https://github.com/huberdf/FreeDisplay) cover those.

## Credits

Written with BetterDisplay and FreeDisplay as references for which private APIs
exist and how the DDC/CI wire format is framed on Apple Silicon.

## License

MIT — see [LICENSE](LICENSE).
