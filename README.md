# CB19-GATE-CONTROL-SYSTEM

Removing my TMT CHOW remote gate controle, because it connects to an external server (security risk). Intergrate RS323 via ESP32 with MQTT > Homebridge > Applehomekit

Step 1:
Open the TMT module

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

Here we can find the PIN OUT

RST
V5
RX
TX
GND

Soldering it to an ESP

<img src="https://github.com/RPJacobs/CB19-GATE-CONTROL-SYSTEM/blob/main/img/esp.jpg?raw=true" width=20% height=20%>

Now we need to bridge it to another ESP, connected to the CB19 controle box. I used esp-link for that (https://github.com/jeelabs/esp-link)

Wrote a small program to attach the tmt wifi unit to the esp-link module [tmt-reverse.ino](tmt-reverse.ino) now we have a MITM serial proxy!

After opening the TMT app we can see the serial traffic between the tmt module and the cb19 box. This is in plain text!

Gate  : READ STATUS;src=P0004A83

TMT   : ACK STATUS:FULL CLOSED,0

Pressing all the buttons gave me all het commands.

PED OPEN
FULL OPEN
FULL CLOSE
READ FUNCTION
READ DEVINFO
STOP

Now it time to flash the esp connected to the control box with tasmota (https://tasmota.github.io/). It has the main funtions is easy to use and you van program drivers in berry (https://tasmota.github.io/docs/Berry/)

So wrote a small berry file [Gate.be](Gate.be) , uploaded this to the tasmota esp connected to the control box and made a sort of serial to MQTT bridge.

send you commands to /test

feedback on /Gate

In homebridge add a door-thing
https://github.com/arachnetech/homebridge-mqttthing


```json
{
            "accessory": "mqttthing",
            "type": "door",
            "name": "Hek",
            "url": "mqtt://10.13.1.4:1883",
            "topics": {
                "getCurrentPosition": "/hek/percentage",
                "setTargetPosition": "/hek/set/percentage",
                "getTargetPosition": "/hek/set/updown",
                "getPositionState": "/gate/getState"
            },
            "positionStateValues": [
                "DECREASING",
                "INCREASING",
                "STOPPED"
            ],
            "minPosition": 0,
            "maxPosition": 99
        },
        {
            "accessory": "mqttthing",
            "type": "door",
            "name": "Loophek",
            "url": "mqtt://10.13.1.4:1883",
            "topics": {
                "getCurrentPosition": "/hek/ped_percentage",
                "setTargetPosition": "/hek/set/ped_percentage",
                "getPositionState": "/gate/getPState"
            },
            "positionStateValues": [
                "DECREASING",
                "INCREASING",
                "STOPPED"
            ],
            "minPosition": 0,
            "maxPosition": 25
        },

```

et voila! No more TMT needed.











