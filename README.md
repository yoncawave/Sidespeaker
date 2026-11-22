# Sidespeaker

Use your phone as a PC speaker over a USB cable. A small program on the PC captures whatever it is playing and streams it through the cable to an app on the phone. No Wi-Fi, no account, no cost.

Version 2.0 works with several phones at once, iPhones and Android phones mixed. Pick which ones play, and optionally turn on surround sound and drag each phone to where it sits in the room.

| | iPhone | Android |
|---|---|---|
| Windows PC | supported | supported |
| Linux PC | planned | planned |
| macOS PC | planned | planned |

## How it works

- **PC sender (`sender/`):** captures system audio (WASAPI loopback on Windows), finds every phone plugged in, and sends each selected phone its own raw 16-bit PCM stream. A short header (sample rate and channel count) comes first. In surround mode a mixer works out what each phone plays from where it sits.
  - **iPhone:** through the Apple usbmuxd service that ships with iTunes and the Apple Devices app.
  - **Android:** through `adb forward`, which tunnels a port on the PC to a port on the phone.
- **iPhone app (`ios/`):** a SwiftUI app that listens on a TCP port and plays the stream with AVAudioEngine. Built on GitHub Actions, so no Mac is needed.
- **Android app (`android/`):** a Kotlin app with a foreground service that plays the stream with AudioTrack, so it keeps playing with the screen off. Built on GitHub Actions.

The sender keeps the stream continuous by filling silent moments with silence, and reconnects by itself when the cable is unplugged and replugged.

## Repository layout

```
sender/    PC sender (C++, CMake)
installer/ Windows installer script (Inno Setup)
ios/       iPhone app (Swift, built with XcodeGen)
android/   Android app (Kotlin, Gradle)
.github/   CI: one workflow per target
```

## Get the builds

Every push builds what changed. Open the **Actions** tab, pick the latest run of the workflow you need, and download the artifact at the bottom of the page:

| Workflow | Artifact | Contents |
|---|---|---|
| sender | Sidespeaker-installer | `Sidespeaker-Setup.exe` |
| sender | Sidespeaker-windows | `sidespeaker.exe` and `config.ini` (portable) |
| ios | Sidespeaker-ipa | `Sidespeaker.ipa` |
| android | Sidespeaker-apk | `Sidespeaker.apk` |

Artifacts download as a zip. You can also start any workflow by hand with **Run workflow**.

## Install on Windows

Run `Sidespeaker-Setup.exe`. It installs for your user only (no admin needed) and adds a Start menu entry with an **Edit config** shortcut. It can also add a desktop shortcut or start Sidespeaker when you sign in. Upgrading keeps your `config.ini`. Uninstall from Settings > Apps.

The installer is not code-signed, so Windows SmartScreen may warn. Choose **More info**, then **Run anyway**. The installer has two optional components, both ticked in the full installation: **iPhone support** installs Apple Devices from the Microsoft Store through `winget`, and **Android support** downloads Android platform-tools from Google into the install folder. Sidespeaker uses that bundled `adb` automatically unless `adb_path` is set. The Store install needs `winget` (App Installer), which comes with Windows 11 and current Windows 10.

The portable `sidespeaker.exe` reads the `config.ini` that sits next to it.

## Build the PC sender yourself

Requires Visual Studio with the C++ workload (it includes CMake). From "x64 Native Tools Command Prompt for VS":

```
cmake -S . -B build
cmake --build build --config Release
```

The exe and a copy of `config.ini` end up in `build\bin\Release`.

## Build the installer yourself

Install [Inno Setup 6](https://jrsoftware.org/isinfo.php), build the sender as above, then:

```
cmake --install build --config Release --prefix dist
iscc installer\sidespeaker.iss
```

The result is `installer-out\Sidespeaker-Setup.exe`. Pass `/DAppVersion=1.2.3` to `iscc` to set the version.

## Set up the phone

### iPhone

1. Install Apple Devices (or iTunes) on the PC. The installer can do this for you.
2. Sideload `Sidespeaker.ipa` with Sideloadly or AltStore. With a free Apple ID it expires after 7 days; re-sideload to refresh.
3. Plug in the iPhone, unlock it, and tap **Trust** the first time.

### Android

1. Install `Sidespeaker.apk` (copy it to the phone, or `adb install Sidespeaker.apk`). Allow installs from unknown sources if asked.
2. Turn on Developer options: Settings > About phone, then tap **Build number** 7 times. Android does not let a program do this for you.
3. Settings > System > Developer options, then turn on **USB debugging**. On Xiaomi, Redmi and POCO phones also turn on **USB debugging (Security settings)**.
4. Install Android platform-tools on the PC. The installer's **Android support** component does this for you. Otherwise Sidespeaker finds `adb` on your PATH, next to `sidespeaker.exe`, in a `platform-tools` folder next to it, or in the Android Studio SDK. Or set `adb_path` in `config.ini`.
5. Plug the phone into the PC with a data cable (some cables only charge), and set the USB mode to **File transfer** in the USB notification.
6. Authorize the PC. With the screen on and unlocked, an **Allow USB debugging?** dialog appears. Tick **Always allow from this computer** and tap **Allow**. If the tray says `Android found (unauthorized)` and no dialog shows up, lock the phone, unplug the cable, plug it back in, unlock the phone, and tap **Allow** when the dialog appears. This is needed once per PC.
7. Open the Sidespeaker app on the phone. The tray icon turns green when streaming starts. While the app runs, a notification stays in the shade; closing the app (Back button or swiping it away from recent apps) stops it and removes the notification.

## Use it

1. Open Sidespeaker on each phone.
2. Run `sidespeaker.exe`. It lives in the system tray (check the hidden icons arrow). Hover over the icon to see the status: waiting for a phone, streaming to one or more phones, or an error. The icon is grey while waiting, green while streaming and red on an error.
3. Left-click the tray icon to open the **Phones** window. Every phone that is plugged in is listed with a checkbox and its status. Tick the phones that should play and untick the ones that should not. Newly connected phones are ticked by default. **Test** plays a short beep on one phone so you can tell which is which.
4. Play audio on the PC. It comes out of every ticked phone.
5. Right-click the tray icon to open the window, edit the config or exit.

Android phones are listed by model name. iPhones are listed as "iPhone" plus the last four characters of their ID, because Apple does not share the device name without pairing. Use **Test** to match them to the physical phone.

While the phone app runs, a persistent notification shows on Android. iOS does not allow pinned notifications, so the iPhone app shows a Now Playing card on the lock screen and in Control Center instead. Both go away when you close the app.

Your PC's own speakers keep playing too, so mute them or switch outputs if you only want the phones. Set `transport` in `config.ini` to `ios` or `android` to ignore the other kind.

### Surround sound

Tick **Surround sound** in the Phones window. A map appears with you in the middle and the front of the room at the top. Drag each ticked phone to where it really is. The label under each phone shows which part of the sound it plays, for example Front left, Center, Side right or Rear left, and it updates as you drag. A phone placed on top of you plays the full mix.

- **Stereo audio:** Sidespeaker builds a front left, front right, center and two rear channels from the left and right channels, and gives each part to the phones closest to it. With only two phones, put one on the left and one on the right.
- **5.1 or 7.1 audio:** set your default playback device to 5.1 or 7.1 in the Windows sound settings (or use a virtual surround device). Apps that output real surround then send each channel to the phone nearest to that speaker position. The subwoofer channel is not used.
- **Each phone plays one channel (mono)** in surround mode. With surround off, every ticked phone plays the same stereo sound.
- Positions, ticks and the surround setting are remembered per phone in `%APPDATA%\Sidespeaker\layout.ini`.

Phones are not synchronised with each other beyond the shared stream. Each app has its own buffer, so phones can play at different times. For the tightest result use the same kind of phone.

## Configuration

### PC sender (`config.ini`)

| Key | Default | Meaning |
|---|---|---|
| `transport` | auto | `auto`, `ios`, or `android`. Auto lists both kinds of phone. |
| `port` | 5000 | Phone port to connect to. Must match the app. |
| `poll_ms` | 5 | How often the capture buffer is checked. |
| `retry_ms` | 1000 | Delay between connection attempts. |
| `fill_ms` | 10 | Smallest chunk of silence sent to keep the stream continuous. |
| `usb_only` | 1 | iPhone only: ignore Wi-Fi connections. Set to 0 to allow them. |
| `adb_path` | adb | Android only: path to the `adb` program. |
| `scan_ms` | 1000 | How often the PC looks for phones being plugged in or removed. |

### iPhone (`ios/project.yml`, under `info.properties`)

| Key | Default | Meaning |
|---|---|---|
| `SidePort` | 5000 | Port the app listens on. |
| `SidePrebufferMs` | 30 | Audio queued before playback starts (screen on). |
| `SideMaxBufferMs` | 60 | Maximum queue before playback resyncs to newer audio (screen on). |
| `SideBgPrebufferMs` | `SidePrebufferMs` | Optional override for the prebuffer while in the background or locked. |
| `SideBgMaxBufferMs` | `SideMaxBufferMs` | Optional override for the maximum queue while in the background or locked. |
| `SideTimeoutMs` | 3000 | Disconnect if no data arrives for this long. |

### Android (`android/app/src/main/res/values/config.xml`)

| Key | Default | Meaning |
|---|---|---|
| `port` | 5000 | Port the app listens on. |
| `prebuffer_ms` | 80 | Audio queued before playback starts. |
| `max_buffer_ms` | 250 | Maximum queue before audio is dropped. |
| `timeout_ms` | 3000 | Disconnect if no data arrives for this long. |
| `track_buffer_mult` | 2 | Size of Android's own output buffer, as a multiple of the minimum. |

Phone settings take effect after a rebuild and reinstall.

## Tuning

- **Crackling or cuts:** raise the prebuffer values. Both apps show the current buffer level and an underrun count on screen.
- **Too much delay:** lower the prebuffer and maximum values. Smaller buffers are less forgiving.
- **iPhone, locked screen:** if playback stutters, raise `SideBgPrebufferMs` and `SideBgMaxBufferMs` in `ios/project.yml`. A deeper buffer adds delay.

## Troubleshooting

- **"waiting for iPhone or Android" forever:** check the cable. For an iPhone, unlock it, tap Trust, and install Apple Devices. For Android, enable USB debugging and accept the prompt. If your phone only shows up over Wi-Fi, `usb_only=1` ignores it.
- **"adb not found":** install platform-tools or set `adb_path`.
- **Android never detected:** run `adb devices` in a terminal. The phone must be listed as `device`. If it is missing, check the cable (use a data cable), set the USB mode to File transfer, and install the phone maker's USB driver if needed. Open the tray window to see each phone and its status. With no phone listed, the window shows why (for example adb not found).
- **"Android found (unauthorized)":** the phone has not approved this PC yet. Lock the phone, unplug the cable, plug it in again, unlock the phone and tap **Allow** on the "Allow USB debugging?" dialog. If no dialog appears, use Developer options > **Revoke USB debugging authorizations**, switch **USB debugging** off and on, replug, and turn off screen overlays (chat bubbles, night filters, screen recorders), which can hide the dialog. Close Android Studio or phone-manager programs, then run `adb kill-server` if another adb is holding the connection.
- **"Open the Sidespeaker app":** open Sidespeaker on that phone and check that the ports match.
- **A phone is listed but silent:** check that it is ticked and its status says Streaming. Use **Test** to check it. In surround mode, a phone placed where no sound is mapped to it only plays a quiet share, so drag it closer to a speaker position.
- **iPhone app stops launching after a week:** the free Apple ID signing expired. Re-sideload.
- **Two copies of the iPhone app:** an older build used a different bundle ID. Delete the old one.

## Limitations

- The PC sender only captures audio on Windows so far.
- Surround sound plays one channel per phone and does not compensate for different phone buffers or distances. Audio is raw PCM, sized for a USB cable, not Wi-Fi.
- Expect roughly the prebuffer length in delay, which is noticeable with video.
