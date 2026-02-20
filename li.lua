--[[
    Stalkie 2.0 - Full Revamp
    Built with kiwisense UI library
]]

local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/Rootleak/roblox/refs/heads/main/li.lua"))()

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VoiceChatInternal = game:GetService("VoiceChatInternal")
local VoiceChatService = game:GetService("VoiceChatService")
local AudioFocusService = game:GetService("AudioFocusService")

local Player = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- Mobile detection
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- Version
local VERSION = "v2.1"

-- Game detection system
local SUPPORTED_GAMES = {
    [15546218972] = {name = "Mic up 18+", canTeleport = false},
    [6884319169] = {name = "Mic up", canTeleport = false},
    [5683833663] = {name = "Ragdoll engine", canTeleport = true},
    [78699621133325] = {name = "Meet People Across The World", canTeleport = true},
    [5991163185] = {name = "Spray Paint", canTeleport = true}
}

local currentPlaceId = game.PlaceId
local currentGame = SUPPORTED_GAMES[currentPlaceId]

-- Create unique games list (no duplicates by name)
local UNIQUE_GAMES = {}
for placeId, gameInfo in pairs(SUPPORTED_GAMES) do
    if not UNIQUE_GAMES[gameInfo.name] then
        UNIQUE_GAMES[gameInfo.name] = {
            name = gameInfo.name,
            canTeleport = gameInfo.canTeleport,
            placeIds = {}
        }
    end
    table.insert(UNIQUE_GAMES[gameInfo.name].placeIds, placeId)
end

-- Get TTS remotes for Mic Up games
local TTS = nil
local TTSToggle = nil
if currentGame then
    pcall(function()
        TTS = ReplicatedStorage:FindFirstChild("event_tts")
        TTSToggle = ReplicatedStorage:FindFirstChild("event_tts_toggle")
    end)
end

-- Variables
local CustomTime = false
local OldTime = nil
local SettedTime = 14

-- Fly variables
local flyEnabled = false
local flySpeed = 50
local flyKeybind = Enum.KeyCode.V
local flyBodyGyro = nil
local flyBodyVelocity = nil

-- Noclip variables
local noclipEnabled = false
local noclipKeybind = Enum.KeyCode.N
local noclipConnection = nil

-- FTP variables
local ftpEnabled = true
local ftpKeybind = Enum.KeyCode.F

-- Anti Lag variables
local antiLagEnabled = false

-- Void Walk variables
local voidWalkEnabled = false

-- Booth spam variables
local boothTitles = {}
local boothTitleIndex = 1
local boothSelectedMaterial = "Random"
local boothSpamRunning = false
local boothSpamTask = nil
local boothOutfitNumber = 13461561617
local boothTextures = {"wood", "slate", "fabric", "plastic", "concrete"}
local boothEvent = nil

pcall(function()
    boothEvent = ReplicatedStorage:FindFirstChild("event_booth_exit")
end)

-- Voice variables
local autoConnection = nil

-- Suggestion variables
local suggestionText = ""
local lastSuggestionTime = 0
local SUGGESTION_COOLDOWN = 60

-- LeakCheck query function (WebSocket-based, no standalone UI)
local function queryLeakCheck(username)
    local HttpService = game:GetService("HttpService")
    local PROXY_URL   = "https://neil.0riginalwarrior55.workers.dev/query"
    local wsUrl       = PROXY_URL:gsub("^https://", "wss://"):gsub("^http://", "ws://")

    -- Create raw WebSocket
    local ws
    if syn and syn.websocket and syn.websocket.connect then
        local ok, w = pcall(function() return syn.websocket.connect(wsUrl) end)
        if ok then ws = w end
    elseif WebSocket and WebSocket.connect then
        local ok, w = pcall(function() return WebSocket.connect(wsUrl) end)
        if ok then ws = w end
    end
    if not ws then return {status = "error", text = "WebSocket unavailable"} end

    local data, responseReceived, connectionError, errorMsg = nil, false, false, ""

    local setupOk = pcall(function()
        ws.OnMessage:Connect(function(msg)
            if responseReceived then return end
            local s, d = pcall(HttpService.JSONDecode, HttpService, tostring(msg))
            if s and d then data = d else connectionError = true errorMsg = "JSON decode failed" end
            responseReceived = true
        end)
        ws.OnClose:Connect(function()
            if not responseReceived then
                connectionError = true
                errorMsg = "Connection closed unexpectedly"
                responseReceived = true
            end
        end)
    end)
    if not setupOk then return {status = "error", text = "WS handler setup failed"} end

    task.wait(0.05)
    local sent = pcall(function()
        ws:Send(HttpService:JSONEncode({query = username, type = "username"}))
    end)
    if not sent then pcall(function() ws:Close() end) return {status = "error", text = "Failed to send query"} end

    local elapsed = 0
    while not responseReceived and elapsed < 15 do task.wait(0.1) elapsed += 0.1 end
    pcall(function() ws:Close() end)

    if not responseReceived then return {status = "error", text = "Request timeout"} end
    if connectionError      then return {status = "error", text = errorMsg} end
    if not data             then return {status = "error", text = "No data received"} end

    if not data.success then
        local em = tostring(data.error or data.message or "API error")
        local el = em:lower()
        if el:find("rate") or el:find("limit") or el:find("quota")
           or data.statusCode == 429 or data.statusCode == 403 then
            return {status = "error", text = "Rate limited", errorType = "rate_limit"}
        end
        return {status = "error", text = "API: " .. em}
    end

    local found = data.found or 0
    if found == 0 then return {status = "no_leaks", found = 0, leaks = {}} end

    local leaks = {}
    for _, breach in ipairs(data.result or {}) do
        local source = breach.source and breach.source.name or "Unknown"
        local rawDate = breach.source and breach.source.breach_date
        local date = (rawDate and rawDate ~= "" and rawDate ~= "None") and tostring(rawDate) or nil
        local fields = {}  -- ordered array of {key=, value=}
        for _, f in ipairs(breach.fields or {}) do
            if breach[f] then
                local val
                if f == "origin" then
                    if type(breach[f]) == "table" then
                        local seen, parts = {}, {}
                        for _, domain in ipairs(breach[f]) do
                            local norm = tostring(domain):gsub("^www%.", "")
                            if not seen[norm] then seen[norm] = true; table.insert(parts, norm) end
                        end
                        val = table.concat(parts, ", ")
                    else
                        val = tostring(breach[f]):gsub("^www%.", "")
                    end
                else
                    val = tostring(breach[f])
                end
                table.insert(fields, {key = f, value = val})
            end
        end
        table.insert(leaks, {source = source, date = date, fields = fields})
    end
    return {status = "leaks", found = found, leaks = leaks}
end

-- Create Window
local Window = Library:Window({
    Name = "Stalkie",
    Version = VERSION,
    Logo = "135215559087473",
    FadeSpeed = 0.25
})

local ESPPreview = Library:ESPPreview({MainFrame = Window.Items["MainFrame"]})

-- Create Watermark and Keybind List
local Watermark = Library:Watermark("Stalkie 2.0", "135215559087473")
Watermark:SetVisibility(false)

local KeybindList = Library:KeybindsList()
KeybindList:SetVisibility(true)

-- Create Main Pages with SubPages
local Pages = {
    ["Character"] = Window:Page({
        Name = "character",
        Icon = "111178525804834",
        SubPages = true
    }),
    
    ["Game"] = Window:Page({
        Name = "game",
        Icon = "136623465713368",
        SubPages = true
    }),
    
    ["Settings"] = Window:Page({
        Name = "settings",
        Icon = "137300573942266",
        SubPages = true
    })
}

--[[ ==================== CHARACTER CATEGORY ==================== ]]--
do
    -- Create SubPages under Character
    local Subpages = {
        ["Misc"] = Pages["Character"]:SubPage({Name = "misc", Icon = "136623465713368", Columns = 2}),
        ["Voice"] = Pages["Character"]:SubPage({Name = "voice", Icon = "111178525804834", Columns = 2})
    }
    
    --[[ ==================== MISC SUB-PAGE ==================== ]]--
    do
        local PlayerSection = Subpages["Misc"]:Section({Name = "player", Icon = "135799335731002", Side = 1})

        --[[ PLAYER SECTION ]]--
        PlayerSection:Toggle({
            Name = "anti lag",
            Flag = "Misc/Player/AntiLag",
            Default = false,
            Callback = function(Value)
                antiLagEnabled = Value
                
                if Value then
                    for _, player in pairs(Players:GetPlayers()) do
                        if player ~= Player and player.Character then
                            for _, part in pairs(player.Character:GetDescendants()) do
                                if part:IsA("BasePart") then
                                    part.CastShadow = false
                                end
                                if part:IsA("Decal") or part:IsA("Texture") then
                                    part.Transparency = 1
                                end
                            end
                        end
                    end
                    
                    Library:Notification({
                        Name = "Anti Lag",
                        Description = "Reduced visual quality of other players",
                        Duration = 3,
                        Icon = "116339777575852",
                        IconColor = Color3.fromRGB(52, 255, 164)
                    })
                end
            end
        })

        local flyConnection = nil

        local FlyToggle = PlayerSection:Toggle({
            Name = "fly",
            Flag = "Misc/Player/Fly",
            Default = false,
            Callback = function(Value)
                flyEnabled = Value
                
                if Value then
                    local character = Player.Character
                    if not character or not character:FindFirstChild("HumanoidRootPart") then
                        Library:Notification({Name = "Fly", Description = "Character not found!", Duration = 2, Icon = "97118059177470", IconColor = Color3.fromRGB(255, 120, 120)})
                        return
                    end
                    
                    local humanoidRootPart = character.HumanoidRootPart
                    
                    local bodyVelocity = Instance.new("BodyVelocity")
                    bodyVelocity.Velocity = Vector3.new(0, 0, 0)
                    bodyVelocity.MaxForce = Vector3.new(100000, 100000, 100000)
                    bodyVelocity.Parent = humanoidRootPart
                    
                    local bodyGyro = Instance.new("BodyGyro")
                    bodyGyro.MaxTorque = Vector3.new(100000, 100000, 100000)
                    bodyGyro.P = 10000
                    bodyGyro.Parent = humanoidRootPart
                    
                    flyConnection = RunService.Heartbeat:Connect(function()
                        if not flyEnabled or not character or not character:FindFirstChild("HumanoidRootPart") then
                            return
                        end
                        
                        local moveDirection = Vector3.new(0, 0, 0)
                        
                        if UserInputService:IsKeyDown(Enum.KeyCode.W) then
                            moveDirection = moveDirection + (Camera.CFrame.LookVector * flySpeed)
                        end
                        if UserInputService:IsKeyDown(Enum.KeyCode.S) then
                            moveDirection = moveDirection - (Camera.CFrame.LookVector * flySpeed)
                        end
                        if UserInputService:IsKeyDown(Enum.KeyCode.A) then
                            moveDirection = moveDirection - (Camera.CFrame.RightVector * flySpeed)
                        end
                        if UserInputService:IsKeyDown(Enum.KeyCode.D) then
                            moveDirection = moveDirection + (Camera.CFrame.RightVector * flySpeed)
                        end
                        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                            moveDirection = moveDirection + Vector3.new(0, flySpeed, 0)
                        end
                        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
                            moveDirection = moveDirection - Vector3.new(0, flySpeed, 0)
                        end
                        
                        bodyVelocity.Velocity = moveDirection
                        bodyGyro.CFrame = Camera.CFrame
                    end)
                    
                    Library:Notification({
                        Name = "Fly",
                        Description = "Fly enabled - WASD to move, Space/Shift for up/down",
                        Duration = 3,
                        Icon = "116339777575852",
                        IconColor = Color3.fromRGB(52, 255, 164)
                    })
                else
                    if flyConnection then
                        flyConnection:Disconnect()
                        flyConnection = nil
                    end
                    
                    local character = Player.Character
                    if character and character:FindFirstChild("HumanoidRootPart") then
                        for _, obj in pairs(character.HumanoidRootPart:GetChildren()) do
                            if obj:IsA("BodyVelocity") or obj:IsA("BodyGyro") then
                                obj:Destroy()
                            end
                        end
                    end
                end
            end
        })

        FlyToggle:Keybind({
            Name = "FlyKeybind",
            Flag = "Misc/Player/FlyKeybind",
            Mode = "toggle",
            Default = Enum.KeyCode.V,
            Callback = function(Value)
                flyKeybind = Library.Flags["Misc/Player/FlyKeybind"].Key
            end
        })

        PlayerSection:Slider({
            Name = "fly speed",
            Flag = "Misc/Player/FlySpeed",
            Min = 10,
            Max = 200,
            Default = 50,
            Decimals = 1,
            Callback = function(Value)
                flySpeed = Value
            end
        })

        PlayerSection:Toggle({
            Name = "ftp (teleport)",
            Flag = "Misc/Player/FTP",
            Default = true,
            Callback = function(Value)
                ftpEnabled = Value
            end
        })
        
        -- FTP keybind listener (separate from toggle)
        UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end
            if input.KeyCode == ftpKeybind and ftpEnabled then
                local character = Player.Character
                if not character or not character:FindFirstChild("HumanoidRootPart") then
                    return
                end
                
                local mouse = Player:GetMouse()
                local targetPosition = mouse.Hit.Position
                
                if targetPosition then
                    local currentCFrame = character.HumanoidRootPart.CFrame
                    local newPosition = targetPosition + Vector3.new(0, 3, 0)
                    character.HumanoidRootPart.CFrame = CFrame.new(newPosition) * (currentCFrame - currentCFrame.Position)
                end
            end
        end)

        local NoclipToggle = PlayerSection:Toggle({
            Name = "noclip",
            Flag = "Misc/Player/Noclip",
            Default = false,
            Callback = function(Value)
                noclipEnabled = Value
                
                if Value then
                    noclipConnection = RunService.Stepped:Connect(function()
                        local character = Player.Character
                        if character then
                            for _, part in pairs(character:GetDescendants()) do
                                if part:IsA("BasePart") then
                                    part.CanCollide = false
                                end
                            end
                        end
                    end)
                    
                    Library:Notification({
                        Name = "Noclip",
                        Description = "Noclip enabled - walk through walls",
                        Duration = 3,
                        Icon = "116339777575852",
                        IconColor = Color3.fromRGB(52, 255, 164)
                    })
                else
                    if noclipConnection then
                        noclipConnection:Disconnect()
                        noclipConnection = nil
                    end
                    
                    local character = Player.Character
                    if character then
                        for _, part in pairs(character:GetDescendants()) do
                            if part:IsA("BasePart") and (part.Name == "HumanoidRootPart" or part.Name == "LowerTorso" or part.Name == "UpperTorso") then
                                part.CanCollide = true
                            end
                        end
                    end
                end
            end
        })

        NoclipToggle:Keybind({
            Name = "NoclipKeybind",
            Flag = "Misc/Player/NoclipKeybind",
            Mode = "toggle",
            Default = Enum.KeyCode.N,
            Callback = function(Value)
                noclipKeybind = Library.Flags["Misc/Player/NoclipKeybind"].Key
            end
        })

    end

    --[[ ==================== VOICE SUB-PAGE ==================== ]]--
    do
        local VoiceSection = Subpages["Voice"]:Section({Name = "voice", Icon = "111178525804834", Side = 1})
        local SoundboardSection = currentGame and Subpages["Voice"]:Section({Name = "mic up tts", Icon = "115907015044719", Side = 2}) or nil
        
        --[[ VOICE SETTINGS ]]--
        VoiceSection:Label("⚠️ Patched, will try to find a fix.", "Left")
        
        VoiceSection:Toggle({
            Name = "auto unsuspend",
            Flag = "Voice/AutoUnsuspend",
            Default = false,
            Callback = function(Value)
                if Value then
                    autoConnection = VoiceChatInternal.LocalPlayerModerated:Connect(function()
                        task.wait(1)
                        pcall(function()
                            local groupId = VoiceChatInternal:GetGroupId()
                            if groupId then
                                VoiceChatInternal:JoinByGroupId(groupId, false)
                            end
                        end)
                        
                        pcall(function()
                            local groupId = VoiceChatInternal:GetGroupId()
                            if groupId then
                                VoiceChatInternal:JoinByGroupIdToken(groupId, false, true)
                            end
                        end)
                    end)
                else
                    if autoConnection then
                        autoConnection:Disconnect()
                        autoConnection = nil
                    end
                end
            end
        })
        
        VoiceSection:Button({
            Name = "unsuspend",
            Callback = function()
                local groupId = VoiceChatInternal:GetGroupId()
                AudioFocusService:RegisterContextIdFromLua(100)
                task.wait()
                AudioFocusService:RequestFocus(100, 9999999)
                VoiceChatService:joinVoice()
                VoiceChatService:rejoinVoice()
                VoiceChatInternal:JoinByGroupId(groupId, false)
                VoiceChatInternal:JoinByGroupIdToken(groupId, false, true)
                VoiceChatService:joinVoice()
            end
        })
        
        VoiceSection:Button({
            Name = "force priority",
            Callback = function()
                AudioFocusService:RegisterContextIdFromLua(100)
                task.wait()
                AudioFocusService:RequestFocus(100, 9999999)
            end
        })
        
        VoiceSection:Button({
            Name = "leave voice channel",
            Callback = function()
                VoiceChatInternal:Leave()
                VoiceChatInternal:PublishPause(true)
            end
        })
        
        --[[ SOUNDBOARD (Mic Up games only) ]]--
        if currentGame and SoundboardSection then
            local ttsEnabled = false
            local selectedVoice = "masculine_america_02"
            local annoyingSoundEnabled = false
            local annoyingSoundConnection = nil
            local lastTTSAttempt = 0
            local ttsErrorDetected = false
            
            -- Hook LogService for TTS errors
            local LogService = game:GetService("LogService")
            LogService.MessageOut:Connect(function(message, messageType)
                if tick() - lastTTSAttempt < 1 and messageType == Enum.MessageType.MessageWarning then
                    if message:match("Failed to load sound") then
                        ttsErrorDetected = true
                        if message:match("FilteredText") then
                            Library:Notification({Name = "Mic up TTS", Description = "Text filtered - try misspelling words", Duration = 4, Icon = "97118059177470", IconColor = Color3.fromRGB(255, 120, 120)})
                        elseif message:match("FilteredAudio") then
                            Library:Notification({Name = "Mic up TTS", Description = "Audio filtered - text blocked by Roblox", Duration = 4, Icon = "97118059177470", IconColor = Color3.fromRGB(255, 120, 120)})
                        else
                            Library:Notification({Name = "Mic up TTS", Description = "Failed to load sound", Duration = 3, Icon = "97118059177470", IconColor = Color3.fromRGB(255, 120, 120)})
                        end
                    end
                end
            end)
            
            SoundboardSection:Toggle({
                Name = "enable tts",
                Flag = "Voice/EnableTTS",
                Default = false,
                Callback = function(Value)
                    ttsEnabled = Value
                    if TTSToggle then
                        TTSToggle:FireServer("Toggle", Value)
                        Library:Notification({Name = "Mic up TTS", Description = Value and "TTS enabled!" or "TTS disabled!", Duration = 2, Icon = "116339777575852", IconColor = Color3.fromRGB(52, 255, 164)})
                    else
                        Library:Notification({Name = "Mic up TTS", Description = "TTS remote not found!", Duration = 3, Icon = "97118059177470", IconColor = Color3.fromRGB(255, 120, 120)})
                    end
                end
            })
            
            local function playTTS(text, buttonName)
                if not ttsEnabled then
                    Library:Notification({Name = "Mic up TTS", Description = "Please enable TTS first!", Duration = 2, Icon = "97118059177470", IconColor = Color3.fromRGB(255, 120, 120)})
                    return
                end
                
                pcall(function()
                    if TTS then
                        ttsErrorDetected = false
                        lastTTSAttempt = tick()
                        TTS:FireServer(text)
                        
                        task.spawn(function()
                            task.wait(0.5)
                            if not ttsErrorDetected then
                                Library:Notification({Name = "Mic up TTS", Description = "Playing: " .. buttonName, Duration = 2, Icon = "116339777575852", IconColor = Color3.fromRGB(52, 255, 164)})
                            end
                        end)
                    else
                        Library:Notification({Name = "Mic up TTS", Description = "TTS not available!", Duration = 3, Icon = "97118059177470", IconColor = Color3.fromRGB(255, 120, 120)})
                    end
                end)
            end
            
            SoundboardSection:Toggle({
                Name = "earrape",
                Flag = "Voice/Earrape",
                Default = false,
                Callback = function(Value)
                    if Value then
                        if not ttsEnabled then
                            Library:Notification({Name = "Mic up TTS", Description = "Please enable TTS first!", Duration = 2, Icon = "97118059177470", IconColor = Color3.fromRGB(255, 120, 120)})
                            return
                        end
                        if TTSToggle then
                            TTSToggle:FireServer("VoicePreset", "feminine_australia")
                        end
                        annoyingSoundEnabled = true
                        annoyingSoundConnection = task.spawn(function()
                            while annoyingSoundEnabled do
                                pcall(function()
                                    if TTS then
                                        TTS:FireServer("^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^e")
                                    end
                                end)
                                task.wait(9)
                            end
                        end)
                    else
                        annoyingSoundEnabled = false
                        if annoyingSoundConnection then
                            task.cancel(annoyingSoundConnection)
                            annoyingSoundConnection = nil
                        end
                    end
                end
            })
            
            local customTTSText = ""
            SoundboardSection:Textbox({
                Name = "custom tts",
                Flag = "Voice/CustomTTS",
                Placeholder = "misspell to bypass filters",
                Default = "",
                Callback = function(Value)
                    customTTSText = Value
                end
            })
            
            SoundboardSection:Button({
                Name = "play custom tts",
                Callback = function()
                    if customTTSText == "" or customTTSText:gsub("%s", "") == "" then
                        Library:Notification({Name = "Mic up TTS", Description = "Please enter text first!", Duration = 3, Icon = "97118059177470", IconColor = Color3.fromRGB(255, 120, 120)})
                        return
                    end
                    playTTS(customTTSText, customTTSText)
                end
            })
            
            local voices = {"masculine_america_01", "masculine_america_02", "feminine_america_01", "feminine_america_02", "masculine_britain", "feminine_britain", "masculine_australia", "feminine_australia"}
            local currentVoiceIndex = 2
            selectedVoice = voices[currentVoiceIndex]
            
            SoundboardSection:Button({
                Name = "voice: " .. selectedVoice,
                Callback = function()
                    currentVoiceIndex = currentVoiceIndex + 1
                    if currentVoiceIndex > #voices then
                        currentVoiceIndex = 1
                    end
                    selectedVoice = voices[currentVoiceIndex]
                    
                    if TTSToggle then
                        TTSToggle:FireServer("VoicePreset", selectedVoice)
                    end
                    
                    Library:Notification({Name = "Voice", Description = "Voice set to: " .. selectedVoice, Duration = 2, Icon = "116339777575852", IconColor = Color3.fromRGB(52, 255, 164)})
                end
            })
        end
    end
end

--[[ ==================== GAME CATEGORY ==================== ]]--
do
    local UtilitiesSubPage = Pages["Game"]:SubPage({Name = "utilities", Icon = "96491224522405", Columns = 2})
    local VisualsSubPage   = Pages["Game"]:SubPage({Name = "visuals",   Icon = "115907015044719", Columns = 2})
    local PlayersSubPage   = Pages["Game"]:SubPage({Name = "players",   Icon = "135799335731002", Columns = 1})

    --[[ UTILITIES SUB-PAGE ]]--
    do
        local StalkieSection = UtilitiesSubPage:Section({Name = "stalkie", Icon = "135215559087473", Side = 1})
        local OtherSection   = UtilitiesSubPage:Section({Name = "others",  Icon = "96491224522405",  Side = 2})

        StalkieSection:Button({
            Name = "ugc emotes",
            Callback = function()
                loadstring(game:HttpGet("https://raw.githubusercontent.com/Rootleak/roblox/refs/heads/main/main.lua"))()
            end
        })

        StalkieSection:Button({
            Name = "anim stealer",
            Callback = function()
                loadstring(game:HttpGet("https://raw.githubusercontent.com/Rootleak/roblox/refs/heads/main/anims.lua"))()
            end
        })

        OtherSection:Button({
            Name = "http spy",
            Callback = function()
                loadstring(game:HttpGet("https://raw.githubusercontent.com/Rootleak/roblox/refs/heads/main/spy.lua"))()
            end
        })

        local MapSection  = UtilitiesSubPage:Section({Name = "map",  Icon = "103174889897193", Side = 1})
        local TimeSection = UtilitiesSubPage:Section({Name = "time", Icon = "130045183204879", Side = 2})

        --[[ MAP SECTION ]]--
        local boothCurrentTitleInput = ""

        MapSection:Toggle({
            Name = "void walk",
            Flag = "Misc/VoidWalk",
            Default = false,
            Callback = function(Value)
                voidWalkEnabled = Value
                if Value then
                    workspace.FallenPartsDestroyHeight = 0/0
                    Library:Notification({Name = "Void Walk", Description = "Void walk enabled - you won't die from falling", Duration = 3, Icon = "116339777575852", IconColor = Color3.fromRGB(52, 255, 164)})
                else
                    workspace.FallenPartsDestroyHeight = -500
                end
            end
        })

        MapSection:Textbox({
            Name = "booth title",
            Flag = "Misc/BoothTitle",
            Placeholder = "type title and press add",
            Default = "",
            Callback = function(Value)
                boothCurrentTitleInput = Value or ""
            end
        })

        MapSection:Button({
            Name = "add title",
            Callback = function()
                local title = (boothCurrentTitleInput or ""):gsub("^%s+", ""):gsub("%s+$", "")
                if title ~= "" then
                    table.insert(boothTitles, title)
                    Library:Notification({Name = "Booth", Description = "Added title: " .. title .. " (" .. #boothTitles .. " total)", Duration = 2, Icon = "116339777575852", IconColor = Color3.fromRGB(52, 255, 164)})
                else
                    Library:Notification({Name = "Error", Description = "Please enter a title first", Duration = 2, Icon = "97118059177470", IconColor = Color3.fromRGB(255, 120, 120)})
                end
            end
        })

        MapSection:Button({
            Name = "remove titles",
            Callback = function()
                boothTitles = {}
                boothTitleIndex = 1
                Library:Notification({Name = "Booth", Description = "Cleared all booth titles", Duration = 2, Icon = "116339777575852", IconColor = Color3.fromRGB(52, 255, 164)})
            end
        })

        MapSection:Dropdown({
            Name = "booth material",
            Flag = "Misc/BoothMaterial",
            Items = {"Random", "All", "wood", "slate", "fabric", "plastic", "concrete"},
            Default = "Random",
            MaxSize = 150,
            Callback = function(Value)
                boothSelectedMaterial = Value
            end
        })

        local function getNextBoothTitle()
            if #boothTitles == 0 then return "STALKIE BOOTH" end
            if boothTitleIndex > #boothTitles then boothTitleIndex = 1 end
            local title = boothTitles[boothTitleIndex]
            boothTitleIndex = boothTitleIndex + 1
            return title
        end

        local function getBoothTexturePreset()
            if boothSelectedMaterial == "Random" or boothSelectedMaterial == "All" then
                return boothTextures[math.random(1, #boothTextures)]
            else
                return boothSelectedMaterial:lower()
            end
        end

        MapSection:Button({
            Name = "start booth spam",
            Callback = function()
                if boothSpamRunning then
                    boothSpamRunning = false
                    if boothSpamTask then task.cancel(boothSpamTask); boothSpamTask = nil end
                    Library:Notification({Name = "Booth", Description = "Stopped booth spam", Duration = 2, Icon = "116339777575852", IconColor = Color3.fromRGB(52, 255, 164)})
                    return
                end
                if not boothEvent then
                    Library:Notification({Name = "Error", Description = "event_booth_exit remote not found", Duration = 3, Icon = "97118059177470", IconColor = Color3.fromRGB(255, 120, 120)})
                    return
                end
                boothSpamRunning = true
                Library:Notification({Name = "Booth", Description = "Started booth spam", Duration = 2, Icon = "116339777575852", IconColor = Color3.fromRGB(52, 255, 164)})
                boothSpamTask = task.spawn(function()
                    while boothSpamRunning do
                        local texturePreset = getBoothTexturePreset()
                        local titleText = getNextBoothTitle()
                        local textureValues = {
                            ["01"] = {hue_number = math.random(), saturation_number = 0.6 + math.random() * 0.4, value_number = 0.8 + math.random() * 0.2},
                            ["02"] = {hue_number = math.random(), saturation_number = 0.6 + math.random() * 0.4, value_number = 0.8 + math.random() * 0.2},
                            title  = {hue_number = math.random(), saturation_number = 0.6 + math.random() * 0.4, value_number = 0.8 + math.random() * 0.2}
                        }
                        pcall(function()
                            boothEvent:FireServer({texture_preset = texturePreset, title_text = titleText, outfit_number = boothOutfitNumber, texture_values = textureValues})
                        end)
                        task.wait(1.05)
                    end
                end)
            end
        })

        --[[ TIME SECTION ]]--
        TimeSection:Toggle({
            Name = "custom time",
            Flag = "Misc/Time/CustomTime",
            Default = false,
            Callback = function(Value)
                CustomTime = Value
                if Value then
                    OldTime = Lighting.ClockTime
                    Lighting.ClockTime = SettedTime
                else
                    if OldTime then Lighting.ClockTime = OldTime end
                end
            end
        })

        TimeSection:Slider({
            Name = "time (hours)",
            Flag = "Misc/Time/Hours",
            Min = 0,
            Max = 24,
            Default = 14,
            Decimals = 0.5,
            Suffix = "h",
            Callback = function(Value)
                SettedTime = Value
                if CustomTime then Lighting.ClockTime = SettedTime end
            end
        })
    end

    --[[ ==================== VISUALS SUB-PAGE ==================== ]]--
    do
        local CameraSection = VisualsSubPage:Section({Name = "camera", Icon = "115907015044719", Side = 1})

        --[[ CAMERA SECTION ]]--
        local defaultFOV = Camera.FieldOfView

        CameraSection:Slider({
            Name = "fov",
            Flag = "Misc/Camera/FOV",
            Min = 1,
            Max = 120,
            Default = defaultFOV,
            Decimals = 1,
            Suffix = "°",
            Callback = function(Value)
                Camera.FieldOfView = Value
            end
        })

        local zoomActive = false
        local originalFOV = 70
        local zoomedFOV = 20
        local zoomConnections = {}

        CameraSection:Toggle({
            Name = "optifine zoom (C)",
            Flag = "Misc/Camera/OptifineZoom",
            Default = false,
            Callback = function(Value)
                zoomActive = Value
                if Value then
                    originalFOV = Camera.FieldOfView
                    for _, conn in pairs(zoomConnections) do if conn then conn:Disconnect() end end
                    zoomConnections = {}
                    zoomConnections[1] = UserInputService.InputBegan:Connect(function(input, gameProcessed)
                        if not gameProcessed and zoomActive and input.KeyCode == Enum.KeyCode.C then
                            TweenService:Create(Camera, TweenInfo.new(0.2), {FieldOfView = zoomedFOV}):Play()
                        end
                    end)
                    zoomConnections[2] = UserInputService.InputEnded:Connect(function(input)
                        if zoomActive and input.KeyCode == Enum.KeyCode.C then
                            TweenService:Create(Camera, TweenInfo.new(0.2), {FieldOfView = originalFOV}):Play()
                        end
                    end)
                else
                    for _, conn in pairs(zoomConnections) do if conn then conn:Disconnect() end end
                    zoomConnections = {}
                end
            end
        })

        local cinematicSmoothing = 5
        local lastCameraPos = Camera.CFrame.Position
        local CINEMATIC_STEP_NAME = "StalikieCinematicCam"

        CameraSection:Toggle({
            Name = "cinematic camera",
            Flag = "Misc/Camera/Cinematic",
            Default = false,
            Callback = function(Value)
                if Value then
                    lastCameraPos = Camera.CFrame.Position
                    RunService:BindToRenderStep(CINEMATIC_STEP_NAME, Enum.RenderPriority.Camera.Value, function(dt)
                        local cf = Camera.CFrame
                        local alpha = math.clamp(cinematicSmoothing * dt, 0, 1)
                        lastCameraPos = lastCameraPos:Lerp(cf.Position, alpha)
                        Camera.CFrame = CFrame.new(lastCameraPos, lastCameraPos + cf.LookVector)
                    end)
                else
                    RunService:UnbindFromRenderStep(CINEMATIC_STEP_NAME)
                end
            end
        })

        --[[ ESP / PLAYERS SECTION ]]--
        local PlayersSection = VisualsSubPage:Section({Name = "players", Icon = "135799335731002", Side = 2})

        ESPPreview:SetVisibility(false)
        ESPPreview:Set("BoxHolder", "BackgroundTransparency", 1)
        ESPPreview:Set("BoxHolder", "Visible", false)
        ESPPreview:Set("Corners", "Visible", false)
        ESPPreview:Set("WeaponText", "Visible", false)
        ESPPreview:Set("Distance", "Visible", false)
        ESPPreview:Set("Name", "Visible", false)
        ESPPreview:Set("HealthBar", "Visible", false)
        ESPPreview:Set("HealthBarText", "Visible", false)
        ESPPreview:Set("HealthBarText", "Position", UDim2.new(0, -5, 0, 0))

        PlayersSection:Toggle({
            Name = "Enabled",
            Flag = "Visuals/ESP/MasterSwitch",
            Default = false,
            Callback = function(Value)
                Options["Enabled"] = Value
                MiscOptions["Enabled"] = Value
                ESPPreview:SetVisibility(Value)
            end
        })

        local BoxesToggle = PlayersSection:Toggle({
            Name = "Boxes",
            Flag = "Visuals/ESP/Boxes",
            Default = false,
            Callback = function(Value)
                Options["Boxes"] = Value
                MiscOptions["Boxes"] = Value
                if MiscOptions["BoxType"] == "Corner" then
                    ESPPreview:Set("BoxHolder", "Visible", false)
                    ESPPreview:Set("Corners", "Visible", Value)
                else
                    ESPPreview:Set("BoxHolder", "Visible", Value)
                    ESPPreview:Set("Corners", "Visible", false)
                end
            end
        })

        BoxesToggle:Colorpicker({
            Name = "Gradient 1",
            Flag = "Visuals/ESP/Boxes/Gradient1",
            Default = MiscOptions["Box Gradient 1"].Color,
            Alpha = 0,
            Callback = function(Value)
                Options["Box Gradient 1"] = {Color = Value, Transparency = 0}
                MiscOptions["Box Gradient 1"] = {Color = Value, Transparency = 0}
                ESPPreview:Set("BoxGradient", "Color", ColorSequence.new{ColorSequenceKeypoint.new(0, Value), ColorSequenceKeypoint.new(1, MiscOptions["Box Gradient 2"].Color)})
                if MiscOptions["BoxType"] == "Corner" then
                    for _, d in ESPPreview.Items.Corners.Instance:GetDescendants() do
                        if d:IsA("UIGradient") then
                            d.Color = ColorSequence.new{ColorSequenceKeypoint.new(0, Value), ColorSequenceKeypoint.new(1, MiscOptions["Box Gradient 2"].Color)}
                        end
                    end
                end
            end
        })

        BoxesToggle:Colorpicker({
            Name = "Gradient 2",
            Flag = "Visuals/ESP/Boxes/Gradient2",
            Default = MiscOptions["Box Gradient 2"].Color,
            Alpha = 0,
            Callback = function(Value)
                Options["Box Gradient 2"] = {Color = Value, Transparency = 0}
                MiscOptions["Box Gradient 2"] = {Color = Value, Transparency = 0}
                ESPPreview:Set("BoxGradient", "Color", ColorSequence.new{ColorSequenceKeypoint.new(0, MiscOptions["Box Gradient 1"].Color), ColorSequenceKeypoint.new(1, Value)})
                if MiscOptions["BoxType"] == "Corner" then
                    for _, d in ESPPreview.Items.Corners.Instance:GetDescendants() do
                        if d:IsA("UIGradient") then
                            d.Color = ColorSequence.new{ColorSequenceKeypoint.new(0, MiscOptions["Box Gradient 1"].Color), ColorSequenceKeypoint.new(1, Value)}
                        end
                    end
                end
            end
        })

        PlayersSection:Dropdown({
            Name = "Box Type",
            Flag = "Visuals/ESP/BoxType",
            Items = {"Normal", "Corner"},
            Default = "Normal",
            MaxSize = 100,
            Callback = function(Value)
                Options["BoxType"] = Value
                MiscOptions["BoxType"] = Value
                if not MiscOptions["Boxes"] then return end
                if Value == "Corner" then
                    ESPPreview:Set("BoxHolder", "Visible", false)
                    ESPPreview:Set("Corners", "Visible", true)
                else
                    ESPPreview:Set("BoxHolder", "Visible", true)
                    ESPPreview:Set("Corners", "Visible", false)
                end
            end
        })

        PlayersSection:Slider({
            Name = "Box Gradient Rotation",
            Flag = "Visuals/ESP/BoxGradientRotation",
            Default = 90,
            Suffix = "°",
            Min = -180,
            Max = 180,
            Decimals = 1,
            Callback = function(Value)
                Options["Box Gradient Rotation"] = Value
                MiscOptions["Box Gradient Rotation"] = Value
                ESPPreview:Set("BoxGradient", "Rotation", Value)
            end
        })

        local BoxesFilledToggle = PlayersSection:Toggle({
            Name = "Box Fill",
            Flag = "Visuals/ESP/BoxesFilled",
            Default = false,
            Callback = function(Value)
                Options["Box Fill"] = Value
                MiscOptions["Box Fill"] = Value
                ESPPreview:Set("BoxHolder", "BackgroundTransparency", Value and 0 or 1)
            end
        })

        BoxesFilledToggle:Colorpicker({
            Name = "Fill Gradient 1",
            Flag = "Visuals/ESP/Boxes/FilledGradient1",
            Default = MiscOptions["Box Fill 1"].Color,
            Alpha = 0.9,
            Callback = function(Value, Alpha)
                Options["Box Fill 1"] = {Color = Value, Transparency = Alpha}
                MiscOptions["Box Fill 1"] = {Color = Value, Transparency = Alpha}
                local PathC = ESPPreview.Items.CornersGradient.Instance
                PathC.Transparency = NumberSequence.new{NumberSequenceKeypoint.new(0, 1 - Alpha), PathC.Transparency.Keypoints[2]}
                PathC.Color = ColorSequence.new{ColorSequenceKeypoint.new(0, Value), PathC.Color.Keypoints[2]}
                local PathB = ESPPreview.Items.BoxHolderGradient.Instance
                PathB.Transparency = NumberSequence.new{PathB.Transparency.Keypoints[1], NumberSequenceKeypoint.new(1, 1 - Alpha)}
                PathB.Color = ColorSequence.new{PathB.Color.Keypoints[1], ColorSequenceKeypoint.new(1, Value)}
            end
        })

        BoxesFilledToggle:Colorpicker({
            Name = "Fill Gradient 2",
            Flag = "Visuals/ESP/Boxes/FilledGradient2",
            Default = MiscOptions["Box Fill 2"].Color,
            Alpha = 0.9,
            Callback = function(Value, Alpha)
                Options["Box Fill 2"] = {Color = Value, Transparency = Alpha}
                MiscOptions["Box Fill 2"] = {Color = Value, Transparency = Alpha}
                local PathC = ESPPreview.Items.CornersGradient.Instance
                PathC.Transparency = NumberSequence.new{PathC.Transparency.Keypoints[1], NumberSequenceKeypoint.new(1, Alpha)}
                PathC.Color = ColorSequence.new{PathC.Color.Keypoints[1], ColorSequenceKeypoint.new(1, Value)}
                local PathB = ESPPreview.Items.BoxHolderGradient.Instance
                PathB.Transparency = NumberSequence.new{NumberSequenceKeypoint.new(0, Alpha), PathB.Transparency.Keypoints[2]}
                PathB.Color = ColorSequence.new{ColorSequenceKeypoint.new(0, Value), PathB.Color.Keypoints[2]}
            end
        })

        PlayersSection:Slider({
            Name = "Box Fill Rotation",
            Flag = "Visuals/ESP/BoxFillGradientRotation",
            Default = 0,
            Suffix = "°",
            Min = -180,
            Max = 180,
            Decimals = 1,
            Callback = function(Value)
                Options["Box Fill Rotation"] = Value
                MiscOptions["Box Fill Rotation"] = Value
                ESPPreview:Set("BoxHolderGradient", "Rotation", Value)
                ESPPreview:Set("CornersGradient", "Rotation", Value)
            end
        })

        local HealthBarToggle = PlayersSection:Toggle({
            Name = "Healthbar",
            Flag = "Visuals/ESP/Healthbar",
            Default = false,
            Callback = function(Value)
                Options["Healthbar"] = Value
                MiscOptions["Healthbar"] = Value
                ESPPreview:Set("HealthBar", "Visible", Value)
            end
        })

        HealthBarToggle:Colorpicker({
            Name = "Low",
            Flag = "Visuals/ESP/HealthbarLow",
            Default = MiscOptions["Healthbar_Low"].Color,
            Alpha = 0,
            Callback = function(Value)
                Options["Healthbar_Low"] = {Color = Value, Transparency = 0}
                MiscOptions["Healthbar_Low"] = {Color = Value, Transparency = 0}
                ESPPreview:Set("BarGradient", "Color", ColorSequence.new{ColorSequenceKeypoint.new(0, Value), ColorSequenceKeypoint.new(0.5, MiscOptions["Healthbar_Medium"].Color), ColorSequenceKeypoint.new(1, MiscOptions["Healthbar_High"].Color)})
            end
        })

        HealthBarToggle:Colorpicker({
            Name = "Medium",
            Flag = "Visuals/ESP/HealthbarMedium",
            Default = MiscOptions["Healthbar_Medium"].Color,
            Alpha = 0,
            Callback = function(Value)
                Options["Healthbar_Medium"] = {Color = Value, Transparency = 0}
                MiscOptions["Healthbar_Medium"] = {Color = Value, Transparency = 0}
                ESPPreview:Set("BarGradient", "Color", ColorSequence.new{ColorSequenceKeypoint.new(0, MiscOptions["Healthbar_Low"].Color), ColorSequenceKeypoint.new(0.5, Value), ColorSequenceKeypoint.new(1, MiscOptions["Healthbar_High"].Color)})
            end
        })

        HealthBarToggle:Colorpicker({
            Name = "High",
            Flag = "Visuals/ESP/HealthbarHigh",
            Default = MiscOptions["Healthbar_High"].Color,
            Alpha = 0,
            Callback = function(Value)
                Options["Healthbar_High"] = {Color = Value, Transparency = 0}
                MiscOptions["Healthbar_High"] = {Color = Value, Transparency = 0}
                ESPPreview:Set("BarGradient", "Color", ColorSequence.new{ColorSequenceKeypoint.new(0, MiscOptions["Healthbar_Low"].Color), ColorSequenceKeypoint.new(0.5, MiscOptions["Healthbar_Medium"].Color), ColorSequenceKeypoint.new(1, Value)})
            end
        })

        PlayersSection:Dropdown({
            Name = "Healthbar Side",
            Flag = "Visuals/ESP/HealthbarSide",
            MaxSize = 145,
            Default = "Left",
            Items = {"Left", "Bottom", "Top", "Right"},
            Callback = function(Value)
                Value = Value or "Left"
                Options["Healthbar_Position"] = Value
                MiscOptions["Healthbar_Position"] = Value
                ESPPreview:Set("HealthBar", "Parent", ESPPreview.Items[Value].Instance or ESPPreview.Items.Left.Instance)
                if Value == "Right" then
                    ESPPreview:Set("HealthBarText", "AnchorPoint", Vector2.new(0, 0))
                    ESPPreview:Set("HealthBarText", "Position", UDim2.new(1, 5, 0, 0))
                else
                    ESPPreview:Set("HealthBarText", "AnchorPoint", Vector2.new(1, 0))
                    ESPPreview:Set("HealthBarText", "Position", UDim2.new(0, -5, 0, 0))
                end
                if Value == "Top" or Value == "Bottom" then
                    ESPPreview:Set("HealthBarText", "Visible", false)
                end
            end
        })

        PlayersSection:Toggle({
            Name = "Healthbar Tween",
            Flag = "Visuals/ESP/HealthbarTween",
            Default = false,
            Callback = function(Value)
                Options["Healthbar_Tween"] = Value
                MiscOptions["Healthbar_Tween"] = Value
            end
        })

        PlayersSection:Dropdown({
            Name = "Tween Style",
            Flag = "Visuals/ESP/HealthbarTweenStyle",
            Default = "Circular",
            Items = {"Linear", "Sine", "Quad", "Cubic", "Quart", "Quint", "Exponential", "Circular", "Back", "Elastic", "Bounce"},
            MaxSize = 150,
            Callback = function(Value)
                Options["Healthbar_EasingStyle"] = Value
                MiscOptions["Healthbar_EasingStyle"] = Value
            end
        })

        PlayersSection:Dropdown({
            Name = "Tween Direction",
            Flag = "Visuals/ESP/HealthbarTweenDirection",
            MaxSize = 55,
            Default = "InOut",
            Items = {"In", "Out", "InOut"},
            Callback = function(Value)
                Options["Healthbar_EasingDirection"] = Value
                MiscOptions["Healthbar_EasingDirection"] = Value
            end
        })

        PlayersSection:Slider({
            Name = "Tween Speed",
            Default = 1,
            Max = 10,
            Min = 0,
            Decimals = 0.01,
            Suffix = "s",
            Flag = "Visuals/ESP/HealthbarTweenSpeed",
            Callback = function(Value)
                Options["Healthbar_Easing_Speed"] = Value
                MiscOptions["Healthbar_Easing_Speed"] = Value
            end
        })

        PlayersSection:Toggle({
            Name = "Healthbar Number",
            Flag = "Visuals/ESP/HealthbarNumber",
            Default = false,
            Callback = function(Value)
                Options["Healthbar_Number"] = Value
                MiscOptions["Healthbar_Number"] = Value
                ESPPreview:Set("HealthBarText", "Visible", Value)
            end
        })

        PlayersSection:Slider({
            Name = "Healthbar Text Size",
            Flag = "Visuals/ESP/HealthbarTextSize",
            Max = 14,
            Min = 1,
            Default = 11,
            Suffix = "px",
            Decimals = 1,
            Callback = function(Value)
                Options["Healthbar_Text_Size"] = Value
                MiscOptions["Healthbar_Text_Size"] = Value
                ESPPreview:Set("HealthBarText", "TextSize", Value)
            end
        })

        PlayersSection:Slider({
            Name = "Healthbar Thickness",
            Flag = "Visuals/ESP/HealthbarThickness",
            Max = 10,
            Min = 1,
            Default = 3,
            Suffix = "px",
            Decimals = 1,
            Callback = function(Value)
                Options["Healthbar_Thickness"] = Value
                MiscOptions["Healthbar_Thickness"] = Value
                ESPPreview:Set("HealthBar", "Size", UDim2.new(0, Value, 1, 0))
            end
        })

        PlayersSection:Dropdown({
            Name = "Healthbar Font",
            Items = {"ProggyClean", "Tahoma", "Verdana", "SmallestPixel", "ProggyTiny", "Minecraftia", "Tahoma Bold"},
            MaxSize = 200,
            Flag = "Visuals/ESP/HealthbarFont",
            Default = "Verdana",
            Multi = false,
            Callback = function(Value)
                Value = Value or "Verdana"
                Options["Healthbar_Font"] = Value
                MiscOptions["Healthbar_Font"] = Value
                ESPPreview:Set("HealthBarText", "FontFace", ESPFonts[Value])
            end
        })

        PlayersSection:Toggle({
            Name = "Name",
            Flag = "Visuals/ESP/NameText",
            Default = false,
            Callback = function(Value)
                Options["Name_Text"] = Value
                MiscOptions["Name_Text"] = Value
                ESPPreview:Set("Name", "Visible", Value)
            end
        }):Colorpicker({
            Name = "Name Color",
            Flag = "Visuals/ESP/NameTextColor",
            Default = Color3.fromRGB(255, 255, 255),
            Alpha = 0,
            Callback = function(Value)
                Options["Name_Text_Color"] = {Color = Value}
                MiscOptions["Name_Text_Color"] = {Color = Value}
                ESPPreview:Set("Name", "TextColor3", Value)
            end
        })

        PlayersSection:Dropdown({
            Name = "Name Font",
            Items = {"ProggyClean", "Tahoma", "Verdana", "SmallestPixel", "ProggyTiny", "Minecraftia", "Tahoma Bold"},
            MaxSize = 200,
            Flag = "Visuals/ESP/NameFont",
            Default = "Verdana",
            Multi = false,
            Callback = function(Value)
                Value = Value or "Verdana"
                Options["Name_Text_Font"] = Value
                MiscOptions["Name_Text_Font"] = Value
                ESPPreview:Set("Name", "FontFace", ESPFonts[Value])
            end
        })

        PlayersSection:Slider({
            Name = "Name Text Size",
            Flag = "Visuals/ESP/NameTextSize",
            Max = 14,
            Min = 1,
            Default = 11,
            Suffix = "px",
            Decimals = 1,
            Callback = function(Value)
                Options["Name_Text_Size"] = Value
                MiscOptions["Name_Text_Size"] = Value
                ESPPreview:Set("Name", "TextSize", Value)
            end
        })

        PlayersSection:Toggle({
            Name = "Distance",
            Flag = "Visuals/ESP/DistanceText",
            Default = false,
            Callback = function(Value)
                Options["Distance_Text"] = Value
                MiscOptions["Distance_Text"] = Value
                ESPPreview:Set("Distance", "Visible", Value)
            end
        }):Colorpicker({
            Name = "Distance Color",
            Flag = "Visuals/ESP/DistanceTextColor",
            Default = Color3.fromRGB(255, 255, 255),
            Alpha = 0,
            Callback = function(Value)
                Options["Distance_Text_Color"] = {Color = Value}
                MiscOptions["Distance_Text_Color"] = {Color = Value}
                ESPPreview:Set("Distance", "TextColor3", Value)
            end
        })

        PlayersSection:Dropdown({
            Name = "Distance Font",
            Items = {"ProggyClean", "Tahoma", "Verdana", "SmallestPixel", "ProggyTiny", "Minecraftia", "Tahoma Bold"},
            MaxSize = 200,
            Flag = "Visuals/ESP/DistanceFont",
            Default = "Verdana",
            Multi = false,
            Callback = function(Value)
                Value = Value or "Verdana"
                Options["Distance_Text_Font"] = Value
                MiscOptions["Distance_Text_Font"] = Value
                ESPPreview:Set("Distance", "FontFace", ESPFonts[Value])
            end
        })

        PlayersSection:Slider({
            Name = "Distance Text Size",
            Flag = "Visuals/ESP/DistanceTextSize",
            Max = 14,
            Min = 1,
            Default = 11,
            Suffix = "px",
            Decimals = 1,
            Callback = function(Value)
                Options["Distance_Text_Size"] = Value
                MiscOptions["Distance_Text_Size"] = Value
                ESPPreview:Set("Distance", "TextSize", Value)
            end
        })

        PlayersSection:Dropdown({
            Name = "Distance Side",
            Items = {"Top", "Bottom", "Left", "Right"},
            MaxSize = 200,
            Flag = "Visuals/ESP/DistanceSide",
            Default = "Bottom",
            Multi = false,
            Callback = function(Value)
                Value = Value or "Bottom"
                Options["Distance_Text_Position"] = Value
                MiscOptions["Distance_Text_Position"] = Value
                ESPPreview:Set("Distance", "Parent", ESPPreview.Items[Value].Instance)
            end
        })
    end

    --[[ PLAYERS SUB-PAGE — Leakcheck integrated into Library Playerlist ]]--
    do
        local Players        = game:GetService("Players")
        local playerLeakData = {}   -- [name] = {found=N, leaks=[...]} | {found=0} | nil=scanning
        local leakPageIndex  = 1
        local plItems        = nil  -- set after PlayerPage is created; safe upvalue for Callback
        local scanQueue      = {}
        local scanWorker     = false

        -- ── Leak labels show/hide helpers ───────────────────────────────────
        local LEAK_LABEL_KEYS = {"LeakSourceLabel","LeakField1","LeakField2","LeakField3","LeakField4","LeakPrevBtn","LeakPageLabel","LeakNextBtn"}
        local function hideLeakLabels()
            if not plItems then return end
            for _, k in ipairs(LEAK_LABEL_KEYS) do
                if plItems[k] then plItems[k].Instance.Visible = false end
            end
        end

        -- ── LeakPanel population ─────────────────────────────────────────────
        local function populateLeakPanel(leaks, index)
            if not plItems then return end
            if not leaks or #leaks == 0 then hideLeakLabels() return end
            local leak = leaks[index]
            if not leak then hideLeakLabels() return end

            local dateStr = (leak.date and leak.date ~= "") and leak.date or "Unknown date"
            plItems["LeakSourceLabel"].Instance.Text    = "[" .. (leak.source or "?") .. "] " .. dateStr
            plItems["LeakSourceLabel"].Instance.Visible = true

            -- filter out username — already shown on the left side
            local displayFields = {}
            for _, f in ipairs(leak.fields) do
                if f.key:lower() ~= "username" then
                    table.insert(displayFields, f)
                end
            end

            for i = 1, 4 do
                local f = displayFields[i]
                local lbl = plItems["LeakField" .. i]
                if lbl then
                    if f then
                        local k = f.key:sub(1,1):upper() .. f.key:sub(2)
                        lbl.Instance.Text    = k .. ": " .. f.value
                        lbl.Instance.Visible = true
                    else
                        lbl.Instance.Text    = ""
                        lbl.Instance.Visible = false
                    end
                end
            end

            local total = #leaks
            plItems["LeakPageLabel"].Instance.Text    = index .. "/" .. total
            plItems["LeakPageLabel"].Instance.Visible = total > 1
            plItems["LeakPrevBtn"].Instance.Visible   = total > 1
            plItems["LeakNextBtn"].Instance.Visible   = total > 1
            if total > 1 then
                plItems["LeakPrevBtn"].Instance.BackgroundTransparency = index == 1      and 0.6 or 0.2
                plItems["LeakNextBtn"].Instance.BackgroundTransparency = index == total  and 0.6 or 0.2
            end
        end

        -- ── Info panel refresh (Leaks label + Details btn) ──────────────────
        local function refreshInfoPanel(player)
            if not plItems then return end
            local data = player and playerLeakData[player.Name]
            local ll   = plItems["PlayerLeaksLabel"]
            local db   = plItems["PlayerDetailsBtn"]
            if not ll or not db then return end
            if not data then
                ll.Instance.Text    = 'Leaks: <font color="rgb(150,150,150)">scanning...</font>'
                db.Instance.Visible = false
            elseif data.status == "error" then
                ll.Instance.Text    = 'Leaks: <font color="rgb(255,200,0)">error</font>'
                db.Instance.Visible = false
            elseif data.status == "leaks" or (data.found and data.found > 0) then
                ll.Instance.Text    = 'Leaks: <font color="rgb(255,60,60)">' .. data.found .. ' found</font>'
                db.Instance.Visible = true
            else
                ll.Instance.Text    = 'Leaks: <font color="rgb(0,210,100)">clean</font>'
                db.Instance.Visible = false
            end
            local tl = plItems["PlayerTeamLabel"]
            if tl and player then
                local tc      = player.Team and player.Team.TeamColor.Color or Color3.new(1,1,1)
                local tcStr   = string.format("rgb(%d,%d,%d)", math.round(tc.R*255), math.round(tc.G*255), math.round(tc.B*255))
                local tName   = player.Team and player.Team.Name or "None"
                tl.Instance.Text = 'Team: <font color="' .. tcStr .. '">' .. tName .. '</font>'
            end
        end

        -- ── Sequential scan worker ───────────────────────────────────────────
        local function startWorker()
            if scanWorker then return end
            scanWorker = true
            task.spawn(function()
                while #scanQueue > 0 do
                    local entry = table.remove(scanQueue, 1)
                    local pd, player = entry.pd, entry.player
                    if not player or not player.Parent then continue end

                    pd.PlayerStatus.Instance.TextColor3 = Color3.fromRGB(150, 150, 150)

                    local result    = nil
                    local attempts  = 0
                    local MAX_RETRIES = 3
                    local animating = true
                    task.spawn(function()
                        local dots = 0
                        while animating do
                            dots = dots % 3 + 1
                            if pd.PlayerStatus and pd.PlayerStatus.Instance then
                                pd.PlayerStatus.Instance.Text = "scanning" .. string.rep(".", dots)
                            end
                            task.wait(0.4)
                        end
                    end)

                    while attempts < MAX_RETRIES do
                        if not player or not player.Parent then break end
                        local ok, r = pcall(queryLeakCheck, player.Name)
                        if ok and r then
                            if r.status ~= "error" then
                                result = r
                                break
                            elseif r.errorType == "rate_limit" then
                                result = r
                                attempts += 1
                                task.wait(3)
                            else
                                result = r
                                attempts += 1
                                task.wait(1.5)
                            end
                        else
                            attempts += 1
                            task.wait(1.5)
                        end
                    end

                    animating = false
                    if not player or not player.Parent then
                        task.wait(0.5) continue
                    end

                    if result and result.status == "leaks" then
                        playerLeakData[player.Name] = result
                        pd.PlayerStatus.Instance.Text       = result.found .. " leak" .. (result.found == 1 and "" or "s")
                        pd.PlayerStatus.Instance.TextColor3 = Color3.fromRGB(255, 60, 60)
                    elseif result and result.status == "no_leaks" then
                        playerLeakData[player.Name] = {status = "no_leaks", found = 0, leaks = {}}
                        pd.PlayerStatus.Instance.Text       = "clean"
                        pd.PlayerStatus.Instance.TextColor3 = Color3.fromRGB(0, 210, 100)
                    else
                        playerLeakData[player.Name] = {status = "error", found = 0, leaks = {}}
                        pd.PlayerStatus.Instance.Text       = "error"
                        pd.PlayerStatus.Instance.TextColor3 = Color3.fromRGB(255, 200, 0)
                    end

                    -- live-update info panel if this player is selected
                    if PlayerPage and PlayerPage.Player == player then
                        refreshInfoPanel(player)
                    end

                    task.wait(0.5)  -- cooldown between scans
                end
                scanWorker = false
            end)
        end

        local function queueScan(pd, player)
            if player == Players.LocalPlayer then
                pd.PlayerStatus.Instance.Text       = "You"
                pd.PlayerStatus.Instance.TextColor3 = Color3.fromRGB(196, 231, 255)
                return
            end
            table.insert(scanQueue, {pd = pd, player = player})
            startWorker()
        end

        -- ── Create Playerlist ────────────────────────────────────────────────
        local PlayerPage = PlayersSubPage:Playerlist({
            Callback = function(Player)
                if not Player or not plItems then return end
                refreshInfoPanel(Player)
                leakPageIndex = 1
                -- hide leak labels on player switch
                hideLeakLabels()
                if plItems["PlayerDetailsBtn"] then
                    plItems["PlayerDetailsBtn"].Instance.Text = "+"
                end
            end
        })

        plItems = PlayerPage and PlayerPage.Items

        -- ── Wire Details / Prev / Next buttons ───────────────────────────────
        if plItems and plItems["PlayerDetailsBtn"] then
            plItems["PlayerDetailsBtn"].Instance.MouseButton1Click:Connect(function()
                local isOpen = plItems["LeakSourceLabel"] and plItems["LeakSourceLabel"].Instance.Visible
                local data   = PlayerPage.Player and playerLeakData[PlayerPage.Player.Name]
                if not isOpen and data and data.found > 0 then
                    leakPageIndex = 1
                    populateLeakPanel(data.leaks, leakPageIndex)
                    plItems["PlayerDetailsBtn"].Instance.Text = "-"
                else
                    hideLeakLabels()
                    plItems["PlayerDetailsBtn"].Instance.Text = "+"
                end
            end)

            if plItems["LeakPrevBtn"] then
                plItems["LeakPrevBtn"].Instance.MouseButton1Click:Connect(function()
                    local data = PlayerPage.Player and playerLeakData[PlayerPage.Player.Name]
                    if not data or not data.leaks then return end
                    leakPageIndex = math.max(1, leakPageIndex - 1)
                    populateLeakPanel(data.leaks, leakPageIndex)
                end)
            end
            if plItems["LeakNextBtn"] then
                plItems["LeakNextBtn"].Instance.MouseButton1Click:Connect(function()
                    local data = PlayerPage.Player and playerLeakData[PlayerPage.Player.Name]
                    if not data or not data.leaks then return end
                    leakPageIndex = math.min(#data.leaks, leakPageIndex + 1)
                    populateLeakPanel(data.leaks, leakPageIndex)
                end)
            end
        end

        -- ── Queue initial scans (sequential, top-to-bottom order) ────────────
        for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
            local pd = PlayerPage.Players[player.Name]
            if pd then queueScan(pd, player) end
        end

        Players.PlayerAdded:Connect(function(player)
            task.wait(0.5)
            local pd = PlayerPage.Players[player.Name]
            if pd then queueScan(pd, player) end
        end)
    end
end

local ConfigSelected
local ConfigsDropdown
local ThemeSelected
local ThemesDropdown

--[[ ==================== SETTINGS CATEGORY ==================== ]]--
do
    -- Create SubPages under Settings
    local Subpages = {
        ["Configs"]        = Pages["Settings"]:SubPage({Name = "configs",        Icon = "96491224522405",  Columns = 2}),
        ["Theming"]        = Pages["Settings"]:SubPage({Name = "theming",        Icon = "103863157706913", Columns = 2}),
        ["Configuration"]  = Pages["Settings"]:SubPage({Name = "configuration",  Icon = "137300573942266", Columns = 2}),
        ["About"]          = Pages["Settings"]:SubPage({Name = "about",          Icon = "103174889897193", Columns = 2})
    }
    
    --[[ ==================== CONFIGS SUB-PAGE ==================== ]]--
    do
        local ConfigsSection  = Subpages["Configs"]:Section({Name = "profiles",  Icon = "96491224522405",  Side = 1})
        local AutoloadSection = Subpages["Configs"]:Section({Name = "autoload",  Icon = "137623872962804", Side = 2})

        local ConfigName

        ConfigsDropdown = ConfigsSection:Dropdown({
            Name     = "configs",
            Flag     = "ConfigsList",
            Items    = {},
            Multi    = false,
            Callback = function(Value)
                ConfigSelected = Value
            end
        })

        ConfigsSection:Textbox({
            Name        = "config name",
            Default     = "",
            Flag        = "ConfigName",
            Placeholder = "enter text",
            Callback    = function(Value)
                ConfigName = Value
            end
        })

        ConfigsSection:Button({
            Name     = "create",
            Callback = function()
                if ConfigName and ConfigName ~= "" then
                    writefile(Library.Folders.Configs .. "/" .. ConfigName .. ".json", Library:GetConfig())
                    Library:RefreshConfigsList(ConfigsDropdown)
                    Library:Notification({Name = "Created", Description = "Created config: " .. ConfigName .. ".json", Duration = 5, Icon = "116339777575852", IconColor = Color3.fromRGB(52, 255, 164)})
                    ConfigName = ""
                    Library.SetFlags["ConfigName"]("")
                else
                    Library:Notification({Name = "Error!", Description = "Enter a config name first", Duration = 3, Icon = "97118059177470", IconColor = Color3.fromRGB(255, 120, 120)})
                end
            end
        })

        ConfigsSection:Button({
            Name     = "save",
            Callback = function()
                if ConfigSelected then
                    writefile(Library.Folders.Configs .. "/" .. ConfigSelected, Library:GetConfig())
                    Library:Notification({Name = "Saved", Description = "Saved config: " .. ConfigSelected, Duration = 5, Icon = "116339777575852", IconColor = Color3.fromRGB(52, 255, 164)})
                end
            end
        })

        ConfigsSection:Button({
            Name     = "load",
            Callback = function()
                if ConfigSelected then
                    local Success, Result = Library:LoadConfig(readfile(Library.Folders.Configs .. "/" .. ConfigSelected))
                    if Success then
                        Library:Notification({Name = "Success", Description = "Loaded config: " .. ConfigSelected, Duration = 5, Icon = "116339777575852", IconColor = Color3.fromRGB(52, 255, 164)})
                        task.wait(0.3)
                        Library:Thread(function()
                            for Index, Value in Library.Theme do
                                Library.Theme[Index] = Library.Flags["ColorpickerTheme" .. Index].Color
                                Library:ChangeTheme(Index, Library.Flags["ColorpickerTheme" .. Index].Color)
                            end
                        end)
                    else
                        Library:Notification({Name = "Error!", Description = "Failed to load config", Duration = 5, Icon = "97118059177470", IconColor = Color3.fromRGB(255, 120, 120)})
                    end
                end
            end
        })

        ConfigsSection:Button({
            Name     = "delete",
            Callback = function()
                if ConfigSelected then
                    local deleted = ConfigSelected
                    ConfigSelected = nil
                    local autoName = readfile(Library.Folders.Directory .. "/AutoLoadConfigName.txt")
                    if autoName == deleted then
                        writefile(Library.Folders.Directory .. "/AutoLoadConfig (do not modify this).json", "")
                        writefile(Library.Folders.Directory .. "/AutoLoadConfigName.txt", "")
                    end
                    Library:DeleteConfig(deleted)
                    Library:RefreshConfigsList(ConfigsDropdown)
                    ConfigsDropdown:Set(nil)
                else
                    Library:Notification({Name = "Error!", Description = "Select a config first", Duration = 3, Icon = "97118059177470", IconColor = Color3.fromRGB(255, 120, 120)})
                end
            end
        })

        ConfigsSection:Button({
            Name     = "refresh list",
            Callback = function()
                Library:RefreshConfigsList(ConfigsDropdown)
            end
        })

        AutoloadSection:Button({
            Name     = "set selected as autoload",
            Callback = function()
                if ConfigSelected then
                    writefile(Library.Folders.Directory .. "/AutoLoadConfig (do not modify this).json", readfile(Library.Folders.Configs .. "/" .. ConfigSelected))
                    writefile(Library.Folders.Directory .. "/AutoLoadConfigName.txt", ConfigSelected)
                    Library:Notification({Name = "Autoload Set", Description = ConfigSelected .. " will autoload on next execution", Duration = 5, Icon = "116339777575852", IconColor = Color3.fromRGB(52, 255, 164)})
                else
                    Library:Notification({Name = "Error!", Description = "Select a config first", Duration = 3, Icon = "97118059177470", IconColor = Color3.fromRGB(255, 120, 120)})
                end
            end
        })

        AutoloadSection:Button({
            Name     = "set current as autoload",
            Callback = function()
                writefile(Library.Folders.Directory .. "/AutoLoadConfig (do not modify this).json", Library:GetConfig())
                writefile(Library.Folders.Directory .. "/AutoLoadConfigName.txt", ConfigSelected or "")
                Library:Notification({Name = "Autoload Set", Description = "Current settings will autoload on next execution", Duration = 5, Icon = "116339777575852", IconColor = Color3.fromRGB(52, 255, 164)})
            end
        })

        AutoloadSection:Button({
            Name     = "remove autoload config",
            Callback = function()
                writefile(Library.Folders.Directory .. "/AutoLoadConfig (do not modify this).json", "")
                writefile(Library.Folders.Directory .. "/AutoLoadConfigName.txt", "")
                Library:Notification({Name = "Autoload Removed", Description = "Config autoload has been cleared", Duration = 5, Icon = "116339777575852", IconColor = Color3.fromRGB(52, 255, 164)})
            end
        })

        Library:RefreshConfigsList(ConfigsDropdown)
    end

    --[[ ==================== ABOUT SUB-PAGE ==================== ]]--
    do
        -- Left Side Sections
        local InfoSection = Subpages["About"]:Section({Name = "script information", Icon = "103174889897193", Side = 1})
        local GamesSection = Subpages["About"]:Section({Name = "supported games", Icon = "109463522861706", Side = 1})
        
        -- Right Side Sections
        local SuggestionsSection = Subpages["About"]:Section({Name = "suggestions", Icon = "136623465713368", Side = 2})

    --[[ INFO SECTION ]]--
    InfoSection:Label("Made by rootleak", "Left")
    InfoSection:Label("Version: " .. VERSION, "Left")
    InfoSection:Label("Stalkie 2.0 - Full Revamp", "Left")

    --[[ GAMES SECTION ]]--
    if currentGame then
        GamesSection:Label("✓ " .. currentGame.name .. " (Current)", "Left")
    else
        GamesSection:Label("✗ Current game not supported", "Left")
    end

    -- Add other games with teleport buttons
    for gameName, gameInfo in pairs(UNIQUE_GAMES) do
        if currentGame == nil or gameName ~= currentGame.name then
            if gameInfo.canTeleport then
                local targetPlaceId = gameInfo.placeIds[1]
                GamesSection:Button({
                    Name = "→ " .. gameInfo.name,
                    Callback = function()
                        Library:Notification({
                            Name = "Teleporting",
                            Description = "Teleporting to " .. gameInfo.name .. "...",
                            Duration = 3,
                            Icon = "109463522861706",
                            IconColor = Color3.fromRGB(56, 189, 248)
                        })
                        TeleportService:Teleport(targetPlaceId, Player)
                    end
                })
            else
                GamesSection:Label("• " .. gameInfo.name, "Left")
            end
        end
    end

    --[[ SUGGESTIONS SECTION ]]--
    local suggestionTextbox
    
    suggestionTextbox = SuggestionsSection:Textbox({
        Name = "your suggestion",
        Flag = "About/Suggestion",
        Placeholder = "enter your suggestion here...",
        Default = "",
        Callback = function(Value)
            suggestionText = Value
        end
    })

    SuggestionsSection:Button({
        Name = "send suggestion",
        Callback = function()
            local currentTime = tick()
            local timeSinceLastSuggestion = currentTime - lastSuggestionTime
            
            if timeSinceLastSuggestion < SUGGESTION_COOLDOWN then
                local remainingTime = math.ceil(SUGGESTION_COOLDOWN - timeSinceLastSuggestion)
                Library:Notification({
                    Name = "Cooldown",
                    Description = "Please wait " .. remainingTime .. " seconds before sending another suggestion",
                    Duration = 3,
                    Icon = "97118059177470",
                    IconColor = Color3.fromRGB(255, 120, 120)
                })
                return
            end
            
            if suggestionText and suggestionText:gsub("%s", "") ~= "" then
                -- Send suggestion via webhook (placeholder - implement your webhook here)
                pcall(function()
                    local webhookUrl = "YOUR_WEBHOOK_URL_HERE" -- Replace with actual webhook
                    local data = {
                        content = "**New Suggestion from " .. Player.Name .. ":**\n" .. suggestionText
                    }
                    -- HttpService:PostAsync(webhookUrl, HttpService:JSONEncode(data))
                end)
                
                lastSuggestionTime = currentTime
                suggestionText = ""
                
                Library:Notification({
                    Name = "Success",
                    Description = "Your suggestion has been sent! Thank you.",
                    Duration = 3,
                    Icon = "116339777575852",
                    IconColor = Color3.fromRGB(52, 255, 164)
                })
            else
                Library:Notification({
                    Name = "Error",
                    Description = "Please enter a suggestion first",
                    Duration = 3,
                    Icon = "97118059177470",
                    IconColor = Color3.fromRGB(255, 120, 120)
                })
            end
        end
    })

        SuggestionsSection:Button({
            Name = "join discord",
            Callback = function()
                pcall(function()
                    setclipboard("https://discord.gg/stalkie")
                end)
                
                Library:Notification({
                    Name = "Discord",
                    Description = "Discord link copied to clipboard!",
                    Duration = 3,
                    Icon = "116339777575852",
                    IconColor = Color3.fromRGB(88, 101, 242)
                })
            end
        })
    end
    
    --[[ ==================== THEMING SUB-PAGE ==================== ]]--
    do
        local ThemingSection = Subpages["Theming"]:Section({Name = "theming", Icon = "103863157706913", Side = 1})

        local FONTS = {
            ["Inter (Default)"] = { name = "Inter",       url = "https://github.com/sametexe001/luas/raw/refs/heads/main/fonts/InterSemibold.ttf" },
            ["ProggyClean"]     = { name = "ProggyClean", url = "https://github.com/i77lhm/storage/raw/refs/heads/main/fonts/ProggyClean.ttf" },
            ["Verdana"]         = { name = "Verdana",     url = "https://github.com/i77lhm/storage/raw/refs/heads/main/fonts/Verdana-Font.ttf" },
            ["Minecraftia"]     = { name = "Minecraftia", url = "https://github.com/i77lhm/storage/raw/refs/heads/main/fonts/Minecraftia-Regular.ttf" },
            ["Tahoma Bold"]     = { name = "TahomaBold",  url = "https://github.com/i77lhm/storage/raw/refs/heads/main/fonts/tahoma_bold.ttf" },
        }

        ThemingSection:Dropdown({
            Name    = "Font",
            Flag    = "FontSelector",
            Items   = {"Inter (Default)", "ProggyClean", "Verdana", "Minecraftia", "Tahoma Bold"},
            Default = "Inter (Default)",
            Multi   = false,
            Callback = function(Value)
                local info = FONTS[Value]
                if not info then return end
                task.spawn(function()
                    Library:LoadFont(info.name, info.url)
                end)
            end
        })

        local ThemingProfiles = Subpages["Theming"]:Section({Name = "profiles", Icon = "96491224522405", Side = 2})
        local AutoloadSection = Subpages["Theming"]:Section({Name = "autoload", Icon = "137623872962804", Side = 2})
        
        -- Custom Mouse Toggle
        ThemingSection:Toggle({
            Name = "Custom Mouse",
            Flag = "Theming/CustomMouse",
            Default = true,
            Callback = function(Value)
                Library.CustomMouseEnabled = Value
            end
        })
        
        -- Add colorpickers for all theme elements
        for Index, Value in Library.Theme do 
            Library.ThemeColorpickers[Index] = ThemingSection:Label(Index, "Left"):Colorpicker({
                Name = "Colorpicker",
                Flag = "ColorpickerTheme" .. Index,
                Default = Value,
                Alpha = 0,
                Callback = function(Color, Alpha)
                    Library.Theme[Index] = Color
                    Library:ChangeTheme(Index, Color)
                end
            })
        end
        
        -- Preset themes dropdown
        ThemingProfiles:Dropdown({
            Name = "preset themes",
            Items = {"Preset", "Halloween", "Aqua", "One Tap"},
            Default = "Preset",
            Multi = false,
            Callback = function(Value)
                local ThemeData = Library.Themes[Value]
                if not ThemeData then return end
                
                for Index, Value in Library.Theme do 
                    Library.Theme[Index] = ThemeData[Index]
                    Library:ChangeTheme(Index, ThemeData[Index])
                    Library.ThemeColorpickers[Index]:Set(ThemeData[Index])
                end
                
                task.wait(0.3)
                Library:Thread(function()
                    for Index, Value in Library.Theme do 
                        Library.Theme[Index] = Library.Flags["ColorpickerTheme" .. Index].Color
                        Library:ChangeTheme(Index, Library.Flags["ColorpickerTheme" .. Index].Color)
                    end    
                end)
            end
        })
        
        local ThemeName
        
        ThemesDropdown = ThemingProfiles:Dropdown({
            Name = "themes",
            Flag = "ThemesList",
            Items = {},
            Multi = false,
            Callback = function(Value)
                ThemeSelected = Value
            end
        })
        
        ThemingProfiles:Textbox({
            Name = "theme name",
            Default = "",
            Flag = "ThemeName",
            Placeholder = "enter text",
            Callback = function(Value)
                ThemeName = Value
            end
        })
        
        ThemingProfiles:Button({
            Name = "save",
            Callback = function()
                if ThemeName and ThemeName ~= "" then
                    writefile(Library.Folders.Themes .. "/" .. ThemeName .. ".json", Library:GetTheme())
                    Library:RefreshThemesList(ThemesDropdown)
                    Library:Notification({Name = "Saved", Description = "Saved theme: " .. ThemeName .. ".json", Duration = 5, Icon = "116339777575852", IconColor = Color3.fromRGB(52, 255, 164)})
                    ThemeName = ""
                    Library.SetFlags["ThemeName"]("")
                else
                    Library:Notification({Name = "Error!", Description = "Enter a theme name first", Duration = 3, Icon = "97118059177470", IconColor = Color3.fromRGB(255, 120, 120)})
                end
            end
        })
        
        ThemingProfiles:Button({
            Name = "load",
            Callback = function()
                if ThemeSelected then
                    local Success, Result = Library:LoadTheme(readfile(Library.Folders.Themes .. "/" .. ThemeSelected))
                    if Success then 
                        Library:Notification({Name = "Success", Description = "Loaded theme: " .. ThemeSelected, Duration = 5, Icon = "116339777575852", IconColor = Color3.fromRGB(52, 255, 164)})
                        task.wait(0.3)
                        Library:Thread(function()
                            for Index, Value in Library.Theme do 
                                Library.Theme[Index] = Library.Flags["ColorpickerTheme" .. Index].Color
                                Library:ChangeTheme(Index, Library.Flags["ColorpickerTheme" .. Index].Color)
                            end    
                        end)
                    else
                        Library:Notification({Name = "Error!", Description = "Failed to load theme", Duration = 5, Icon = "97118059177470", IconColor = Color3.fromRGB(255, 120, 120)})
                    end
                else
                    Library:Notification({Name = "Error!", Description = "Select a theme first", Duration = 3, Icon = "97118059177470", IconColor = Color3.fromRGB(255, 120, 120)})
                end
            end
        })

        ThemingProfiles:Button({
            Name = "delete",
            Callback = function()
                if ThemeSelected then
                    local deleted = ThemeSelected
                    ThemeSelected = nil
                    local autoName = readfile(Library.Folders.Directory .. "/AutoLoadThemeName.txt")
                    if autoName == deleted then
                        writefile(Library.Folders.Directory .. "/AutoLoadTheme (do not modify this).json", "")
                        writefile(Library.Folders.Directory .. "/AutoLoadThemeName.txt", "")
                    end
                    Library:DeleteTheme(deleted)
                    Library:RefreshThemesList(ThemesDropdown)
                else
                    Library:Notification({Name = "Error!", Description = "Select a theme first", Duration = 3, Icon = "97118059177470", IconColor = Color3.fromRGB(255, 120, 120)})
                end
            end
        })
        
        AutoloadSection:Button({
            Name = "set selected theme as autoload",
            Callback = function()
                if ThemeSelected then 
                    writefile(Library.Folders.Directory .. "/AutoLoadTheme (do not modify this).json", readfile(Library.Folders.Themes .. "/" .. ThemeSelected))
                    writefile(Library.Folders.Directory .. "/AutoLoadThemeName.txt", ThemeSelected)
                    Library:Notification({Name = "Autoload Set", Description = ThemeSelected .. " will autoload on next execution", Duration = 5, Icon = "116339777575852", IconColor = Color3.fromRGB(52, 255, 164)})
                else
                    Library:Notification({Name = "Error!", Description = "Select a theme first", Duration = 3, Icon = "97118059177470", IconColor = Color3.fromRGB(255, 120, 120)})
                end
            end
        })
        
        AutoloadSection:Button({
            Name = "set current theme as autoload",
            Callback = function()
                writefile(Library.Folders.Directory .. "/AutoLoadTheme (do not modify this).json", Library:GetTheme())
                writefile(Library.Folders.Directory .. "/AutoLoadThemeName.txt", ThemeSelected or "")
                Library:Notification({Name = "Autoload Set", Description = "Current theme will autoload on next execution", Duration = 5, Icon = "116339777575852", IconColor = Color3.fromRGB(52, 255, 164)})
            end
        })
        
        AutoloadSection:Button({
            Name = "remove autoload theme",
            Callback = function()
                writefile(Library.Folders.Directory .. "/AutoLoadTheme (do not modify this).json", "")
                writefile(Library.Folders.Directory .. "/AutoLoadThemeName.txt", "")
                Library:Notification({Name = "Autoload Removed", Description = "Theme autoload has been cleared", Duration = 5, Icon = "116339777575852", IconColor = Color3.fromRGB(52, 255, 164)})
            end
        })
        
        Library:RefreshThemesList(ThemesDropdown)
    end

    --[[ ==================== CONFIGURATION SUB-PAGE ==================== ]]--
    do
        local MenuSection     = Subpages["Configuration"]:Section({Name = "menu",     Icon = "93007870315593",  Side = 1})
        local TweeningSection = Subpages["Configuration"]:Section({Name = "tweening", Icon = "130045183204879", Side = 2})

        MenuSection:Label("menu keybind", "Left"):Keybind({
            Name     = "MenuKeybind",
            Flag     = "MenuKeybind",
            Mode     = "toggle",
            Default  = Library.MenuKeybind,
            Callback = function()
                Library.MenuKeybind = Library.Flags["MenuKeybind"].Key
            end
        })

        MenuSection:Toggle({
            Name     = "keybind list",
            Flag     = "keybind list",
            Default  = true,
            Callback = function(Value)
                KeybindList:SetVisibility(Value)
            end
        })

        MenuSection:Toggle({
            Name     = "watermark",
            Flag     = "watermark",
            Default  = false,
            Callback = function(Value)
                Watermark:SetVisibility(Value)
            end
        })

        MenuSection:Button({
            Name     = "unload",
            Callback = function()
                Library:Unload()
            end
        })

        TweeningSection:Slider({
            Name     = "time",
            Flag     = "TweenTime",
            Default  = Library.Tween.Time,
            Min      = 0,
            Max      = 5,
            Decimals = 0.01,
            Callback = function(Value)
                Library.Tween.Time = Value
            end
        })

        TweeningSection:Dropdown({
            Name     = "style",
            Flag     = "TweenStyle",
            Default  = "Cubic",
            Items    = {"Linear", "Sine", "Quad", "Cubic", "Quart", "Quint", "Exponential", "Circular", "Back", "Elastic", "Bounce"},
            MaxSize  = 150,
            Callback = function(Value)
                Library.Tween.Style = Enum.EasingStyle[Value]
            end
        })

        TweeningSection:Dropdown({
            Name     = "direction",
            Flag     = "TweenDirection",
            Default  = "Out",
            MaxSize  = 55,
            Items    = {"In", "Out", "InOut"},
            Callback = function(Value)
                Library.Tween.Direction = Enum.EasingDirection[Value]
            end
        })
    end
end

-- Show loaded notification
Library:Notification({
    Name = "Stalkie 2.0",
    Description = "Loaded successfully!",
    Duration = 5,
    Icon = "116339777575852",
    IconColor = Color3.fromRGB(52, 255, 164)
})

-- Initialize the library (required for autoload to work)
Library:Init()

-- Auto-select the config that was autoloaded
local autoLoadName = readfile(Library.Folders.Directory .. "/AutoLoadConfigName.txt")
if autoLoadName and autoLoadName ~= "" and ConfigsDropdown then
    ConfigSelected = autoLoadName
    ConfigsDropdown:Set(autoLoadName)
end

-- Auto-select the theme that was autoloaded
local autoLoadThemeName = readfile(Library.Folders.Directory .. "/AutoLoadThemeName.txt")
if autoLoadThemeName and autoLoadThemeName ~= "" and ThemesDropdown then
    ThemeSelected = autoLoadThemeName
    ThemesDropdown:Set(autoLoadThemeName)
end
