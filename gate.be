import mqtt
import string

class Gate : Driver

  var ser          #- Serial interface -#
	var readStatus
  var state
  var Tstate
  var percentage

  def init()
  	self.readStatus = false
		# gpio_rx:16 gpio_tx:17
		self.ser = serial(17, 16, 9600, serial.SERIAL_8N1)
		self.ser.write(bytes().fromstring("READ STATUS;src=P0004A83\r\n"))
		self.subscribe()
    tasmota.add_driver(self)
    tasmota.add_rule("mqtt#connected", /->self.subscribe())
  end
  
  def subscribe()
    mqtt.subscribe("/test")
    mqtt.subscribe("/Gate/set/percentage")
    mqtt.subscribe("/Gate/set/ped_percentage")
    print "connected MQTT"
  end
  
  def remove()
     tasmota.remove_driver(self)
  end
  
	#- get mqtt values -#
	def mqtt_data(topic, idx, payload_s, payload_b)
		if (topic == "/Gate/set/percentage")
      var command = payload_s
      if(command == "99")
        mqtt.publish("/gate/getTargetDoorState", "Open")
        self.ser.write(bytes().fromstring("FULL OPEN;src=P0004A83\r\n"))
        return true
      end
      if(command == "0")
        mqtt.publish("/gate/getTargetDoorState", "Closed")
        self.ser.write(bytes().fromstring("FULL CLOSE;src=P0004A83\r\n"))
        return true
      end
    end
		if (topic == "/Gate/set/ped_percentage")
      var command = payload_s
      if(command == "25")
        mqtt.publish("/gate/getTargetDoorPState", "Open")
        self.ser.write(bytes().fromstring("PED OPEN;src=P0004A83\r\n"))
        return true
      end
      if(command == "0")
        mqtt.publish("/gate/getTargetDoorPState", "Closed")
        self.ser.write(bytes().fromstring("FULL CLOSE;src=P0004A83\r\n"))
        return true
      end
    end
    if (topic == "/test")
				var command = payload_s
				if(command == "FULL CLOSE")
					self.ser.write(bytes().fromstring("FULL CLOSE;src=P0004A83\r\n"))
				end
				if(command == "PED OPEN")
					self.ser.write(bytes().fromstring("PED OPEN;src=P0004A83\r\n"))
				end
				if(command == "READ FUNCTION")
					self.ser.write(bytes().fromstring("READ FUNCTION;src=P0004A83\r\n"))
				end
				if(command == "READ DEVINFO")
					self.ser.write(bytes().fromstring("READ DEVINFO;src=P0004A83\r\n"))
				end
				if(command == "FULL OPEN")
					self.ser.write(bytes().fromstring("FULL OPEN;src=P0004A83\r\n"))
				end
				if(command == "STOP")
					self.ser.write(bytes().fromstring("STOP;src=P0004A83\r\n"))
				end
	  	return true
		end		

	  return false
	end
	
	
	def processMain(msg)
        if(msg == "PedOpening" || msg == "PedClosing" || msg == "Opening" || msg == "Closing")
            self.readStatus = true
        end
	end
	
	def processStatus(msg)
		var strSplit = string.split(msg, ',')
		if (strSplit.size() == 2)

      self.percentage = str(strSplit[1]);

			if(strSplit[0] == "SINGLE STOPPED") 
				mqtt.publish("/gate/getPState", "STOPPED")
        mqtt.publish("/Gate/ped_percentage", "25")
				self.readStatus = false
			end
      if (strSplit[0] == "FULL OPENED")
        mqtt.publish("/gate/getState", "STOPPED")
        mqtt.publish("/Gate/percentage", "99")
        self.readStatus = false
      end
			if(strSplit[0] == "PED CLOSED") 
				mqtt.publish("/gate/getPState", "STOPPED")
				mqtt.publish("/Gate/ped_percentage", "0")
        mqtt.publish("/gate/getState", "STOPPED")
				mqtt.publish("/Gate/percentage", "0")
				self.readStatus = false
			end
			if(strSplit[0] == "FULL CLOSED") 
				mqtt.publish("/gate/getPState", "STOPPED")
				mqtt.publish("/Gate/ped_percentage", "0")
        mqtt.publish("/gate/getState", "STOPPED")
				mqtt.publish("/Gate/percentage", "0")
				self.readStatus = false
			end

			if(strSplit[0] =="PED OPENING")
				mqtt.publish("/gate/getPState", "INCREASING")
				mqtt.publish("/Gate/ped_percentage", str(strSplit[1]))
        mqtt.publish("/gate/getState", "STOPPED")
				mqtt.publish("/Gate/percentage", "0")
			end
			if(strSplit[0] =="FULL OPENING")
				mqtt.publish("/gate/getState", "INCREASING")
				mqtt.publish("/Gate/percentage", str(strSplit[1]))
        mqtt.publish("/gate/getPState", "STOPPED")
				mqtt.publish("/Gate/ped_percentage", "0")
			end
			if(strSplit[0] =="DUAL STOPPED")
				mqtt.publish("/gate/getState", "STOPPED")
				mqtt.publish("/Gate/percentage", str(strSplit[1]))
				mqtt.publish("/Gate/ped_percentage", str(strSplit[1]))
        self.readStatus = false
			end
      if (strSplit[0] =="FULL CLOSING" )
				mqtt.publish("/gate/getState", "DECREASING")
				mqtt.publish("/Gate/percentage", str(strSplit[1]))
      end
      if (strSplit[0] =="PED CLOSING" )
				mqtt.publish("/gate/getPState", "DECREASING")
				mqtt.publish("/Gate/ped_percentage", str(strSplit[1]))
      end			
		end
	end
	
	def processMSG(msg)
        var msgArray = string.split(msg.asstring(), "\r")
        for i:0..msgArray.size()-2
            msg = msgArray[i]
            var strSplit = string.split(msg, ':')
            if (strSplit[0] == "Error")
              return false
            end
            mqtt.publish("/Gate/serial", msg)
            if(strSplit.size() == 2 && strSplit[0] == "ACK STATUS")
                self.processStatus(strSplit[1])
            end
            strSplit = string.split(msg, ';')
            if(strSplit.size() == 2)
                strSplit = string.split(strSplit[0], ',')
                if (strSplit.size() == 3)
                    self.processMain(strSplit[2])
                end
            end
        end
	end

  #- trigger a read every second -#
  def every_second()
  	if(self.ser.available())
  		var msg = self.ser.read()   			# read bytes from serial as bytes
  		self.processMSG(msg);
  	end
  	
  	if(self.readStatus)
  		self.ser.write(bytes().fromstring("READ STATUS;src=P0004A83\r\n"))
  	end
  end

  #- display sensor value in the web UI -#
  def web_sensor()
    var msg = string.format(
             "{s}Gate Percentage {m}%.1f °C{e}",
              self.percentage)
    tasmota.web_send_decimal(msg)
  end



end
Gate = Gate()