<?php

echo date('Y-m-d H:i:s')."\tIncomming:\t".$buf."\n";
$talkback = false;
if ($buf == 'READ STATUS;src=P0004A83') {
    $talkback = "ACK STATUS:PED CLOSED,0";
    
}
if ($buf == 'READ DEVINFO;src=P0004A83') {
    $talkback = "ACK READ DEVINFO:P190,PS17062E,V0.3";
    
}
if ($buf == 'READ FUNCTION;src=P0004A83') {
    //3.2 PARAMETER SETTINGS of CB19U-34100-125-10-C_CB19_manual_std_Wi-Fi_au
    $talkback = "ACK READ FUNCTION,1:1,2:01,3:01,4:4,5:4,6:4,7:1,8:2,9:7,A:1,B:1,C:0,D:1,E:0,F:0,G:0,H:1,I:2,J:0;src=P0004A83";
               /* " WRITE FUNCTION,1:1,2:01,3:01,4:4,5:4,6:4,7:1,8:2,9:0,A:1,B:1,C:0,D:1,E:0,F:0,G:0,H:1,I:2,J:0;src=P0004A83
                    WRITE FUNCTION,1:1,2:02,3:01,4:4,5:4,6:4,7:1,8:2,9:7,A:1,B:1,C:0,D:1,E:0,F:0,G:0,H:1,I:2,J:0;src=P0004A83
               "*/
}

//CLEAR REMOTE LEARN;src=P0004A83 - remote clear
//RESTORE;src=P0004A83 - factory default
//REMOTE LEARN;src=P0004A83 - remote learn
//AUTO LEARN;src=P0004A83 - system learning
// - READ LEARN STATUS;src=P0004A83

if ($talkback) {
    $talkback = $talkback."\r\n";
}
