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
import "java.net.URL"
import "java.io.BufferedReader"
import "java.io.InputStreamReader"
import "java.io.OutputStreamWriter"

-- ═══ AUTO-UPDATE CONFIG ═══
local CURRENT_VERSION = "1.6"
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
  geminiModel = "gemini-2.5-flash",
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
  -- FIXED: Purane galat models ko sahi wale par le jao, taake 404 na aaye
  if appSettings.geminiModel == "gemini-3-flash" or appSettings.geminiModel == "gemini-3-pro" or appSettings.geminiModel == "gemini-3.1-flash" or appSettings.geminiModel == "gemini-4-flash" or appSettings.geminiModel == "gemini-4-pro" or appSettings.geminiModel == "gemini-1.5-flash" or appSettings.geminiModel == "gemini-1.5-flash-8b" or appSettings.geminiModel == "gemini-2.0-flash" then
    appSettings.geminiModel = "gemini-2.5-flash"
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

-- ═══ GEMINI LATEST MODELS - FIXED (404 Fix) ═══
local geminiModelsList = {
  "gemini-2.5-flash",
  "gemini-2.5-flash-lite",
  "gemini-3-flash-preview",
  "gemini-3.1-pro-preview",
  "gemini-3.5-flash-lite",
  "gemini-2.0-flash"
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

-- ═══ SENTENCE-LEVEL & KEYWORD EMOJI ENGINE ═══
local sentenceContextEmojis = {
  { keys = {"salam", "assalam", "hello", "hi", "hey", "سلام", "السلام", "ہیلو"}, emoji = "👋" },
  { keys = {"kaise", "kaisay", "how are", "kya hal", "haal", "کیسے", "کیسی", "حال", "خیریت"}, emoji = "😊" },
  { keys = {"shukriya", "thanks", "thank", "meharbani", "شکریہ", "مہربانی", "نوازش"}, emoji = "🙏" },
  { keys = {"love", "pyar", "mohabbat", "dil", "jaan", "heart", "miss", "محبت", "پیار", "دل", "جان", "یاد"}, emoji = "❤️" },
  { keys = {"khushi", "happy", "smile", "maza", "enjoy", "great", "awesome", "خوشی", "خوش", "مزہ", "زبردست", "بہترین"}, emoji = "😄" },
  { keys = {"mubarak", "congrat", "shadi", "eid", "birthday", "party", "مبارک", "شادی", "عید", "سالگرہ"}, emoji = "🎉" },
  { keys = {"dua", "allah", "ameen", "inshallah", "mashallah", "subhanallah", "pray", "god", "دعا", "اللہ", "آمین", "انشاءاللہ", "ماشاءاللہ", "سبحان"}, emoji = "🤲✨" },
  { keys = {"sorry", "maaf", "sad", "udaas", "dukh", "dard", "ro", "cry", "afsos", "معاف", "اداس", "دکھ", "درد", "افسوس", "پریشان"}, emoji = "😔" },
  { keys = {"gussa", "angry", "naraz", "fight", "غصہ", "ناراض", "لڑائی"}, emoji = "😠" },
  { keys = {"dost", "friend", "bhai", "yaar", "bro", "sister", "behen", "دوست", "بھائی", "یار", "بہن"}, emoji = "🤝" },
  { keys = {"ami", "abu", "mother", "father", "mom", "dad", "walid", "امی", "ابو", "ماں", "باپ", "والد"}, emoji = "❤️" },
  { keys = {"kaam", "work", "office", "meeting", "study", "parhai", "exam", "کام", "دفتر", "میٹنگ", "پڑھائی", "امتحان"}, emoji = "💼" },
  { keys = {"khana", "chai", "tea", "food", "roti", "biryani", "کھانا", "چائے", "روٹی", "بریانی"}, emoji = "☕🍽️" },
  { keys = {"neend", "sleep", "night", "raat", "subah", "morning", "نیند", "رات", "صبح"}, emoji = "🌙✨" },
  { keys = {"pakistan", "پاکستان"}, emoji = "🇵🇰" },
  { keys = {"acha", "theek", "ok", "okay", "good", "nice", "yes", "han", "ji", "اچھا", "ٹھیک", "جی", "ہاں"}, emoji = "👍" }
}

local function hasEmojiAlready(str)
  for i = 1, #str do
    local b = str:byte(i)
    if b and b >= 240 then
      return true
    end
  end
  return false
end

function applyEmojis(text)
  if not appSettings.emojiEnabled then return text end
  if not text or text == "" then return text end
  if hasEmojiAlready(text) then return text end
  local lowerText = text:lower()
  local matchedEmoji = nil
  for _, group in ipairs(sentenceContextEmojis) do
    for _, kw in ipairs(group.keys) do
      if lowerText:find(kw, 1, true) then
        matchedEmoji = group.emoji
        break
      end
    end
    if matchedEmoji then break end
  end
  if not matchedEmoji then
    if text:find("%?") or text:find("؟") or lowerText:find("kya") or lowerText:find("kyun") or lowerText:find("kab") or lowerText:find("kahan") or lowerText:find("کیا") or lowerText:find("کیوں") or lowerText:find("کب") or lowerText:find("کہاں") then
      matchedEmoji = "🤔"
    elseif text:find("!") then
      matchedEmoji = "✨"
    else
      matchedEmoji = "😊"
    end
  end
  return text .. " " .. matchedEmoji
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

-- ═══ ROBUST JSON TEXT EXTRACTOR ═══
local function extractGeminiText(jsonStr)
  if not jsonStr or jsonStr == "" then return nil end
  local partsPos = jsonStr:find('"parts"')
  local searchArea = partsPos and jsonStr:sub(partsPos) or jsonStr
  local textStart = searchArea:find('"text"%s*:%s*"')
  if not textStart then return nil end
  local _, quoteStart = searchArea:find('"text"%s*:%s*"', textStart)
  local i = quoteStart + 1
  local len = #searchArea
  local out = {}
  while i <= len do
    local c = searchArea:sub(i, i)
    if c == "\\" then
      local nxt = searchArea:sub(i + 1, i + 1)
      if nxt == "n" then table.insert(out, " ")
      elseif nxt == "r" then
      elseif nxt == "t" then table.insert(out, " ")
      elseif nxt == '"' then table.insert(out, '"')
      elseif nxt == "\\" then table.insert(out, "\\")
      elseif nxt == "u" then
        local hex = searchArea:sub(i + 2, i + 5)
        local code = tonumber(hex, 16)
        if code then
          if code >= 0xD800 and code <= 0xDBFF and searchArea:sub(i + 6, i + 7) == "\\u" then
            local lowHex = searchArea:sub(i + 8, i + 11)
            local lowCode = tonumber(lowHex, 16)
            if lowCode and lowCode >= 0xDC00 and lowCode <= 0xDFFF then
              local cp = 0x10000 + ((code - 0xD800) * 0x400) + (lowCode - 0xDC00)
              table.insert(out, string.char(
                0xF0 + math.floor(cp / 262144),
                0x80 + (math.floor(cp / 4096) % 64),
                0x80 + (math.floor(cp / 64) % 64),
                0x80 + (cp % 64)
              ))
              i = i + 10
            end
          elseif code < 0x80 then
            table.insert(out, string.char(code))
            i = i + 4
          elseif code < 0x800 then
            table.insert(out, string.char(0xC0 + math.floor(code / 64), 0x80 + (code % 64)))
            i = i + 4
          else
            table.insert(out, string.char(0xE0 + math.floor(code / 4096), 0x80 + (math.floor(code / 64) % 64), 0x80 + (code % 64)))
            i = i + 4
          end
        end
      else
        table.insert(out, nxt)
      end
      i = i + 2
    elseif c == '"' then
      break
    else
      table.insert(out, c)
      i = i + 1
    end
  end
  return table.concat(out)
end

-- ═══ GEMINI PROCESSOR (TRANSLATION + CONTEXTUAL EMOJIS) ═══
function processWithGemini(text, doTranslate, targetCode, addEmojis, callback)
  local apiKey = (appSettings.geminiApiKey or ""):gsub("%s+","")
  if apiKey == "" or (not doTranslate and not addEmojis) then
    callback(text)
    return
  end
  local targetName = languageNamesForAI[targetCode] or "English"
  local model = appSettings.geminiModel or "gemini-2.5-flash"
  local prompt = ""
  if doTranslate and addEmojis then
    prompt = "Translate the following text into " .. targetName .. " and add 1 or 2 relevant expressive emojis matching the sentence meaning and tone. Return ONLY the final text with emojis, no quotes, no explanation:\n" .. text
  elseif doTranslate then
    prompt = "Translate the following text into " .. targetName .. ". Return ONLY the translated text without any quotes, explanation, or extra words:\n" .. text
  else
    prompt = "Add 1 or 2 relevant expressive emojis to the following sentence according to its meaning, mood, and context without changing the words. Return ONLY the sentence with emojis, no quotes or explanation:\n" .. text
  end
  local escapedPrompt = prompt:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "")
  local urlStr = "https://generativelanguage.googleapis.com/v1beta/models/" .. model .. ":generateContent?key=" .. apiKey
  local jsonBody = '{"contents":[{"parts":[{"text":"' .. escapedPrompt .. '"}]}]}'
  local th = luajava.newInstance("java.lang.Thread", luajava.createProxy("java.lang.Runnable", {
    run = function()
      local resultText = nil
      local errInfo = nil
      pcall(function()
        local url = URL(urlStr)
        local conn = url.openConnection()
        conn.setRequestMethod("POST")
        conn.setRequestProperty("Content-Type", "application/json; charset=UTF-8")
        conn.setRequestProperty("Accept", "application/json")
        conn.setConnectTimeout(25000)
        conn.setReadTimeout(25000)
        conn.setDoOutput(true)
        local outStream = conn.getOutputStream()
        local writer = OutputStreamWriter(outStream, "UTF-8")
        writer.write(jsonBody)
        writer.flush()
        writer.close()
        outStream.close()
        local code = conn.getResponseCode()
        local stream = (code == 200) and conn.getInputStream() or conn.getErrorStream()
        if stream then
          local reader = BufferedReader(InputStreamReader(stream, "UTF-8"))
          local sb = {}
          local line = reader.readLine()
          while line ~= nil do
            table.insert(sb, tostring(line))
            line = reader.readLine()
          end
          reader.close()
          local fullResp = table.concat(sb, "\n")
          if code == 200 then
            resultText = extractGeminiText(fullResp)
          else
            errInfo = "API Error " .. tostring(code)
          end
        else
          errInfo = "HTTP " .. tostring(code)
        end
      end)
      mainHandler.post(luajava.createProxy("java.lang.Runnable", {
        run = function()
          if resultText and resultText ~= "" then
            resultText = resultText:gsub("^%s+", ""):gsub("%s+$", "")
            callback(resultText)
          else
            if errInfo and doTranslate then
              Toast.makeText(service, "Gemini (" .. model .. "): " .. errInfo, Toast.LENGTH_SHORT).show()
            end
            callback(text)
          end
        end
      }))
    end
  }))
  th.start()
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
      { TextView; text="Gemini API Configuration (Gemini Models):"; textSize="14sp"; textColor="#FF9800"; layout_marginBottom="5dp"; };
      { EditText; id="apiKeyInput"; hint="Enter Gemini API Key"; text=appSettings.geminiApiKey; textSize="16sp"; layout_width="fill"; layout_marginBottom="10dp"; };
      { Button; text="Create Free Gemini API Key"; textSize="14sp"; layout_width="fill"; layout_marginBottom="10dp"; onClick=function() local uri=Uri.parse("https://aistudio.google.com/app/apikey") service.startActivity(Intent(Intent.ACTION_VIEW, uri)) end; };
      { TextView; text="Select Gemini Model:"; textSize="14sp"; textColor="#FF9800"; layout_marginBottom="5dp"; };
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
  local foundIdx = 0
  for i=1,#geminiModelsList do
    if geminiModelsList[i]==appSettings.geminiModel then foundIdx = i-1 break end
  end
  modelSpinner.setSelection(foundIdx)
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
        local spokenText = tostring(arr.get(0))
        for w,c in pairs(changeTable) do spokenText = spokenText:gsub(w,c) end
        spokenText = applyTypingMode(spokenText)
        local function finishAndInsert(outText)
          outText = applyEmojis(outText)
          local punct = punctuationMap[appSettings.punctuationMode] or ". "
          if punct ~= "" then
            outText = outText:gsub("%s([?,!])", "%1")
            if not outText:match("[.?!,.]$") then outText = outText .. punct end
          end
          mainHandler.post(luajava.createProxy("java.lang.Runnable", {
            run = function() service.insertText(editText, outText) end
          }))
        end
        local targetCode = getSavedLanguage(transLangFile, "en-US")
        local sourceCode = getSavedLanguage(langFile, "ur-PK")
        local shouldTranslate = appSettings.translationEnabled and (targetCode ~= sourceCode)
        local shouldEmoji = appSettings.emojiEnabled
        local apiKey = (appSettings.geminiApiKey or ""):gsub("%s+","")
        if (shouldTranslate or shouldEmoji) and apiKey ~= "" then
          processWithGemini(spokenText, shouldTranslate, targetCode, shouldEmoji, function(finalText)
            finishAndInsert(finalText)
          end)
        else
          if shouldTranslate and apiKey == "" then
            Toast.makeText(service, "Add Gemini API Key in Settings for Translation", Toast.LENGTH_SHORT).show()
          end
          finishAndInsert(spokenText)
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
