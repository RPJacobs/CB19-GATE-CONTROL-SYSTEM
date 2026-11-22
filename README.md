# CB19 gate control with ESP32 and Tasmota

[gate.be](gate.be) connects a TMT CB19 gate controller to a local MQTT broker and Homebridge. The ESP32 reads the gate position over serial, displays all 19 controller settings and provides controls for pairing a remote and learning gate travel. The TMT CHOW cloud service is optional.

This driver has been used with Tasmota32 14.4.1 and a CB19 reporting `P190,PS17062E,V0.3` through `READ DEVINFO`. The gate dashboard, controller settings and learning forms are available in Dutch, English and German. The original hardware photos and serial captures are included [below](#hardware-and-protocol-notes).

## App screenshots

![Gate dashboard showing both leaves closed, the pedestrian and full-gate controls, and a three-minute automatic closing delay](https://github.com/user-attachments/assets/a86f3b26-dbe5-4024-803b-12b7cf3dac7e)

<details>
<summary>View all 19 CB19 controller settings</summary>

![Expanded controller card showing the decoded F1–FJ settings alongside their raw CB19 values](https://github.com/user-attachments/assets/858b9b2c-666a-412a-b91b-abf3e919dd5d)

</details>

## Install the dashboard on Tasmota32

[**Download CB19-Gate.tapp**](https://github.com/RPJacobs/CB19-GATE-CONTROL-SYSTEM/releases/latest/download/CB19-Gate.tapp) · [All releases](https://github.com/RPJacobs/CB19-GATE-CONTROL-SYSTEM/releases)

For an ESP32 running Tasmota32 with Berry, filesystem, web server and MQTT support. The driver uses **GPIO17 RX, GPIO16 TX, 9600 baud, 8N1**. Check your board's serial interface and voltage levels. Configure your broker in Tasmota if you use Homebridge. Keep MQTT movement commands non-retained.

1. Download **CB19-Gate.tapp** and keep the file intact.
2. In Tasmota open **Tools → Manage File system**, select the file and click **Upload** in the filesystem root.
3. With the gate stationary and in view, **restart** the ESP. Click **Hekoverzicht** on the Tasmota home page or open `/hek`. Check the reported gate position and **READ DEVINFO**.

The app contains the driver, dashboard and language files. The two-leaf diagram shows the CB19 position. The dashboard opens either the pedestrian gate or both leaves, closes the gate, and controls F9 automatic closing. The language selector remembers the choice in each browser.

### Upgrade or roll back

- **Earlier single-file release** — download the new package, replace **CB19-Gate.tapp** under the same name and restart. To roll back, upload the previous release with the same filename and restart. Keep just one active CB19 application.
- **Earlier loose-file installation** — download a backup of the current gate scripts and root `autoexec.be`. Remove only the CB19 startup lines for `gate.be` or `hek.be` and `hekweb.be`. Move those loose driver files and matching `.bec` files out of the root, or rename them with a `.bak` suffix. If you previously used `Hekoverzicht.tapp`, download a backup and remove it from the ESP. Upload the new package and restart once. Keep other startup lines and apps. The packaged driver skips startup when it detects the old files. To roll back, remove the new package, restore your backups and restart.

### Change translations or publish a release

Edit [nl.json](app/nl.json), [en.json](app/en.json) or [de.json](app/de.json) and keep the keys consistent. Run `python3 app/build.py` from the repository to build `dist/CB19-Gate.tapp`. Maintainers can publish the build from **Actions → Publish Tasmota application → Run workflow** on `main` by entering a new version such as `v1.1.0`. The release attaches the package built from that commit.

## Standalone driver installation

1. Use an ESP32 running Tasmota with Berry, MQTT, the web server and filesystem enabled. The driver opens GPIO17 as RX and GPIO16 as TX at 9600 baud, 8 data bits, no parity and one stop bit. Check the serial interface and logic levels for your board before connecting it.
2. Configure your broker in Tasmota and back up the current Berry driver and `autoexec.be`. On an upgrade, check the MQTT mappings below. Movement commands should be published with **retain off**. A broker can replay a retained command when the ESP reconnects.
3. Upload [gate.be](gate.be) to the root of the ESP filesystem using **Manage File System**. Add the following line to `autoexec.be`, keeping your other startup scripts. If the installed driver is named `hek.be`, use that name in the load line instead. Load a single copy of the driver.

   ```berry
   load("gate.be")
   ```

4. With the gate in sight and the travel area clear, restart the ESP. Open its home page. Under **Gate Percentage**, the **READ DEVINFO** row shows the identity returned by your controller, for example `P190,PS17062E,V0.3`. The ESP requests it when the gate driver is idle and retries after 30 seconds if no valid reply arrives. The settings below start with **F9 Automatisch sluiten**. To refresh the identity manually, run `Hek.send("READ DEVINFO")` in the Berry console. The reply updates the row and also appears on `/hek/serial`.

For filesystem and startup details, see the [Tasmota Berry documentation](https://tasmota.github.io/docs/Berry/).

## ESP web controls

| Home-screen button | What it does |
| --- | --- |
| **CB19-instellingen wijzigen** | Opens the settings editor at `/cb19`. Select one of F1–F9 or FA–FJ, choose a value and press **Wijziging opslaan**. The ESP checks for standstill, reads the full settings frame, changes one field and reads the result back. |
| **AB inleren** | Opens the hand-transmitter form. Press **Handzender inleermodus starten**, then press the button on the remote. The page displays the controller’s `LearnStart` and `LearnComplete` events when received. |
| **Hek inleren** | Opens the gate travel-learning form. The cycle **moves the gate leaves**. Stand by the gate, check that the travel area is clear, tick the confirmation and press **Inleercyclus starten**. The ESP requests a fresh gate position before sending `AUTO LEARN`. |
| **Inleerstatus** | Opens `/inleren`. Press **Inleerstatus uitlezen** to request `READ LEARN STATUS` at any time. During learning, the ESP polls approximately every three seconds and displays both the latest status reply and the latest learning event. |

The two start buttons use separate commands, `REMOTE LEARN` for a transmitter and `AUTO LEARN` for gate travel. For example, `ACK LEARN STATUS:SYSTEM LEARN COMPLETE` describes the **gate travel** result. Look for **LearnComplete** after starting transmitter pairing to see its completion event. Automatic monitoring runs for up to one minute for a transmitter or five minutes for gate travel. If monitoring times out, check the gate and request its status again.

### Controller settings

The home page shows the decoded value and the raw controller code in brackets. These codes are useful when comparing the screen with the manual or a serial capture.

| Setting | Meaning |
| --- | --- |
| F1 | Motor feedback mode |
| F2 / F3 | Opening and closing current limits. In Hall-sensor mode, F3 sets additional closing current. |
| F4 / F5 / F6 | Opening, closing and deceleration speeds |
| F7 / F8 | Delay between the leaves during opening and closing |
| F9 | Automatic closing delay |
| FA / FB / FC | Safety input mode, pedestrian mode and warning light |
| FD / FE | Photocells 1 and 2 |
| FF / FG / FH | Buzzer, electric lock and display orientation |
| FI / FJ | Number of leaves and reversal on closing overcurrent |

For **F9**, the web editor supports every delay in the table. The MQTT autoclose switch uses a fixed three-minute delay when switched on.

| Raw F9 value | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Delay | Off | 3 s | 10 s | 20 s | 40 s | 60 s | 120 s | 180 s | 300 s |

## Hardware manuals

The [PAPILLON250 articulated-arm opener manual](PAPILLON250.pdf) covers the CB19 with controller ID `PS17062E`. The page numbers below are printed in the manual. The cover and contents add two pages in a PDF viewer.

| Procedure | Section | Printed pages |
| --- | --- | --- |
| Pair a remote and select OSC (open–stop–close) or PED (pedestrian) with the board’s RF Learn button | 3.1–3.2 | 8–9 |
| Learn gate travel | 3.3.2 | 10 |
| Look up controller settings, including F9 automatic closing | 5.1–5.2 | 12–13 (F9 on 13) |

The [CB19 control-box manual](CB19U-34100-125-10-C_CB19_manual_std_Wi-Fi_au.pdf) also documents the controller parameters and operating logic in sections 7.2–7.3. TMT Automation hosts the [PAPILLON250 manual on its website](https://www.tmt-automation.us/_upload/files/3410012416BPS17062EPAPILLONCB19manualen.pdf).

## MQTT and Homebridge

MQTT topics and payloads are case-sensitive. When upgrading from the original driver, replace the old `/Gate/set/...`, `/Gate/percentage`, `/Gate/ped_percentage` and `/Gate/serial` mappings with the exact names below. Replace the old `/Gate/set/updown` feedback mapping with the corresponding target door state below. The Berry console instance is now `Hek`.

| Homebridge mapping | Full gate | Pedestrian gate |
| --- | --- | --- |
| Send a target | `/hek/set/percentage` · `100` or `99` opens, `0` closes | `/hek/set/ped_percentage` · `25` opens, `0` closes the gate |
| Read current position | `/hek/percentage` | `/hek/ped_percentage` |
| Read current door state | `/gate/getCurrentDoorState` | `/gate/getCurrentPedState` |
| Read target door state | `/gate/getTargetDoorState` | `/gate/getTargetPedState` |
| Read movement direction | `/gate/getState` | `/gate/getPState` |

For a Homebridge garage-door accessory, map current state to `open`, `closed`, `opening`, `closing` and `stopped`. Map target state to `open` and `closed`, and publish the numeric payload for the selected target. Motion feedback uses `INCREASING`, `DECREASING` and `STOPPED`. The legacy pedestrian target alias `/gate/getTargetDoorPState` publishes `Open` and `Closed`.

| Other MQTT topics | Payload or result |
| --- | --- |
| `/hek/autoclose/cmd` | Send `ON` for F9 = 7 (180 s) or `OFF` for F9 = 0. |
| `/hek/autoclose/state` | Read `ON` for any nonzero F9 delay or `OFF` for zero. |
| `/hek/autoclose/start` | Publish any payload to request a fresh position and settings report. |
| `/hek/serial` | Subscribe to read controller replies and events. |
| `/test` | Accepts `READ DEVINFO`, `READ FUNCTION`, `FULL OPEN`, `PED OPEN`, `FULL CLOSE` and `STOP`. |

## Hardware and protocol notes

The original project replaced the TMT CHOW Wi-Fi module to keep control local. The module header is marked `RST`, `V5`, `RX`, `TX` and `GND`. These are the original module and ESP photos.

<table>
<tr><td>
<img src="https://user-images.githubusercontent.com/14312145/198314056-47c4af81-4ce5-4bf7-b1a2-107f2e96255c.png" width=40% height=40%>

</td></tr>
<tr><td>
<img src="https://github.com/RPJacobs/CB19-GATE-CONTROL-SYSTEM/blob/main/img/tmt1.jpg?raw=true" width=20% height=20%>
</td><td>
<img src="https://github.com/RPJacobs/CB19-GATE-CONTROL-SYSTEM/blob/main/img/tmt2.jpg?raw=true" width=20% height=20%>
</td></tr>
</table>

<img src="https://github.com/RPJacobs/CB19-GATE-CONTROL-SYSTEM/blob/main/img/esp.jpg?raw=true" width=20% height=20%>

The original capture setup used [tmt-reverse.ino](tmt-reverse.ino) and [esp-link](https://github.com/jeelabs/esp-link) to observe traffic between the CHOW module and the CB19. [server.php](server.php) emulates the controller for the module. [commands.php](commands.php) records the serial commands. A position request and an unsolicited close event look like this on the wire.

```text
READ STATUS;src=P0004A83
ACK STATUS:FULL CLOSED,0
$V1PKF0,17,Closed;src=0001
```

The CB19 returns all settings in one `ACK READ FUNCTION` reply and expects a full `WRITE FUNCTION` frame. The editor preserves the other 18 fields, their order and their original padding. This example is a read from the original project.

```text
ACK READ FUNCTION,1:1,2:01,3:01,4:4,5:4,6:4,7:1,8:2,9:7,A:1,B:1,C:0,D:1,E:0,F:0,G:0,H:1,I:2,J:0;src=P0004A83
```

<img width="901" alt="Screenshot 2022-10-27 at 17 15 07" src="https://user-images.githubusercontent.com/14312145/198329367-f20a2907-8d3f-4c4d-8f33-9ec19f592087.png">
