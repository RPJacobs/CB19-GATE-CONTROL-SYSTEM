import webserver
import crypto
import json

class HekOverzicht : Driver
  var gate, panel, learn, info, token, next_read, cooldown, asset_dir

  var state, pct, path, valid_until

  def init(gate, panel, learn, info)
    self.asset_dir = size(tasmota.wd) ? tasmota.wd : "/"
    self.gate = gate
    gate.web_display = self
    self.panel = panel
    self.learn = learn
    self.info = info
    self.token = crypto.random(16).tohex()
  end

  def web_add_handler()
    # Reserve the control and status routes before any optional download links.
    webserver.on("/hek-actie", /->Hek.web_display.submit(), webserver.HTTP_POST)
    webserver.on("/hek-data", /->Hek.web_display.data(), webserver.HTTP_GET)
    webserver.on("/hek", /->Hek.web_display.page(), webserver.HTTP_GET)

    # Older pages and bookmarks may still request assets by their filename.
    try
      webserver.on("/nl.json", /->Hek.web_display.asset("/nl.json","application/json; charset=utf-8"), webserver.HTTP_GET)
      webserver.on("/en.json", /->Hek.web_display.asset("/en.json","application/json; charset=utf-8"), webserver.HTTP_GET)
      webserver.on("/de.json", /->Hek.web_display.asset("/de.json","application/json; charset=utf-8"), webserver.HTTP_GET)
      webserver.on("/hek-taal.js", /->Hek.web_display.asset("/hek-taal.js","application/javascript; charset=utf-8"), webserver.HTTP_GET)
    except "internal_error" as e, message
      if message != "no more slots for webserver hooks" raise e, message end
    end
  end

  def page()
    if !webserver.has_arg("bestand")
      return self.asset("/hek.html","text/html; charset=utf-8")
    end
    var name = webserver.arg("bestand")
    if name == "hek-taal.js"
      return self.asset("/hek-taal.js","application/javascript; charset=utf-8")
    end
    if name == "nl.json" || name == "en.json" || name == "de.json"
      return self.asset("/" + name,"application/json; charset=utf-8")
    end
    if webserver.check_privileged_access() self.reply(404,"text/plain","404") end
  end

  def web_add_main_button()
    webserver.content_send("<form action='/hek'><p><button>Hekoverzicht</button></p></form>")
  end

  def asset(file,mime)
    if !webserver.check_privileged_access() return end
    import path
    file = self.asset_dir + file[1..]
    if !path.exists(file) self.reply(404,"text/plain","404") return end
    var f = open(file,"r")
    webserver.content_open(200,mime)
    var part = f.read(768)
    while size(part) > 0
      webserver.content_send(part)
      part = f.read(768)
    end
    f.close()
    webserver.content_close()
  end

  def busy()
    return self.learn.phase != nil || self.panel.phase != nil || self.gate.f9_ticks != 0
  end

  # A pedestrian cycle moves the short leaf only. Remember it if it closes
  # with FULL CLOSING or if a full opening follows the pedestrian endpoint.
  def observe(state, pct)
    import string
    if state == "FULL CLOSED" || state == "PED CLOSED" || state == "FULL OPENED"
      self.path = "both"
    elif string.startswith(state,"PED ") || state == "SINGLE STOPPED"
      self.path = "single"
    elif state == "FULL OPENING" && self.path != "from_ped"
      var was_open = self.state == "PED OPENED" || (self.state == "SINGLE STOPPED" && self.pct == 25)
      self.path = was_open ? "from_ped" : "both"
    elif state == "FULL CLOSING" && self.path == "from_ped"
      self.path = "both"
    end
    self.state = state
    self.pct = pct
    self.valid_until = tasmota.millis(14000)
  end

  def fresh()
    return self.valid_until != nil && !tasmota.time_reached(self.valid_until)
  end

  def data()
    if !webserver.check_privileged_access() return end
    var g = self.gate
    var p = self.panel
    var busy = self.busy()
    if !busy && !g.readStatus && g.refresh_ticks == 0 && (self.next_read == nil || tasmota.time_reached(self.next_read))
      g.send("READ STATUS")
      self.next_read = tasmota.millis(5000)
    end
    var result = {"state": self.fresh() ? self.state : nil, "pct":self.pct, "path":self.path,
                  "token":self.token, "busy":busy}
    var valid_f9 = p.values != nil && p.stale_after != nil && !tasmota.time_reached(p.stale_after)
    result["f9"] = valid_f9 ? p.values["9"] : nil
    if !valid_f9 && !busy p.request_refresh(g) end
    if webserver.has_arg("f9check") result["f9notice"] = p.notice end
    if webserver.has_arg("info")
      if !busy p.request_refresh(g) end
      var rows = []
      if p.values != nil
        for spec : p.specs
          var key = spec[0]
          var raw = p.values[key]
          rows.push([key,p.label(key,p.values),p.value_text(p.choices(key,p.values),raw),raw])
        end
      end
      result["rows"] = rows
      result["dev"] = self.info.value
      result["old"] = p.stale_after != nil && tasmota.time_reached(p.stale_after)
    end
    self.reply(200,"application/json",json.dump(result))
  end

  def reply(code, mime, body)
    webserver.content_open(code,mime)
    webserver.content_send(body)
    webserver.content_close()
  end

  def command(action, token)
    if token != self.token return [403,"Herlaad de pagina."] end
    var cmd = {"ped":"PED OPEN","both":"FULL OPEN","close":"FULL CLOSE","stop":"STOP"}.find(action)
    if cmd == nil return [400,"Onbekende opdracht."] end
    if self.busy() return [409,"De controller verwerkt een instelling of inleeropdracht."] end
    if !self.fresh() return [409,"Wachten op de actuele hekstand."] end
    if cmd != "STOP" && self.cooldown != nil && !tasmota.time_reached(self.cooldown)
      return [409,"De vorige opdracht is zojuist verstuurd."]
    end
    self.cooldown = tasmota.millis(1000)
    self.gate.move(cmd,action == "ped")
    return [200,"Opdracht verstuurd."]
  end

  def set_f9(value, base, token)
    if token != self.token return [403,"Herlaad de pagina."] end
    var p = self.panel
    if !self.fresh() || p.stale_after == nil || tasmota.time_reached(p.stale_after)
      return [409,"Wacht op actuele gegevens van de controller."]
    end
    # The settings panel checks the base value, confirms standstill, then
    # changes only F9 and reads back the entire controller configuration.
    var msg = p.begin_edit("9",value,base,nil)
    if msg != nil return [409,msg] end
    return [202,"Wijziging in behandeling."]
  end

  def submit()
    if !webserver.check_privileged_access() return end
    var result
    var action = webserver.arg("actie")
    if action == "f9"
      result = self.set_f9(webserver.arg("v"),webserver.arg("base"),webserver.arg("token"))
    else
      result = self.command(action,webserver.arg("token"))
    end
    self.reply(result[0],"text/plain; charset=utf-8",result[1])
  end
end

tasmota.add_driver(HekOverzicht(Hek,cb19_panel,cb19_learn,cb19_info))
