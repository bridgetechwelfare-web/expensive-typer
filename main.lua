require "import"
import "android.widget.*"
import "android.content.Intent"
import "android.speech.SpeechRecognizer"
import "android.speech.RecognitionListener"
import "android.speech.RecognizerIntent"
import "android.view.View"
import "android.content.Context"
import "android.net.Uri"
import "android.os.Handler"
import "android.os.Looper"
import "com.androlua.Http"

-- ═══ AUTO-UPDATE CONFIG ═══
local CURRENT_VERSION = "1.4"
local GITHUB_BRANCH  = "main"
local VERSION_URL    = "https://raw.githubusercontent.com/bridgetechwelfare-web/expensive-typer/" .. GITHUB_BRANCH .. "/version.txt"
local UPDATE_CODE_URL= "https://raw.githubusercontent.com/bridgetechwelfare-web/expensive-typer/" .. GITHUB_BRANCH .. "/main.lua"
local CHANGELOG_URL  = "https://raw.githubusercontent.com/bridgetechwelfare-web/expensive-typer/" .. GITHUB_BRANCH .. "/changelog.txt"
local PLUGIN_PATH    = "/storage/emulated/0/解说/Plugins/expensive typer/main.lua"
local updateInProgress = false
local mainHandler    = Handler(Looper.getMainLooper())

pcall(function()
  Http.setConnTimeout(60000)
  Http.setReadTimeout(60000)
end)

local langFile = os.getenv("EXTERNAL_STORAGE") .. "/expensive_typer_lang.dat"
local transLangFile = os.getenv("EXTERNAL_STORAGE") .. "/expensive_typer_trans_lang.dat"
local dictFile = os.getenv("EXTERNAL_STORAGE") .. "/expensive_typer_dict.dat"
local settingsFile = os.getenv("EXTERNAL_STORAGE") .. "/expensive_typer_settings.dat"
local changelogFile = os.getenv("EXTERNAL_STORAGE") .. "/expensive_typer_changelog.dat"
local lastShownVersionFile = os.getenv("EXTERNAL_STORAGE") .. "/expensive_typer_lastver.dat"

local appSettings = {
  translationEnabled = true,
  emojiEnabled = false,
  typingMode = "Smart Pro Mode",
  punctuationMode = "Period (.)",
  geminiModel = "gemini-2.0-flash",
  geminiApiKey = ""
}

function loadSettings()
  local f = io.open(settingsFile, "r")
  if f then
    local content = f:read("*all")
    f:close()
    if content and content ~= "" then
      local func = loadstring("return " .. content)
      if func then
        local saved = func()
        if type(saved) == "table" then
          for k,v in pairs(saved) do appSettings[k]=v end
        end
      end
    end
  end
end

function saveSettings()
  local f = io.open(settingsFile, "w")
  if f then
    local items = {}
    for k,v in pairs(appSettings) do
      if type(v)=="boolean" then
        table.insert(items, string.format("[%q]=%s", k, tostring(v)))
      else
        table.insert(items, string.format("[%q]=%q", k, tostring(v)))
      end
    end
    f:write("{"..table.concat(items,",").."}")
    f:close()
  end
end

loadSettings()

local changeTable = {}

function loadDictionary()
  local f = io.open(dictFile, "r")
  if f then
    local c = f:read("*all")
    f:close()
    if c and c ~= "" then
      local fn = loadstring("return "..c)
      if fn then changeTable = fn() end
      if type(changeTable) ~= "table" then changeTable = {} end
    end
  end
end

function saveDictionary()
  local f = io.open(dictFile, "w")
  if f then
    local items = {}
    for w,c in pairs(changeTable) do
      table.insert(items, string.format("[%q]=%q",w,c))
    end
    f:write("{"..table.concat(items,",").."}")
    f:close()
  end
end

function addToDictionary(w,c)
  if w and c and w~="" and c~="" then
    changeTable[w]=c
    saveDictionary()
    return true
  end
  return false
end

function getSavedLanguage(file, defVal)
  local f = io.open(file,"r")
  if f then
    local c = f:read("*all")
    f:close()
    return c:gsub("%s+","")
  end
  return defVal
end

function saveLanguage(file, code)
  local f = io.open(file,"w")
  if f then f:write(code) f:close() end
end

local languageItems = {"Urdu (Pakistan)","English (US)","English (UK)","Hindi (India)","Arabic (Saudi Arabia)","French (France)","German (Germany)","Spanish (Spain)","Turkish (Turkey)","Chinese (Mandarin)","Japanese (Japan)","Korean (South Korea)"}
local languageCodes = {"ur-PK","en-US","en-GB","hi-IN","ar-SA","fr-FR","de-DE","es-ES","tr-TR","zh-CN","ja-JP","ko-KR"}
local languageNamesForAI = {["ur-PK"]="Urdu",["en-US"]="English",["en-GB"]="English",["hi-IN"]="Hindi",["ar-SA"]="Arabic",["fr-FR"]="French",["de-DE"]="German",["es-ES"]="Spanish",["tr-TR"]="Turkish",["zh-CN"]="Chinese",["ja-JP"]="Japanese",["ko-KR"]="Korean"}

local uniqueTypingModes = {
  "Smart Pro Mode",
  "Shayari Mode",
  "Boss / Interview Mode",
  "Roman Urdu to Urdu Mode",
  "Caption + Hashtag Mode",
  "Dua / Respect Mode"
}

-- ═══ SIRF FREE AUR WORKING MODELS ═══
local geminiModelsList = {
  "gemini-2.0-flash",
  "gemini-2.5-flash",
  "gemini-1.5-flash",
  "gemini-1.5-flash-8b"
}

local punctuationOptions = {
  "Period (.)",
  "Comma (,)",
  "Exclamation (!)",
  "Question (?)",
  "None"
}

local punctuationMap = {
  ["Period (.)"] = ". ",
  ["Comma (,)"] = ", ",
  ["Exclamation (!)"] = "! ",
  ["Question (?)"] = "? ",
  ["None"] = ""
}

local romanToUrdu = {
  ["salam"]="سلام",
  ["kaisay"]="کیسے",
  ["shukriya"]="شکریہ",
  ["khushi"]="خوشی",
  ["mohabbat"]="محبت",
  ["dost"]="دوست",
  ["zindagi"]="زندگی",
  ["dil"]="دل",
  ["jaan"]="جان",
  ["pyar"]="پیار",
  ["allah"]="اللہ",
  ["dua"]="دعا",
  ["bhai"]="بھائی",
  ["ami"]="امی",
  ["abu"]="ابو",
  ["acha"]="اچھا",
  ["bohat"]="بہت"
}

local emojiMap = {
  ["khushi"]="😉",
  ["mohabbat"]="💅",
  ["pyar"]="💅",
  ["love"]="❤️",
  ["dost"]="👍",
  ["dil"]="❤️",
  ["jaan"]="💄",
  ["dua"]="🤲",
  ["allah"]="🕫",
  ["shadi"]="💲",
  ["zindagi"]="🌮",
  ["shukriya"]="🙏",
  ["pakistan"]="🇵🇰",
  ["bhai"]="👍",
  ["ami"]="❤️",
  ["abu"]="❤️"
}

function applyEmojis(text)
  if not appSettings.emojiEnabled then return text end
  for word, emoji in pairs(emojiMap) do
    text = text:gsub("%f[%a]"..word.."%f[%A]", word.." "..emoji)
  end
  return text
end

function applyTypingMode(text)
  local mode = appSettings.typingMode or "Smart Pro Mode"
  if mode == "Boss / Interview Mode" then
    text = text:gsub("yaar", "Respected Sir")
    text = text:gsub("bhai", "Dear Sir")
    if not text:match("^Dear") and not text:match("^Respected") then
      text = "Respected Sir, " .. text
    end
    return text
  elseif mode == "Roman Urdu to Urdu Mode" then
    for r, u in pairs(romanToUrdu) do
      text = text:gsub("%f[%a]"..r.."%f[%A]", u)
    end
    return text
  elseif mode == "Caption + Hashtag Mode" then
    if not text:match("#") then
      text = text .. " #BridgeTech #Viral #Trending"
    end
    return text
  elseif mode == "Dua / Respect Mode" then
    if not text:match("Ameen") and not text:match("آمین") then
      text = text .. " - Ameen"
    end
    return text
  else
    return text
  end
end

-- ═══ TRANSLATION FIX - AB ASLI TRANSLATION HOGI ═══
function translateWithGemini(text, targetCode, callback)
  local apiKey = (appSettings.geminiApiKey or ""):gsub("%s+","")
  if apiKey == "" or not appSettings.translationEnabled then
    callback(text)
    return
  end
  local targetName = languageNamesForAI[targetCode] or "English"
  local model = appSettings.geminiModel or "gemini-2.0-flash"
  local prompt = "Translate the following text to " .. targetName .. ". Only return the translated text, no explanation, no quotes: " .. text
  local url = "https://generativelanguage.googleapis.com/v1beta/models/" .. model .. ":generateContent?key=" .. apiKey
  local body = '{"contents":[{"parts":[{"text":' .. string.format("%q", prompt) .. '}]}]}'
  Http.post(url, body, "application/json", function(code, response)
    if code == 200 and response and response ~= "" then
      local ok, result = pcall(function()
        local fn = loadstring("return " .. response:gsub('"([%w_]+)":', '["%1"]='))
        if fn then return fn() end
        return nil
      end)
      -- Simple parse: text ke andar se nikalna
      local translated = response:match('"text"%s*:%s*"([^"]+)"')
      if translated then
        translated = translated:gsub("\\n", " "):gsub('\\"', '"'):gsub("\\\\", "\\")
        callback(translated)
      else
        callback(text)
      end
    else
      callback(text)
    end
  end)
end

function showUpdateMessage(title, msg)
  local d = LuaDialog(service)
  d.setTitle(title)
  d.setMessage(msg)
  d.setButton("OK", function() d.dismiss() end)
  d.show()
end

function showWhatsNewIfNeeded(onDone)
  local f = io.open(lastShownVersionFile, "r")
  local lastVer = ""
  if f then lastVer = f:read("*all") or "" f:close() end
  if lastVer ~= CURRENT_VERSION then
    local cf = io.open(changelogFile, "r")
    if cf then
      local msg = cf:read("*all")
      cf:close()
      if msg and msg ~= "" then
        local d = LuaDialog(service)
        d.setTitle("What's New in v" .. CURRENT_VERSION)
        d.setMessage(msg)
        d.setButton("OK", function()
          d.dismiss()
          local wf = io.open(lastShownVersionFile, "w")
          if wf then wf:write(CURRENT_VERSION) wf:close() end
          if onDone then onDone() end
        end)
        d.show()
        return
      end
    end
    local wf = io.open(lastShownVersionFile, "w")
    if wf then wf:write(CURRENT_VERSION) wf:close() end
  end
  if onDone then onDone() end
end

function checkForUpdates(silentMode)
  if updateInProgress then return end
  local ts = tostring(os.time())
  Http.get(VERSION_URL .. "?t=" .. ts, function(code, response)
    if code ~= 200 or not response then
      if not silentMode then
        mainHandler.post(luajava.createProxy("java.lang.Runnable", { run = function() showUpdateMessage("Update Check Failed", "Could not connect. Code: " .. tostring(code)) end }))
      end
      return
    end
    local onlineVersion = tostring(response):gsub("%s+", "")
    if onlineVersion == "" then return end
    if onlineVersion == CURRENT_VERSION then
      if not silentMode then
        mainHandler.post(luajava.createProxy("java.lang.Runnable", { run = function() showUpdateMessage("Up to Date", "You are already on latest version (" .. CURRENT_VERSION .. ").") end }))
      end
      return
    end
    Http.get(UPDATE_CODE_URL .. "?t=" .. ts, function(code2, newCode)
      if code2 ~= 200 or not newCode or newCode:gsub("%s+", "") == "" then return end
      mainHandler.post(luajava.createProxy("java.lang.Runnable", { run = function()
        local d = LuaDialog(service)
        d.setTitle("Update Available")
        d.setMessage("New version: " .. onlineVersion .. "\nCurrent version: " .. CURRENT_VERSION .. "\n\nDo you want to update now?")
        d.setButton("Update Now", function() d.dismiss() performUpdate(newCode, onlineVersion) end)
        d.setButton2("Later", function() d.dismiss() end)
        d.show()
      end }))
    end)
  end)
end

function performUpdate(newCode, onlineVersion)
  if not newCode or newCode:gsub("%s+", "") == "" then return end
  updateInProgress = true
  local tempPath = PLUGIN_PATH .. ".temp_update"
  local thread = luajava.newInstance("java.lang.Thread", luajava.createProxy("java.lang.Runnable", { run = function()
    local success = false
    pcall(function()
      local f = io.open(tempPath, "w")
      if not f then error("Cannot create temp file") end
      f:write(newCode)
      f:close()
      local check = io.open(PLUGIN_PATH, "r")
      if check then check:close() os.remove(PLUGIN_PATH) end
      local ok, rerr = os.rename(tempPath, PLUGIN_PATH)
      if ok then success = true else error("Rename failed: " .. tostring(rerr)) end
    end)
    updateInProgress = false
    mainHandler.post(luajava.createProxy("java.lang.Runnable", { run = function()
      if success then
        pcall(function()
          Http.get(CHANGELOG_URL .. "?t=" .. tostring(os.time()), function(c, txt)
            if c == 200 and txt then
              local cf = io.open(changelogFile, "w")
              if cf then cf:write(txt) cf:close() end
            end
          end)
        end)
        local d = LuaDialog(service)
        d.setTitle("Update Successful")
        d.setMessage("Updated to version " .. onlineVersion .. ".\n\nPlease restart plugin for changes to take effect.")
        d.setButton("OK", function() d.dismiss() end)
        d.show()
      else
        pcall(function() os.remove(tempPath) end)
        showUpdateMessage("Update Failed", "Could not write new version file.")
      end
    end }))
  end }))
  thread.start()
end

function showSearchLanguageDialog(title, saveFile)
  local dlg = LuaDialog(service)
  dlg.setTitle(title)
  local layout = {
    LinearLayout; orientation="vertical"; padding="15dp";
    { EditText; id="searchBox"; hint="Search..."; textSize="16sp"; layout_width="fill"; layout_marginBottom="10dp"; };
    { ListView; id="langList"; layout_width="fill"; layout_height="350dp"; };
    { Button; text="Cancel"; layout_width="fill"; onClick=function() dlg.dismiss() end; };
  }
  local view = loadlayout(layout)
  local curItems = languageItems
  local curCodes = languageCodes
  local function updateList(filter)
    local fItems = {}
    local fCodes = {}
    filter = filter:lower()
    for i=1,#languageItems do
      if filter=="" or languageItems[i]:lower():find(filter,1,true) then
        table.insert(fItems, languageItems[i])
        table.insert(fCodes, languageCodes[i])
      end
    end
    curItems = fItems
    curCodes = fCodes
    langList.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, fItems))
  end
  updateList("")
  searchBox.addTextChangedListener({ onTextChanged=function(s) updateList(tostring(s)) end })
  langList.onItemClick=function(l,v,p,i)
    saveLanguage(saveFile, curCodes[p+1])
    dlg.dismiss()
  end
  dlg.setView(view)
  dlg.show()
end

function showDictionaryDialog()
  local dlg = LuaDialog(service)
  dlg.setTitle("Dictionary")
  local layout = {
    LinearLayout; orientation="vertical"; padding="20dp";
    { TextView; text="Add Custom Word Replacement:"; textSize="14sp"; textColor="#FF9800"; layout_marginBottom="10dp"; };
    { EditText; id="wrongWord"; hint="Wrong / Target word"; textSize="16sp"; layout_width="fill"; layout_marginBottom="15dp"; };
    { EditText; id="correctWord"; hint="Correct replacement word"; textSize="16sp"; layout_width="fill"; layout_marginBottom="20dp"; };
    { LinearLayout; orientation="horizontal"; layout_width="fill";
      { Button; text="Cancel"; layout_width="fill"; layout_weight="1"; onClick=function() dlg.dismiss() end; };
      { View; layout_width="10dp"; };
      { Button; text="Save Word"; layout_width="fill"; layout_weight="1"; onClick=function()
        local w = wrongWord.getText().toString()
        local c = correctWord.getText().toString()
        if w~="" and c~="" then addToDictionary(w,c) dlg.dismiss() end
      end; };
    };
  }
  dlg.setView(loadlayout(layout))
  dlg.show()
end

function showDictionaryList()
  if next(changeTable)==nil then return end
  local items = {}
  for w,c in pairs(changeTable) do table.insert(items, w.." -> "..c) end
  local listDlg = LuaDialog(service)
  listDlg.setTitle("Saved Dictionary Words")
  local layout = {
    LinearLayout; orientation="vertical"; padding="10dp";
    { ListView; id="list"; layout_width="fill"; layout_height="350dp"; };
    { Button; text="Close"; layout_width="fill"; onClick=function() listDlg.dismiss() end; };
  }
  local view = loadlayout(layout)
  list.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, items))
  listDlg.setView(view)
  listDlg.show()
end

function showSettingsDialog()
  local dlg = LuaDialog(service)
  dlg.setTitle("Settings")
  local layout = {
    ScrollView; layout_width="fill"; layout_height="fill";
    { LinearLayout; orientation="vertical"; padding="20dp";
      { TextView; text="Gemini API Configuration (Free Models Only):"; textSize="14sp"; textColor="#FF9800"; layout_marginBottom="5dp"; };
      { EditText; id="apiKeyInput"; hint="Enter Gemini API Key"; text=appSettings.geminiApiKey; textSize="16sp"; layout_width="fill"; layout_marginBottom="10dp"; };
      { Button; text="Create Free Gemini API Key"; textSize="14sp"; layout_width="fill"; layout_marginBottom="10dp"; onClick=function() local uri=Uri.parse("https://aistudio.google.com/app/apikey") service.startActivity(Intent(Intent.ACTION_VIEW, uri)) end; };
      { TextView; text="Select Gemini Model (Free):"; textSize="14sp"; textColor="#FF9800"; layout_marginBottom="5dp"; };
      { Spinner; id="modelSpinner"; layout_width="fill"; layout_marginBottom="10dp"; };
      { Button; id="testBtn"; text="Test API"; textSize="15sp"; layout_width="fill"; layout_marginBottom="10dp"; };
      { TextView; id="testResult"; text=""; textSize="15sp"; gravity="center"; layout_marginBottom="15dp"; };
      { LinearLayout; orientation="horizontal"; layout_width="fill";
        { Button; text="Cancel"; layout_width="fill"; layout_weight="1"; onClick=function() dlg.dismiss() end; };
        { View; layout_width="10dp"; };
        { Button; text="Save Settings"; layout_width="fill"; layout_weight="1"; onClick=function() appSettings.geminiApiKey=apiKeyInput.getText().toString() saveSettings() dlg.dismiss() end; };
      };
    };
  }
  local view = loadlayout(layout)
  local adapter = ArrayAdapter(service, android.R.layout.simple_spinner_item, geminiModelsList)
  adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
  modelSpinner.setAdapter(adapter)
  for i=1,#geminiModelsList do
    if geminiModelsList[i]==appSettings.geminiModel then modelSpinner.setSelection(i-1) break end
  end
  modelSpinner.onItemSelected=function(p,v,pos,id) appSettings.geminiModel=geminiModelsList[pos+1] end
  testBtn.onClick=function()
    local key = apiKeyInput.getText().toString():gsub("%s+","")
    if key == "" then
      testResult.setText("Please Enter API Key First")
      testResult.setTextColor(0xFFFF0000)
      return
    end
    testResult.setText("Testing... Please Wait")
    testResult.setTextColor(0xFFFF9800)
    testBtn.setEnabled(false)
    local th = luajava.newInstance("java.lang.Thread", luajava.createProxy("java.lang.Runnable", { run = function()
      local success = false
      local errMsg = ""
      local ok, err = pcall(function()
        import "java.net.URL"
        local urlStr = "https://generativelanguage.googleapis.com/v1beta/models?key="..key
        local url = URL(urlStr)
        local conn = url.openConnection()
        conn.setRequestMethod("GET")
        conn.setConnectTimeout(15000)
        conn.setReadTimeout(15000)
        local code = conn.getResponseCode()
        if code == 200 then success = true else success = false errMsg = "Code: "..code end
      end)
      if not ok then success = false errMsg = "Network Error" end
      mainHandler.post(luajava.createProxy("java.lang.Runnable", { run = function()
        testBtn.setEnabled(true)
        if success then
          testResult.setText("Valid - API Key is Working")
          testResult.setTextColor(0xFF00C853)
        else
          testResult.setText("Not Valid - Check API Key ("..errMsg..")")
          testResult.setTextColor(0xFFFF0000)
        end
      end }))
    end }))
    th.start()
  end
  dlg.setView(view)
  dlg.show()
end

function startVoiceTyping()
  local editText = service.getEditText()
  if not editText then showMainDialog() return end
  local langCode = getSavedLanguage(langFile, "ur-PK")
  local context = service.getApplicationContext()
  local speechRec = SpeechRecognizer.createSpeechRecognizer(context)
  local listener = RecognitionListener {
    onResults = function(results)
      local arr = results.getParcelableArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
      if arr and arr.size() > 0 then
        local spokenText = arr.get(0)
        for w,c in pairs(changeTable) do spokenText = spokenText:gsub(w,c) end
        spokenText = applyTypingMode(spokenText)
        spokenText = applyEmojis(spokenText)
        local punct = punctuationMap[appSettings.punctuationMode] or ". "
        if punct ~= "" then
          spokenText = spokenText:gsub("%s([?,!])", "%1")
          if not spokenText:match("[.?!,.]$") then spokenText = spokenText .. punct end
        end
        -- Translation yahan se hogi
        if appSettings.translationEnabled then
          local targetCode = getSavedLanguage(transLangFile, "en-US")
          local sourceCode = getSavedLanguage(langFile, "ur-PK")
          if targetCode ~= sourceCode then
            translateWithGemini(spokenText, targetCode, function(finalText)
              mainHandler.post(luajava.createProxy("java.lang.Runnable", { run = function() service.insertText(editText, finalText) end }))
            end)
          else
            service.insertText(editText, spokenText)
          end
        else
          service.insertText(editText, spokenText)
        end
      end
      speechRec.destroy()
    end,
    onError = function(code) speechRec.destroy() return false end,
  }
  local intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
  intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
  intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE, langCode)
  speechRec.setRecognitionListener(listener)
  speechRec.startListening(intent)
end

function showFeedbackDialog()
  local dlg = LuaDialog(service)
  dlg.setTitle("Send Feedback")
  local layout = {
    LinearLayout; orientation="vertical"; padding="20dp";
    { TextView; text="Your Name:"; textSize="14sp"; textColor="#FF9800"; layout_marginBottom="5dp"; };
    { EditText; id="fbName"; hint="Enter Your Name"; textSize="16sp"; layout_width="fill"; layout_marginBottom="12dp"; };
    { TextView; text="WhatsApp Number with Country Code:"; textSize="14sp"; textColor="#FF9800"; layout_marginBottom="5dp"; };
    { EditText; id="fbNumber"; hint="+92 300-0000000"; textSize="16sp"; layout_width="fill"; layout_marginBottom="12dp"; };
    { TextView; text="Your Feedback:"; textSize="14sp"; textColor="#FF9800"; layout_marginBottom="5dp"; };
    { EditText; id="fbMsg"; hint="Write your feedback / suggestion..."; textSize="16sp"; layout_width="fill"; layout_height="120dp"; layout_marginBottom="15dp"; };
    { LinearLayout; orientation="horizontal"; layout_width="fill";
      { Button; text="Cancel"; layout_width="fill"; layout_weight="1"; onClick=function() dlg.dismiss() end; };
      { View; layout_width="10dp"; };
      { Button; text="Send"; layout_width="fill"; layout_weight="1"; onClick=function()
        local name = fbName.getText().toString()
        local num = fbNumber.getText().toString()
        local msg = fbMsg.getText().toString()
        if name=="" or msg=="" then return end
        local fullMsg = "Feedback - Expensive Typer\n\nName: "..name.."\nWhatsApp: "..num.."\n\nFeedback:\n"..msg
        local enc = Uri.encode(fullMsg)
        local url = "https://wa.me/923057040811?text="..enc
        service.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        dlg.dismiss()
      end; };
    };
  }
  dlg.setView(loadlayout(layout))
  dlg.show()
end

function showAboutDialog()
  local d = LuaDialog(service)
  d.setTitle("About Expensive Typer")
  local layout = {
    ScrollView; layout_width="fill"; layout_height="fill";
    { LinearLayout; orientation="vertical"; padding="20dp";
      { TextView; text="Expensive Typer"; textSize="22sp"; gravity="center"; textColor="#FF9800"; layout_marginBottom="2dp"; };
      { TextView; text="Developed by Bridge Tech"; textSize="14sp"; gravity="center"; textColor="#AAAAAA"; layout_marginBottom="2dp"; };
      { TextView; text="Project by AbdulRafay"; textSize="16sp"; gravity="center"; textColor="#FFFFFF"; layout_marginBottom="15dp"; };
      { TextView; text="Description"; textSize="16sp"; textColor="#FF9800"; layout_marginBottom="5dp"; };
      { TextView; text="Expensive Typer is an advanced voice typing extension made for fast, smart and professional typing.\n\nIs me aap bol kar Urdu, English aur doosri languages me type kar sakte hain. Smart Pro Mode, Shayari Mode, Boss / Interview Mode, Roman Urdu to Urdu Mode, Caption + Hashtag Mode aur Dua / Respect Mode se aap ki typing aur bhi behtar ho jati hai.\n\nCustom Dictionary, Auto Punctuation, Emojis aur Translation Mode se ye extension har user ke liye complete solution hai.\n\nBridge Tech Welfare ki taraf se banaya gaya ye project har Pakistani user ke liye free aur easy banaya gaya hai."; textSize="14sp"; textColor="#FFFFFF"; layout_marginBottom="15dp"; };
      { TextView; text="Contact Us"; textSize="16sp"; textColor="#FF9800"; layout_marginBottom="10dp"; };
      { Button; text="WhatsApp Channel"; textSize="15sp"; layout_width="fill"; layout_marginBottom="8dp"; onClick=function() service.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://whatsapp.com/channel/0029VbCJfWSAojYuaMuB9E1t"))) end; };
      { Button; text="WhatsApp Community"; textSize="15sp"; layout_width="fill"; layout_marginBottom="8dp"; onClick=function() service.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://chat.whatsapp.com/CDkyuCcPVyEIAkW87j644n"))) end; };
      { Button; text="YouTube Channel"; textSize="15sp"; layout_width="fill"; layout_marginBottom="15dp"; onClick=function() service.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://youtube.com/@instructor-of-btw?si=IFh27qGn8z44985D"))) end; };
      { Button; text="Send Feedback"; textSize="15sp"; layout_width="fill"; layout_marginBottom="10dp"; onClick=function() d.dismiss() showFeedbackDialog() end; };
      { Button; text="Close"; textSize="15sp"; layout_width="fill"; onClick=function() d.dismiss() end; };
    }
  }
  d.setView(loadlayout(layout))
  d.show()
end

function showMainDialog()
  local dlg = LuaDialog(service)
  dlg.setTitle("Expensive Typer")
  local layout = {
    ScrollView; layout_width="fill"; layout_height="fill";
    { LinearLayout; orientation="vertical"; padding="20dp";
      { TextView; text="Expensive Typer"; textSize="20sp"; gravity="center"; layout_marginBottom="2dp"; textColor="#FF9800"; };
      { TextView; text="Developed by Bridge Tech  |  v" .. CURRENT_VERSION; textSize="14sp"; gravity="center"; layout_marginBottom="15dp"; textColor="#AAAAAA"; };
      { Button; text="Select Typing Language"; textSize="15sp"; layout_width="fill"; layout_marginBottom="8dp"; onClick=function() showSearchLanguageDialog("Select Typing Language", langFile) end; };
      { CheckBox; id="transToggle"; text="Enable Translation Mode"; textSize="15sp"; layout_marginBottom="5dp"; };
      { Button; text="Select Translation Language"; textSize="14sp"; layout_width="fill"; layout_marginBottom="10dp"; onClick=function() showSearchLanguageDialog("Select Translation Language", transLangFile) end; };
      { CheckBox; id="emojiToggle"; text="Enable Emojis"; textSize="15sp"; layout_marginBottom="10dp"; };
      { Button; text="Dictionary (Add Words)"; textSize="15sp"; layout_width="fill"; layout_marginBottom="8dp"; onClick=function() showDictionaryDialog() end; };
      { Button; text="View Custom Dictionary"; textSize="15sp"; layout_width="fill"; layout_marginBottom="10dp"; onClick=function() showDictionaryList() end; };
      { TextView; text="Typing Mode:"; textSize="14sp"; textColor="#FF9800"; layout_marginBottom="3dp"; };
      { Spinner; id="modeSpinner"; layout_width="fill"; layout_marginBottom="10dp"; };
      { TextView; text="End Punctuation:"; textSize="14sp"; textColor="#FF9800"; layout_marginBottom="3dp"; };
      { Spinner; id="punctSpinner"; layout_width="fill"; layout_marginBottom="15dp"; };
      { Button; text="Settings"; textSize="15sp"; layout_width="fill"; layout_marginBottom="8dp"; onClick=function() showSettingsDialog() end; };
      { Button; text="Check for Updates"; textSize="15sp"; layout_width="fill"; layout_marginBottom="8dp"; onClick=function() checkForUpdates(false) end; };
      { Button; text="About & Official Links"; textSize="15sp"; layout_width="fill"; layout_marginBottom="15dp"; onClick=function() showAboutDialog() end; };
      { Button; text="Exit App"; textSize="15sp"; layout_width="fill"; onClick=function() dlg.dismiss() end; };
    }
  }
  local view = loadlayout(layout)
  transToggle.setChecked(appSettings.translationEnabled)
  transToggle.setOnCheckedChangeListener({ onCheckedChanged=function(v,c) appSettings.translationEnabled=c saveSettings() end })
  emojiToggle.setChecked(appSettings.emojiEnabled)
  emojiToggle.setOnCheckedChangeListener({ onCheckedChanged=function(v,c) appSettings.emojiEnabled=c saveSettings() end })
  local ma = ArrayAdapter(service, android.R.layout.simple_spinner_item, uniqueTypingModes)
  ma.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
  modeSpinner.setAdapter(ma)
  for i=1,#uniqueTypingModes do
    if uniqueTypingModes[i]==appSettings.typingMode then modeSpinner.setSelection(i-1) break end
  end
  modeSpinner.onItemSelected=function(p,v,pos,id) appSettings.typingMode=uniqueTypingModes[pos+1] saveSettings() end
  local pa = ArrayAdapter(service, android.R.layout.simple_spinner_item, punctuationOptions)
  pa.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
  punctSpinner.setAdapter(pa)
  for i=1,#punctuationOptions do
    if punctuationOptions[i]==appSettings.punctuationMode then punctSpinner.setSelection(i-1) break end
  end
  punctSpinner.onItemSelected=function(p,v,pos,id) appSettings.punctuationMode=punctuationOptions[pos+1] saveSettings() end
  dlg.setView(view)
  dlg.show()
  mainHandler.postDelayed(luajava.createProxy("java.lang.Runnable", { run = function() pcall(function() checkForUpdates(true) end) end }), 3000)
end

loadDictionary()
showWhatsNewIfNeeded(function()
  local editText = service.getEditText()
  if editText then startVoiceTyping() else showMainDialog() end
end)
