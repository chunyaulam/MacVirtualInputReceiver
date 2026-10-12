# MacVirtualInputReceiver

A lightweight, native macOS menu bar utility that receives input commands (mouse, keyboard, gamepad) over UDP and injects them into macOS as native system events via CoreGraphics (`CGEvent`).

---

## 🚀 Features

- **Menu Bar Utility**: Runs unobtrusively in the macOS menu bar (`MenuBarExtra`), displaying real-time server status and connection information.
- **Low-Latency UDP Protocol**: Uses Apple's `Network.framework` (`NWListener`) for fast, low-overhead packet processing.
- **Mouse Emulation**:
  - Relative pointer movement (`mouseMoved`, `leftMouseDragged`).
  - Screen boundary clamping.
  - Multi-button support (Left, Right, Middle / Center click).
  - Vertical and horizontal scroll wheel events.
- **Keyboard Emulation**:
  - Standard key events with macOS virtual key codes and modifier keys (Shift, Control, Option, Command).
  - Direct Unicode / UTF-8 text string insertion (`CGEventKeyboardSetUnicodeString`).
  - Dedicated control keys (Backspace, Return, Tab, Escape).
- **Gamepad Support**:
  - Parses standard gamepad states (14 buttons, dual analog sticks, analog triggers).
- **Permission Management**: Live detection and direct prompt request for macOS Accessibility permissions.

---

## 🛠 Requirements

- **macOS**: 13.0 (Ventura) or later
- **Xcode**: 15.0 or later
- **Swift**: 5.9 or later
- **Permissions**: **Accessibility** (`AXIsProcessTrusted`) permission is required to post synthetic input events into `.cghidEventTap`.

---

## 📦 Installation & Setup

1. **Clone the Repository**:
   ```bash
   git clone https://github.com/chunyaulam/MacVirtualInputReceiver.git
   cd MacVirtualInputReceiver
   ```

2. **Open in Xcode**:
   ```bash
   open MacVirtualInputReceiver.xcodeproj
   ```

3. **Build & Run**:
   - Select your Mac as the run destination.
   - Press `Cmd + R` to build and launch.

4. **Grant Accessibility Permission**:
   - When launched for the first time, click the menu bar icon.
   - If prompted that **Accessibility Permission Needed**, click **Allow** or manually enable the app under:
     **System Settings** → **Privacy & Security** → **Accessibility**.

---

## ⚙️ How It Works

Upon launch, the application binds to UDP port `8567` across active network interfaces (preferring `en0` / `en1` for Wi-Fi / Ethernet). It listens for binary packets and routes them to their corresponding controller:

```
                      ┌────────────────────────┐
                      │ UDP Client (Port 8567) │
                      └───────────┬────────────┘
                                  │ UDP Packets
                                  ▼
                     ┌──────────────────────────┐
                     │    UDPListenerManager    │
                     └────────────┬─────────────┘
                                  │
         ┌────────────────────────┼────────────────────────┐
         │ 0x01                   │ 0x02 / 0x03 / 0x04     │ 0x03
         ▼                        ▼                        ▼
┌─────────────────┐      ┌────────────────────┐   ┌───────────────────┐
│ MouseController │      │ KeyboardController │   │ GamepadController │
└────────┬────────┘      └─────────┬──────────┘   └─────────┬─────────┘
         │                         │                        │
         └─────────────────────────┼────────────────────────┘
                                   │ CGEvent / EventTap
                                   ▼
                         ┌───────────────────┐
                         │ macOS Input Queue │
                         └───────────────────┘
```

---

## 📡 Protocol Specification

All multi-byte numeric fields are encoded in **Little-Endian** byte order.

### 1. Mouse Packet (`packetType: 0x01`)

Minimum length: **16 bytes**

| Offset | Field | Type | Description |
|---|---|---|---|
| `0..3` | `timestamp` | `UInt32` | Milliseconds timestamp (used for latency calculation) |
| `4` | `packetType` | `UInt8` | `0x01` (Mouse) |
| `5` | `buttons` | `UInt8` | Bitmask: <br>• Bit 0 (`0x01`): Left Button<br>• Bit 1 (`0x02`): Right Button<br>• Bit 2 (`0x04`): Middle Button |
| `6..9` | `deltaX` | `Float32` | Relative X delta |
| `10..13` | `deltaY` | `Float32` | Relative Y delta |
| `14` | `scrollWheel` | `Int8` | Vertical scroll step (positive/negative) |
| `15` | `hScrollWheel` | `Int8` | Horizontal scroll step (positive/negative) |

---

### 2. Keyboard Packets

#### A. Standard Key Event (`packetType: 0x02`)
Minimum length: **9 bytes**

| Offset | Field | Type | Description |
|---|---|---|---|
| `0..3` | `timestamp` | `UInt32` | Milliseconds timestamp |
| `4` | `packetType` | `UInt8` | `0x02` (Keyboard) |
| `5` | `action` | `UInt8` | `0x00`: Key Up<br>`0x01`: Key Down |
| `6..7` | `keycode` | `UInt16` | macOS Virtual Key Code |
| `8` | `modifiers` | `UInt8` | Modifier bitmask:<br>• `0x01`: Shift (`.maskShift`)<br>• `0x02`: Control (`.maskControl`)<br>• `0x04`: Alt / Option (`.maskAlternate`)<br>• `0x08`: Command (`.maskCommand`) |

#### B. Unicode Text Channel (`channel: 0x03`)
Used for sending text strings directly without mapping key codes.

| Offset | Field | Type | Description |
|---|---|---|---|
| `0` | `channel` | `UInt8` | `0x03` |
| `1..N` | `payload` | `[UInt8]` | UTF-8 encoded string |

#### C. Control Key Channel (`channel: 0x04`)
Quick single-action control key presses (automatically fires KeyDown followed by KeyUp).

| Offset | Field | Type | Description |
|---|---|---|---|
| `0` | `channel` | `0x04` | Control key channel identifier |
| `1` | `action` | `UInt8` | `1`: Delete / Backspace (`0x33`)<br>`2`: Return / Enter (`0x24`)<br>`3`: Tab (`0x30`)<br>`4`: Escape (`0x35`) |

---

### 3. Gamepad Packet (`packetType: 0x03`)

Minimum length: **17 bytes**

| Offset | Field | Type | Description |
|---|---|---|---|
| `0..3` | `timestamp` | `UInt32` | Milliseconds timestamp |
| `4` | `packetType` | `UInt8` | `0x03` (Gamepad) |
| `5..6` | `buttons` | `UInt16` | Bitmask:<br>• `0x0001`: A<br>• `0x0002`: B<br>• `0x0004`: X<br>• `0x0008`: Y<br>• `0x0010`: LB<br>• `0x0020`: RB<br>• `0x0040`: LS (Left Stick Click)<br>• `0x0080`: RS (Right Stick Click)<br>• `0x0100`: Start<br>• `0x0200`: Back<br>• `0x0400`: D-Pad Up<br>• `0x0800`: D-Pad Down<br>• `0x1000`: D-Pad Left<br>• `0x2000`: D-Pad Right |
| `7..8` | `leftStickX` | `Int16` | Left stick X (-32768 to 32767) |
| `9..10` | `leftStickY` | `Int16` | Left stick Y (-32768 to 32767) |
| `11..12` | `rightStickX` | `Int16` | Right stick X (-32768 to 32767) |
| `13..14` | `rightStickY` | `Int16` | Right stick Y (-32768 to 32767) |
| `15` | `leftTrigger` | `UInt8` | Left trigger analog value (0 to 255) |
| `16` | `rightTrigger` | `UInt8` | Right trigger analog value (0 to 255) |

---

## 📂 Project Structure

```text
MacVirtualInputReceiver/
├── MacVirtualInputReceiverApp.swift   # App entry point, MenuBarExtra setup, ServerController
├── UDPListenerManager.swift          # Network.framework UDP listener & packet demuxer
├── MouseController.swift             # Mouse packet parsing and CGEvent simulation
├── KeyboardController.swift          # Keycode, Unicode, and Control key simulation
├── GamepadController.swift           # Gamepad packet parsing and state tracking
├── ContentView.swift                 # Menu bar popover SwiftUI view
└── Assets.xcassets                   # App icons and color assets
```

---

## 🔒 Security & Privacy

This application injects synthetic HID events directly into macOS. Because of this:
- macOS requires explicit user authorization in **System Settings → Privacy & Security → Accessibility**.
- The app only listens locally on the network and does not transmit data outside your local environment.

---

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.
