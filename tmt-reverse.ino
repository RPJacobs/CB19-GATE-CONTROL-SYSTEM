#include <SPI.h>
#include <WiFi.h>
#include<HardwareSerial.h>//No extra libray installed

#define RXD2 16
#define TXD2 17

HardwareSerial tmt(1);

// Enter the IP address of the server you're connecting to:41
IPAddress server(10, 13, 1, 125);
WiFiClient client;
                    
bool message = false;
bool newLine = false;

int count = 0;

void setup() {
  // start the serial library:
  Serial.begin(115200);
  tmt.begin(9600, SERIAL_8N1, RXD2, TXD2);
  Serial.println("Serial Txd is on pin: "+String(TX));
  Serial.println("Serial Rxd is on pin: "+String(RX));
  Serial.println("Serial2 Txd is on pin: "+String(TXD2));
  Serial.println("Serial2 Rxd is on pin: "+String(RXD2));

  // start wifi connection:
  initWiFi();
  
  // if you get a connection, report back via serial:
  if (client.connect(server, 23)) {
    Serial.println("connected");
  }
  else {
    // if you didn't get a connection to the server:
    Serial.println("connection failed");
  }
}

void initWiFi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin("xxxxxx", "xxxxxx");
  Serial.print("Connecting to WiFi ..");
  while (WiFi.status() != WL_CONNECTED) {
    Serial.print('.');
    delay(1000);
  }
  Serial.println(WiFi.localIP());
}

void printHex(int num, int precision) {
      char tmp[16];
      char format[128];

      sprintf(format, "%%.%dX", precision);

      sprintf(tmp, format, num);
      Serial.print(tmp);
      Serial.print(" ");
}

void loop()
{
  // if there are incoming bytes available
  // from the server, read them and print them:


  while (client.available()) {
    if(newLine == false) {Serial.print("gate: ");}
    char c = client.read();
    tmt.write(c);
    Serial.print(c);
    //printHex(c, 2);
    message = true;
    newLine = true;
    count++;
  }

  if(newLine) {
    Serial.println();
    count = 0;
    newLine = false;
  }

  // as long as there are bytes in the serial queue,
  // read them and send them out the socket if it's open:
  while (tmt.available() > 0) {
    if(!newLine) {Serial.print("tmt: ");}
    size_t len = tmt.available();
    uint8_t sbuf[len];
    tmt.readBytes(sbuf, len);
    //push UART data to all connected telnet clients
    client.write(sbuf, len);
    //delay(1);
    
    for (int i = 0; i <= len; i++) {
      Serial.print((char) sbuf[i]);
    }
    newLine = true;
  } 


  if(newLine) {
    Serial.println();
    newLine = false;
  }


  
  // if the server's disconnected, stop the client:
  if (!client.connected()) {
    Serial.println();
    Serial.println("disconnecting.");
    client.stop();
    // do nothing:
    while(!client.connected()) {
        if (client.connect(server, 23)) {
          Serial.println("connected");
        } else {
          Serial.print('.');
          delay(1000);
        }
    }
  }



}
