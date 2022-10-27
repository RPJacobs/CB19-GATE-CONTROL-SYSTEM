# CB19-GATE-CONTROL-SYSTEM

Removing my TMT CHOW remote gate control, because it connects to an external server (security risk). Intergrate RS323 via ESP32 with MQTT > Homebridge > Applehomekit

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

Now we need to bridge it to another ESP, connected to the CB19 control box. I used esp-link for that (https://github.com/jeelabs/esp-link)

Wrote a small program to attach the tmt wifi unit to the esp-link module [tmt-reverse.ino](tmt-reverse.ino) now we have a MITM serial proxy!

After opening the TMT app we can see the serial traffic between the tmt module and the cb19 box. This is in plain text!

Gate  : READ STATUS;src=P0004A83

TMT   : ACK STATUS:FULL CLOSED,0

We also get messages from $V1PKF0 (the box system controller, is a an main event is triggerd:

$V1PKF0,17,Closed;src=0001

Pressing all the buttons gave me all het commands.

PED OPEN
FULL OPEN
FULL CLOSE
READ FUNCTION
READ DEVINFO
STOP

Now it time to flash the esp connected to the control box with tasmota (https://tasmota.github.io/). It has the main funtions is easy to use and you van program drivers in berry (https://tasmota.github.io/docs/Berry/)

So wrote a small berry file [gate.be](gate.be) , uploaded this to the tasmota esp connected to the control box and made a sort of serial to MQTT bridge.

send you commands to /test

feedback on /Gate

In homebridge add a door-thing
https://github.com/arachnetech/homebridge-mqttthing


```json
{
            "accessory": "mqttthing",
            "type": "door",
            "name": "DualGate",
            "url": "mqtt://10.x.x.x:1883",
            "topics": {
                "getCurrentPosition": "/Gate/percentage",
                "setTargetPosition": "/Gate/set/percentage",
                "getTargetPosition": "/Gate/set/updown",
                "getPositionState": "/Gate/getState"
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
            "name": "Pedestrian",
            "url": "mqtt://10.x.x.x:1883",
            "topics": {
                "getCurrentPosition": "/Gate/ped_percentage",
                "setTargetPosition": "/Gate/set/ped_percentage",
                "getPositionState": "/Gate/getPState"
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

et voilà! No more TMT needed.

To still be able to connect the tmt module to a fake control box I used a php script to act as the esp-link module.

[server.php](server.php)

Now we can also find the programm commands [commands.php](commands.php) not implemented in the gate.be file...

READ FUNCTION;src=P0004A83 gives a string with all programmable items:

ACK READ FUNCTION,1:1,2:01,3:01,4:4,5:4,6:4,7:1,8:2,9:7,A:1,B:1,C:0,D:1,E:0,F:0,G:0,H:1,I:2,J:0;src=P0004A83

We can also write this string:

WRITE FUNCTION,1:1,2:02,3:01,4:4,5:4,6:4,7:1,8:2,9:7,A:1,B:1,C:0,D:1,E:0,F:0,G:0,H:1,I:2,J:0;src=P0004A83

Please check your control box documentation for all options. [CB19U-34100-125-10-C_CB19_manual_std_Wi-Fi_au.pdf](CB19U-34100-125-10-C_CB19_manual_std_Wi-Fi_au.pdf) page 10 & 11 7.2 parameters.

<img width="901" alt="Screenshot 2022-10-27 at 17 15 07" src="https://user-images.githubusercontent.com/14312145/198329367-f20a2907-8d3f-4c4d-8f33-9ec19f592087.png">










