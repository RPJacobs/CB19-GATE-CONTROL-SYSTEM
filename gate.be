import mqtt
import string
import crypto
import webserver

# CB19 remote pairing, travel learning and read-only progress.
class CB19Learn : Driver
  var gate, settings, tokens, mode, phase, deadline, next_poll, read_until
  var progress, status_text, event_text, note

  def init()
    self.tokens = {}
    for k : ["ab","hek","lees"] self.tokens[k] = crypto.random(16).tohex() end
  end

  def attach(gate, settings)
    self.gate = gate
    self.settings = settings
    tasmota.add_driver(self)
  end

  def web_add_handler()
    webserver.on("/inleren", /->self.page(), webserver.HTTP_GET)
    webserver.on("/inleren-actie", /->self.submit(), webserver.HTTP_POST)
  end

  def web_add_main_button()
    webserver.content_send("<form action='/inleren' method='get'><p><button name='k' value='ab'>AB inleren</button></p><p><button name='k' value='hek'>Hek inleren</button></p><p><button>Inleerstatus</button></p></form>")
  end

  def escaped(txt)
    return string.replace(string.replace(string.replace(txt,"&","&amp;"),"<","&lt;"),">","&gt;")
  end

  def form(k, button)
    webserver.content_send("<form action='/inleren-actie' method='post'>")
    webserver.content_send(string.format("<input type='hidden' name='k' value='%s'><input type='hidden' name='token' value='%s'>",k,self.tokens[k]))
    if k == "hek"
      webserver.content_send("<p><label><input type='checkbox' name='vrij' value='ja' required> Ik sta bij het hek en de volledige bewegingsruimte is vrij.</label></p>")
    end
    webserver.content_send("<p><button>" + button + "</button></p></form>")
  end

  def page()
    if !webserver.check_privileged_access() return end
    var k = webserver.arg("k")
    webserver.content_start("CB19 inleren")
    webserver.content_send_style()
    if self.phase == nil && (k == "ab" || k == "hek")
      if k == "hek"
        webserver.content_send("<h3>Hek inleren</h3><p>De CB19 beweegt de vleugels om de slag te leren. Houd de doorgang vrij en blijf bij het hek.</p>")
        self.form(k,"Inleercyclus starten")
      else
        webserver.content_send("<h3>AB inleren</h3><p>Leg de handzender klaar. Druk na het starten op de knop die je wilt inleren.</p>")
        self.form(k,"Handzender inleermodus starten")
      end
    end
    webserver.content_send("<h3>Inleerstatus</h3>")
    if self.note != nil webserver.content_send("<p role='status'>" + self.note + "</p>") end
    if self.read_until != nil webserver.content_send("<p>Wachten op antwoord van de CB19.</p>") end
    if self.status_text != nil
      webserver.content_send("<p>Laatste antwoord op READ LEARN STATUS<br><strong>" + self.escaped(self.status_text) + "</strong></p>")
    end
    if self.event_text != nil
      webserver.content_send("<p>Laatste inleermelding<br><strong>" + self.escaped(self.event_text) + "</strong></p>")
    end
    self.form("lees","Inleerstatus uitlezen")
    if self.phase != nil || self.read_until != nil
      webserver.content_send("<script>setTimeout(()=>location.replace('/inleren'),2500)</script>")
    end
    webserver.content_button(webserver.BUTTON_MAIN)
    webserver.content_stop()
  end

  def submit()
    if !webserver.check_privileged_access() return end
    var k = webserver.arg("k")
    if !self.tokens.contains(k) || webserver.arg("token") != self.tokens[k]
      webserver.content_open(403,"text/plain")
      webserver.content_send("Formulier verlopen. Open de inleerpagina opnieuw.")
      webserver.content_close()
      return
    end
    if k == "lees"
      self.read_status()
    else
      self.tokens[k] = crypto.random(16).tohex()
      var err = self.request(k,webserver.arg("vrij") == "ja")
      if err != nil
        webserver.content_start("CB19 inleren")
        webserver.content_send_style()
        webserver.content_send("<p>" + err + "</p><p><a href='/inleren'>Naar de inleerstatus</a></p>")
        webserver.content_stop()
        return
      end
    end
    webserver.redirect("/inleren")
  end

  def request(k, clear)
    if k != "ab" && k != "hek" return "Onbekende opdracht." end
    if k == "hek" && !clear return "Bevestig eerst dat de bewegingsruimte vrij is." end
    if self.phase != nil return "Er loopt al een inleeraanvraag." end
    if self.settings.phase != nil || self.gate.f9_ticks != 0 return "Wacht tot de instelling is opgeslagen." end
    if self.gate.readStatus return "Wacht op stilstand van het hek." end
    self.mode = k
    self.phase = "stand"
    self.progress = false
    self.deadline = tasmota.millis(4500)
    self.note = "De ESP controleert of het hek stilstaat."
    self.gate.send("READ STATUS")
    return nil
  end

  def read_status()
    if self.next_poll != nil && !tasmota.time_reached(self.next_poll) return end
    self.next_poll = tasmota.millis(3000)
    if self.read_until == nil self.read_until = tasmota.millis(6500) end
    self.gate.send("READ LEARN STATUS")
  end

  def finish(message)
    self.note = message
    self.phase = nil
    self.mode = nil
    self.deadline = nil
  end

  def activate(k)
    self.mode = k
    self.phase = "volgen"
    self.progress = false
    self.status_text = nil
    self.event_text = nil
    self.read_until = nil
    self.next_poll = tasmota.millis(2000)
    self.deadline = tasmota.millis(k == "hek" ? 300000 : 60000)
  end

  def line(msg)
    if string.startswith(msg,"ACK STATUS:") && self.phase == "stand"
      if tasmota.time_reached(self.deadline)
        self.finish("Geen tijdige standmelding. De aanvraag is vervallen.")
        return
      end
      var p = string.split(msg[11..-1],",")
      if size(p) != 2 || !self.gate.digits(p[1]) || int(p[1]) > 100 return end
      var stopped = ["FULL CLOSED","PED CLOSED","FULL OPENED","PED OPENED","DUAL STOPPED","SINGLE STOPPED"]
      if stopped.find(p[0]) == nil || self.gate.readStatus || self.settings.phase != nil || self.gate.f9_ticks != 0
        self.finish("Start afgebroken. Controleer de hekstand en de instellingen.")
        return
      end
      var k = self.mode
      self.activate(k)
      self.note = "Startopdracht verzonden. Wachten op de CB19."
      self.gate.send(k == "hek" ? "AUTO LEARN" : "REMOTE LEARN")
    elif msg == "ACK REMOTE LEARN" || msg == "ACK AUTO LEARN"
      var k = msg == "ACK AUTO LEARN" ? "hek" : "ab"
      if self.phase != "volgen" || self.mode != k self.activate(k) end
      self.note = k == "hek" ? "De CB19 heeft de opdracht voor het hek geaccepteerd." : "De CB19 heeft de inleermodus voor de handzender geaccepteerd."
    elif string.startswith(msg,"ACK LEARN STATUS:") || string.startswith(msg,"ACK READ LEARN STATUS:")
      var txt = string.split(msg,";")[0]
      txt = txt[string.find(txt,":")+1..-1]
      self.status_text = txt
      self.read_until = nil
      if self.mode == "hek" && self.phase == "volgen"
        if txt == "SYSTEM LEARN COMPLETE" && self.progress
          self.finish("De CB19 meldt dat het hek is ingeleerd.")
        elif string.find(txt,"IN PROGRESS") >= 0 || string.find(txt,"LEARNING") >= 0
          self.progress = true
        end
      end
    elif string.startswith(msg,"$V1PKF0,")
      var fields = string.split(string.split(msg,";")[0],",")
      if size(fields) < 3 return end
      var ev = fields[2]
      if self.phase == "stand" && (ev == "Opening" || ev == "Closing" || ev == "PedOpening" || ev == "PedClosing")
        self.finish("Start afgebroken. Het hek is in beweging.")
      end
      if string.find(ev,"Learn") < 0 return end
      self.event_text = ev
      if self.phase != "volgen" return end
      if ev == "LearnStart"
        self.progress = true
        self.note = self.mode == "ab" ? "Inleren gestart. Druk op de knop van de handzender." : "De CB19 is met het inleren begonnen."
      elif ev == "LearnComplete"
        self.finish("De CB19 meldt dat het inleren is afgerond (LearnComplete).")
        self.read_status()
      elif ev == "LearnFail" || ev == "LearnFailed" || ev == "LearnError"
        self.finish("De CB19 meldt een fout bij het inleren.")
      end
    end
  end

  def every_second()
    if self.read_until != nil && tasmota.time_reached(self.read_until)
      self.read_until = nil
      self.status_text = "Geen antwoord op de statusaanvraag."
    end
    if self.phase == nil return end
    if tasmota.time_reached(self.deadline)
      if self.phase == "stand"
        self.finish("Geen tijdige standmelding. De aanvraag is vervallen.")
      else
        self.finish("Automatisch volgen gestopt zonder eindmelding. Controleer het hek en lees de status opnieuw uit.")
      end
    elif self.phase == "volgen"
      self.read_status()
    end
  end
end

var cb19_learn = CB19Learn()

# Display the most recent complete READ FUNCTION reply, using CB19 manual 7.2/7.3.
class CB19Panel : Driver
  var rows, next_read, stale_after, specs, by_key, values, hall_amps
  var driver, token, phase, ticks, edit_key, desired, base, mode, before_write, notice, queued_auto

  def init()
    var switches = ["Uit", "Aan"]
    var speed = [nil, "40%", "50%", "75%", "100%"]
    var gap = ["0 s", "2 s", "5 s", "10 s", "15 s", "20 s", "25 s", "35 s", "45 s", "55 s"]
    var amps = [nil, "2 A", "3 A", "4 A", "5 A"]
    self.specs = [
      ["9", "Automatisch sluiten", ["Uit", "Aan, 3 s", "Aan, 10 s", "Aan, 20 s", "Aan, 40 s", "Aan, 60 s", "Aan, 120 s", "Aan, 180 s (3 min)", "Aan, 300 s"]],
      ["1", "Motortype", [nil, "Overstroomdetectie", "Eindschakelaar", "Hall-sensor"]],
      ["2", "Stroomgrens openen", amps],
      ["3", "Stroomgrens sluiten", amps],
      ["4", "Snelheid openen", speed],
      ["5", "Snelheid sluiten", speed],
      ["6", "Afremsnelheid", [nil, "40%", "50%", "60%", "70%"]],
      ["7", "Vleugelvertraging openen", gap],
      ["8", "Vleugelvertraging sluiten", gap],
      ["A", "Beveiligingsmodus", [nil, "Fotocel open/sluit", "Veiligheidslijst", "Voertuigdetectie", "Dubbele fotocel"]],
      ["B", "Voetgangersstand", switches],
      ["C", "Waarschuwingslicht", ["Bij beweging", "3 s vooraf"]],
      ["D", "Fotocel 1", switches],
      ["E", "Fotocel 2", switches],
      ["F", "Alarmzoemer", switches],
      ["G", "Elektrisch slot", ["Standaard openen", "Ontlasten (0,25 s)"]],
      ["H", "Displayrichting", ["Klemmen boven", "Klemmen onder"]],
      ["I", "Aantal vleugels", [nil, "Enkel", "Dubbel"]],
      ["J", "Terugloop bij overstroom (sluiten)", ["Uit", "0,1 s", "0,2 s", "0,3 s", "0,4 s", "0,5 s", "0,6 s"]]
    ]
    self.by_key = {}
    for spec : self.specs self.by_key[spec[0]] = spec end
    self.hall_amps = [nil,nil,nil,nil,nil]
    for i : 5..50
      self.hall_amps.push(string.format("+%d,%d A", i / 10, i % 10))
    end
    self.token = crypto.random(16).tohex()
  end

  def choices(key, values)
    if key == "3" && int(values["1"]) == 3 return self.hall_amps end
    return self.by_key[key][2]
  end

  def label(key, values)
    if key == "3" && int(values["1"]) == 3 return "Extra stroom bij sluiten" end
    return self.by_key[key][1]
  end

  def value_text(options, raw)
    var n = int(raw)
    if n >= 0 && n < size(options) && options[n] != nil return options[n] end
    return "Onbekende waarde"
  end

  def update(values)
    self.values = values
    var rendered = []
    for spec : self.specs
      var key = spec[0]
      var raw = values[key]
      var decoded = self.value_text(self.choices(key, values), raw)
      rendered.push(string.format("{s}F%s %s{m}%s [%s]{e}", key, self.label(key, values), decoded, raw))
    end
    self.rows = rendered.concat("")
    self.next_read = tasmota.millis(60000)
    self.stale_after = tasmota.millis(90000)
  end

  def attach(driver)
    self.driver = driver
    tasmota.add_driver(self)
  end

  def web_add_handler()
    webserver.on("/cb19", /->self.page(), webserver.HTTP_GET)
    webserver.on("/cb19-save", /->self.submit(), webserver.HTTP_POST)
  end

  def web_add_main_button()
    webserver.content_send("<p></p><form action='/cb19' method='get'><button>CB19-instellingen wijzigen</button></form>")
  end

  def page()
    if !webserver.check_privileged_access() return end
    var key = webserver.arg("k")
    if !self.by_key.contains(key) key = "9" end
    webserver.content_start("CB19-instellingen")
    webserver.content_send_style()
    if self.phase != nil
      webserver.content_send("<p role='status'>Wijziging in behandeling. De controller wordt uitgelezen.</p><script>setTimeout(()=>location.reload(),1800)</script>")
    elif self.notice != nil
      webserver.content_send("<p role='status'>" + self.notice + "</p>")
    end
    webserver.content_send("<form action='/cb19' method='get'><label for='k'>Instelling</label><select id='k' name='k' onchange='this.form.submit()'>")
    for spec : self.specs
      var id = spec[0]
      var title = self.values == nil ? spec[1] : self.label(id,self.values)
      webserver.content_send(string.format("<option value='%s'%s>F%s %s</option>", id, id == key ? " selected" : "", id, title))
    end
    webserver.content_send("</select><noscript><button>Tonen</button></noscript></form>")
    if self.values == nil
      self.request_refresh(self.driver)
      webserver.content_send("<p>Wachten op instellingen van de CB19.</p><p><a href='/cb19'>Opnieuw uitlezen</a></p>")
    else
      self.request_refresh(self.driver)
      var choices = self.choices(key, self.values)
      var raw = self.values[key]
      webserver.content_send(string.format("<p>Laatst uitgelezen: <strong>%s [%s]</strong></p>", self.value_text(choices,raw),raw))
      if self.phase == nil
        webserver.content_send("<form action='/cb19-save' method='post'>")
        webserver.content_send(string.format("<input type='hidden' name='k' value='%s'><input type='hidden' name='base' value='%s'><input type='hidden' name='mode' value='%s'><input type='hidden' name='token' value='%s'>", key,raw,self.values["1"],self.token))
        webserver.content_send("<label for='v'>Nieuwe waarde</label><select id='v' name='v' required>")
        if self.value_text(choices,raw) == "Onbekende waarde"
          webserver.content_send("<option value='' selected disabled>Kies een waarde</option>")
        end
        for i : 0..size(choices)-1
          if choices[i] != nil
            webserver.content_send(string.format("<option value='%d'%s>%s</option>", i, i == int(raw) ? " selected" : "", choices[i]))
          end
        end
        webserver.content_send("</select><p><button type='submit'>Wijziging opslaan</button></p></form>")
      end
    end
    webserver.content_button(webserver.BUTTON_MAIN)
    webserver.content_stop()
  end

  def submit()
    if !webserver.check_privileged_access() return end
    if webserver.arg("token") != self.token
      webserver.content_open(403,"text/plain")
      webserver.content_send("Dit formulier is verlopen. Open de instellingen opnieuw.")
      webserver.content_close()
      return
    end
    var key = webserver.arg("k")
    var message = self.begin_edit(key,webserver.arg("v"),webserver.arg("base"),webserver.arg("mode"))
    if message != nil
      webserver.content_start("CB19-instellingen")
      webserver.content_send_style()
      webserver.content_send("<p>" + message + "</p><p><a href='/cb19'>Terug naar de instellingen</a></p>")
      webserver.content_stop()
      return
    end
    self.token = crypto.random(16).tohex()
    webserver.redirect("/cb19?k=" + key)
  end

  def begin_edit(key, requested, base, mode)
    if cb19_learn.phase != nil return "Wacht tot het inleren is afgerond." end
    if self.phase != nil || self.driver.f9_ticks != 0
      return "Een andere wijziging loopt. Probeer het daarna opnieuw."
    end
    if self.values == nil || !self.by_key.contains(key) || !self.driver.digits(requested)
      return "Kies een instelling en een geldige waarde."
    end
    if self.values[key] != base || (key == "3" && self.values["1"] != mode)
      return "Deze instelling is intussen gewijzigd. Open het formulier opnieuw."
    end
    var n = int(requested)
    var choices = self.choices(key,self.values)
    if n < 0 || n >= size(choices) || choices[n] == nil
      return "Deze waarde valt buiten de opties van de controller."
    end
    if n == int(base) return "Deze waarde is al ingesteld." end
    if self.driver.readStatus return "Het hek beweegt of de stand wordt uitgelezen. Probeer het opnieuw bij stilstand." end
    self.edit_key = key
    self.desired = n
    self.base = base
    self.mode = mode
    self.phase = "status"
    self.ticks = 10
    self.notice = nil
    self.driver.send("READ STATUS")
    return nil
  end

  def position(moving)
    if self.phase == "status" || self.phase == "read"
      if moving
        self.finish("Het hek beweegt. De wijziging is afgebroken.")
      elif self.phase == "status"
        self.phase = "read"
        self.driver.send("READ FUNCTION")
      end
    end
  end

  def acknowledged()
    if self.phase == "ack" self.phase = "verify" end
  end

  def observe(fields, address)
    if self.phase == nil return false end
    if self.phase == "verify"
      var matching = int(self.values[self.edit_key]) == self.desired
      var others_match = true
      for spec : self.specs
        var k = spec[0]
        if k != self.edit_key && self.values[k] != self.before_write[k] others_match = false end
      end
      var msg = matching ? "Waarde door de CB19 bevestigd." : "De CB19 meldt een andere waarde."
      if !others_match msg += " Ook een andere parameter is gewijzigd. Controleer het overzicht." end
      self.finish(msg)
      return true
    end
    if self.phase != "read" return true end
    if self.driver.readStatus || self.values[self.edit_key] != self.base || (self.edit_key == "3" && self.values["1"] != self.mode)
      self.finish("De stand of instelling is intussen gewijzigd. Controleer de actuele waarden.")
      return true
    end
    # Preserve all other controller-supplied fields, their order and their original padding.
    var raw = str(self.desired)
    var width = size(self.base)
    if (self.edit_key == "2" || self.edit_key == "3") && width < 2 width = 2 end
    while size(raw) < width raw = "0" + raw end
    for i : 1..size(fields)-1
      if string.startswith(fields[i], self.edit_key + ":")
        fields[i] = self.edit_key + ":" + raw
        break
      end
    end
    fields[0] = "WRITE FUNCTION"
    self.before_write = self.values
    self.phase = "ack"
    self.ticks = 10
    self.driver.send(fields.concat(",") + ";" + address)
    return true
  end

  def finish(message)
    self.notice = "F" + self.edit_key + " &ndash; " + message
    self.phase = nil
    self.before_write = nil
    if self.queued_auto != nil
      var enable = self.queued_auto
      self.queued_auto = nil
      self.driver.set_auto_close(enable)
    end
  end

  def every_second()
    if self.phase == nil return end
    self.ticks -= 1
    if self.ticks == 6
      if self.phase == "status"
        self.driver.send("READ STATUS")
      else
        if self.phase == "ack" self.phase = "verify" end
        self.driver.send("READ FUNCTION")
      end
    elif self.ticks <= 0
      self.finish("Geen bevestiging ontvangen. Controleer de uitgelezen waarde.")
      self.driver.refresh_ticks = 12
    end
  end

  def request_refresh(driver)
    # Reuse bounded settings reads while this screen is open and the gate is idle.
    if (self.next_read == nil || tasmota.time_reached(self.next_read)) && !driver.readStatus && driver.f9_ticks == 0 && driver.refresh_ticks == 0
      driver.refresh_ticks = 12
      self.next_read = tasmota.millis(60000)
    end
  end

  def show(driver)
    self.request_refresh(driver)
    if self.rows == nil
      tasmota.web_send("{s}CB19-instellingen{m}Wachten op uitlezing{e}")
    else
      if tasmota.time_reached(self.stale_after)
        tasmota.web_send("{s}CB19-instellingen{m}Laatste bekende waarden{e}")
      end
      tasmota.web_send(self.rows)
    end
  end
end

var cb19_panel = CB19Panel()

# Cache the controller identity from its serial reply, independently of MQTT.
class CB19DeviceInfo
  var value, retry_at

  def read_if_due(driver)
    if self.value != nil || driver.readStatus || driver.refresh_ticks != 0 || driver.f9_ticks != 0 return end
    if cb19_panel.phase != nil || cb19_learn.phase != nil return end
    if self.retry_at != nil && !tasmota.time_reached(self.retry_at) return end
    self.retry_at = tasmota.millis(30000)
    driver.send("READ DEVINFO")
  end

  def receive(msg)
    var prefix = "ACK READ DEVINFO:"
    if !string.startswith(msg,prefix) return end
    var data = string.split(msg[size(prefix)..-1],";")[0]
    var parts = string.split(data,",")
    if size(parts) != 3 || size(data) > 96 return end
    for part : parts
      if size(part) == 0 return end
    end
    # Escape both HTML and Tasmota's {s}/{m}/{e} table markers.
    data = string.replace(string.replace(string.replace(data,"&","&amp;"),"<","&lt;"),">","&gt;")
    self.value = string.replace(data,"{","&#123;")
  end

  def row()
    var shown = self.value == nil ? "Wachten op antwoord" : self.value
    return "{s}READ DEVINFO{m}" + shown + "{e}"
  end
end

var cb19_info = CB19DeviceInfo()

class HekDriver : Driver
  var ser, rx, discard_line, sent, percentage, readStatus, poll_ticks, settle
  var desired_motion, ped_active, desired_f9, written_f9, verify_f9, f9_ticks, refresh_ticks

  def init()
    self.reset_state()
    # ESP32 RX=17, TX=16. The gate controller manages its own motor and limits.
    self.ser = serial(17, 16, 9600, serial.SERIAL_8N1)
    tasmota.add_driver(self)
    for topic : ["/test", "/hek/autoclose/cmd", "/hek/autoclose/start",
                 "/hek/set/percentage", "/hek/set/ped_percentage"]
      mqtt.subscribe(topic)
    end
    tasmota.add_rule("mqtt#connected", /->self.refresh())
    self.refresh()
  end

  def reset_state()
    self.rx = ""
    self.discard_line = false
    self.sent = {}
    self.readStatus = false
    self.poll_ticks = 0
    self.settle = 0
    self.f9_ticks = 0
    self.verify_f9 = false
    self.ped_active = false
    self.refresh_ticks = 0
  end

  def send(command)
    if string.find(command, ";src=") < 0
      command += ";src=P0004A83"
    end
    self.ser.write(bytes().fromstring(command + "\r\n"))
  end

  def publish(topic, value)
    mqtt.publish(topic, value)
  end

  def changed(topic, value)
    if self.sent.find(topic) != value
      self.publish(topic, value)
      self.sent[topic] = value
    end
  end

  def target(ped, value)
    if ped
      self.changed("/gate/getTargetPedState", value)
      # Earlier clients used this alias with a capital first letter.
      self.changed("/gate/getTargetDoorPState", value == "open" ? "Open" : "Closed")
    else
      self.changed("/gate/getTargetDoorState", value)
    end
  end

  def report(ped, state, position)
    var movement = "STOPPED"
    if state == "opening" movement = "INCREASING" end
    if state == "closing" movement = "DECREASING" end
    self.changed(ped ? "/gate/getCurrentPedState" : "/gate/getCurrentDoorState", state)
    self.changed(ped ? "/gate/getPState" : "/gate/getState", movement)
    if position != nil
      self.changed(ped ? "/hek/ped_percentage" : "/hek/percentage", position)
    end
  end

  def poll()
    if !self.readStatus
      self.readStatus = true
      self.poll_ticks = 60
    end
  end

  def refresh()
    self.sent = {}
    self.poll()
    self.send("READ STATUS")
    # Space the two reads so the controller can answer each in turn.
    self.refresh_ticks = 12
  end

  def move(command, ped)
    self.poll_ticks = 60
    self.readStatus = true
    self.settle = 3
    self.desired_motion = nil
    if command != "STOP"
      self.desired_motion = command == "FULL CLOSE" ? "closed" : "open"
      self.target(ped, self.desired_motion)
      if command == "FULL CLOSE" && self.ped_active
        self.target(true, "closed")
      end
    end
    self.send(command)
  end

  def mqtt_data(topic, idx, value, raw)
    if topic == "/hek/set/percentage"
      if value == "99" || value == "100" self.move("FULL OPEN", false) end
      if value == "0" self.move("FULL CLOSE", false) end
    elif topic == "/hek/set/ped_percentage"
      if value == "25" self.move("PED OPEN", true) end
      if value == "0" self.move("FULL CLOSE", true) end
    elif topic == "/test"
      if value == "FULL OPEN" || value == "FULL CLOSE" || value == "PED OPEN" || value == "STOP"
        self.move(value, value == "PED OPEN")
      elif value == "READ FUNCTION" || value == "READ DEVINFO"
        self.send(value)
      end
    elif topic == "/hek/autoclose/start"
      self.refresh()
    elif topic == "/hek/autoclose/cmd"
      if value == "ON" || value == "OFF"
        self.set_auto_close(value == "ON")
      end
    else
      return false
    end
    return true
  end

  def set_auto_close(enable)
    if type(enable) != "bool" return end
    if cb19_panel.phase != nil
      cb19_panel.queued_auto = enable
      return
    end
    self.desired_f9 = enable ? "7" : "0"
    if self.f9_ticks == 0
      self.f9_ticks = 8
      self.send("READ FUNCTION")
    end
  end

  def remove()
    tasmota.remove_driver(self)
  end

  def digits(s)
    if size(s) == 0 || size(s) > 3 return false end
    for i : 0..size(s)-1
      if string.find("0123456789", s[i]) < 0 return false end
    end
    return true
  end

  def status(data)
    var fields = string.split(data, ",")
    if size(fields) != 2 || !self.digits(fields[1]) return end
    var pct = int(fields[1])
    if pct > 100 return end
    var k = fields[0]
    var pos = str(pct)
    var moving = k == "FULL OPENING" || k == "FULL CLOSING" || k == "PED OPENING" || k == "PED CLOSING"
    var closed = k == "FULL CLOSED" || k == "PED CLOSED"
    var ped_end = k == "SINGLE STOPPED" || k == "PED OPENED"
    if !moving && !closed && !ped_end && k != "FULL OPENED" && k != "DUAL STOPPED" return end
    # A read directly after a command can still report the old endpoint.
    if !moving && self.settle > 0 && self.desired_motion != nil
      if (closed && self.desired_motion == "open") || (!closed && self.desired_motion == "closed")
        return
      end
    end
    self.percentage = pos
    if moving
      self.settle = 0
      self.poll()
      var ped = string.startswith(k, "PED ")
      var opening = k == "FULL OPENING" || k == "PED OPENING"
      var state = opening ? "opening" : "closing"
      var dest = opening ? "open" : "closed"
      if ped self.ped_active = true end
      self.target(ped, dest)
      self.report(ped, state, pos)
      if !ped && !opening && self.ped_active
        self.target(true, "closed")
        self.report(true, "closing", nil)
      end
    else
      self.readStatus = false
      self.settle = 0
      self.desired_motion = nil
      if closed
        self.ped_active = false
        self.target(true, "closed")
        self.report(true, "closed", "0")
        if k == "FULL CLOSED"
          self.target(false, "closed")
          self.report(false, "closed", "0")
        end
      elif k == "FULL OPENED"
        self.target(false, "open")
        self.report(false, "open", "100")
      elif ped_end
        self.ped_active = true
        if k == "PED OPENED" || pct == 25
          self.target(true, "open")
          self.report(true, "open", pos)
        else
          self.report(true, "stopped", pos)
        end
      else
        self.report(false, "stopped", pos)
        if self.ped_active self.report(true, "stopped", pos) end
      end
    end
    cb19_panel.position(moving)
  end

  # Only act on complete settings frames from our controller.
  def function_frame(msg, is_read)
    var halves = string.split(msg, ";")
    if size(halves) != 2 || halves[1] != "src=P0004A83" return end
    var fields = string.split(halves[0], ",")
    var schema = "123456789ABCDEFGHIJ"
    if size(fields) != size(schema) + 1 return end
    var values = {}
    var f9_index = nil
    for i : 1..size(fields)-1
      var kv = string.split(fields[i], ":")
      if size(kv) != 2 || size(kv[0]) != 1 || string.find(schema, kv[0]) < 0 return end
      if values.contains(kv[0]) || !self.digits(kv[1]) return end
      values[kv[0]] = kv[1]
      if kv[0] == "9" f9_index = i end
    end
    var actual = values["9"]
    # A write acknowledgement triggers a separate read-back. Only reads
    # publish the actual switch state or initiate a settings change.
    if !is_read
      cb19_panel.acknowledged()
      if self.written_f9 != nil self.verify_f9 = true end
      self.send("READ FUNCTION")
      return
    end
    if self.written_f9 != nil && !self.verify_f9 return end
    cb19_panel.update(values)
    self.refresh_ticks = 0
    self.changed("/hek/autoclose/state", actual == "0" ? "OFF" : "ON")
    if cb19_panel.observe(fields, halves[1]) return end
    if self.written_f9 != nil
      if actual != self.written_f9 && self.desired_f9 == self.written_f9
        print("Hek: autoclose wijziging niet bevestigd")
        self.desired_f9 = nil
      end
      self.written_f9 = nil
    end
    if self.desired_f9 == nil || actual == self.desired_f9
      self.desired_f9 = nil
      self.f9_ticks = 0
      return
    end
    fields[0] = "WRITE FUNCTION"
    fields[f9_index] = "9:" + self.desired_f9
    self.written_f9 = self.desired_f9
    self.verify_f9 = false
    self.f9_ticks = 8
    self.send(fields.concat(",") + ";" + halves[1])
  end

  def line(msg)
    print(msg)
    self.publish("/hek/serial", msg)
    if string.startswith(msg, "ACK READ DEVINFO:")
      cb19_info.receive(msg)
    elif string.startswith(msg, "ACK STATUS:")
      self.status(msg[11..-1])
    elif string.startswith(msg, "ACK READ FUNCTION,")
      self.function_frame(msg, true)
    elif string.startswith(msg, "ACK FUNCTION,")
      self.function_frame(msg, false)
    elif string.startswith(msg, "$")
      var fields = string.split(string.split(msg, ";")[0], ",")
      if size(fields) == 3
        var event_name = fields[2]
        if event_name == "Opening" || event_name == "Closing" || event_name == "PedOpening" || event_name == "PedClosing"
          self.poll()
        elif event_name == "Opened" || event_name == "Closed" || event_name == "Stopped"
          self.poll()
        end
      end
    end
    cb19_learn.line(msg)
  end

  def processMSG(chunk)
    # Treat CR, LF and CRLF as separators, including across UART reads.
    var lines = string.split(string.replace(chunk.asstring(), "\r", "\n"), "\n")
    for i : 0..size(lines)-1
      var part = lines[i]
      if !self.discard_line
        if size(self.rx) + size(part) > 512
          self.rx = ""
          self.discard_line = true
        else
          self.rx += part
        end
      end
      if i < size(lines)-1
        if !self.discard_line && size(self.rx) > 0 self.line(self.rx) end
        self.rx = ""
        self.discard_line = false
      end
    end
  end

  def every_second()
    if self.ser.available() self.processMSG(self.ser.read()) end
    var read_functions = false
    if self.refresh_ticks > 0
      self.refresh_ticks -= 1
      # Read again if a position reply or a reconnect coincided with the first request.
      read_functions = self.f9_ticks == 0 && (self.refresh_ticks == 11 || self.refresh_ticks == 7 || self.refresh_ticks == 3)
      if self.refresh_ticks == 0 && self.f9_ticks == 0
        print("Hek: geen instellingen ontvangen na drie uitleespogingen")
      end
    end
    if self.readStatus
      self.poll_ticks -= 1
      if self.poll_ticks <= 0
        print("Hek: geen bevestigde eindstand binnen 60 seconden")
        self.readStatus = false
      elif !read_functions
        self.send("READ STATUS")
      end
    end
    if self.settle > 0 self.settle -= 1 end
    if read_functions self.send("READ FUNCTION") end
    if self.f9_ticks > 0
      self.f9_ticks -= 1
      if self.f9_ticks == 4
        self.verify_f9 = self.written_f9 != nil
        self.send("READ FUNCTION")
      end
      if self.f9_ticks == 0
        self.desired_f9 = nil
        self.written_f9 = nil
        print("Hek: autoclose aanvraag verlopen")
      end
    end
    cb19_info.read_if_due(self)
  end

  def web_sensor()
    var position = self.percentage == nil ? "?" : self.percentage
    tasmota.web_send_decimal(string.format("{s}Gate Percentage {m}%s %%{e}", position))
    tasmota.web_send(cb19_info.row())
    cb19_panel.show(self)
  end
end

var Hek = HekDriver()
cb19_panel.attach(Hek)
cb19_learn.attach(Hek,cb19_panel)
