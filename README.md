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

Wrote a small program to attach the tmt wifi unit to the esp-link module [here](main/tmt-reverse.ino)







