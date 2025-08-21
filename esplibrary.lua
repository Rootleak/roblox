--!nolint BuiltinGlobalWrite
--!optimize 2
--!native

if getconnections then
    if cloneref then
        for _,v in pairs(getconnections(cloneref(game:GetService("LogService")).MessageOut)) do v:Disable() end
        for _,v in pairs(getconnections(cloneref(game:GetService("ScriptContext")).Error)) do v:Disable() end
    else
        for _,v in pairs(getconnections(game:GetService("LogService")).MessageOut) do v:Disable() end
        for _,v in pairs(getconnections(game:GetService("ScriptContext")).Error) do v:Disable() end
    end
end

local function randomHex(len)
    local str = ""
    for i = 1, len do
        str = str .. string.format("%x", math.random(0, 15))
    end
    return str
end

local function randstr()
    local uuid = table.concat({
        randomHex(8),
        randomHex(4),
        randomHex(4),
        randomHex(4),
        randomHex(12)
    }, "-")
    return "ESP_" .. uuid
end

local ESP_KEY = randstr()

if not getgenv()[ESP_KEY] then
    getgenv()[ESP_KEY] = {
        Enabled = false,
        
        BoxType = "3DCorner",
        TracersEnabled = false,
        SkeletonEnabled = false,
        
        Color = Color3.fromRGB(255, 255, 255),
        Thickness = 1.0,
        Transparency = 1,
        
        CornerSize = 0.3,
        
        TracerOrigin = "Bottom",
        TracerThickness = 1.0,
        TracerTransparency = 1,
        
        SkeletonThickness = 1.0,
        SkeletonTransparency = 1,
        
        Objects = {},
        PlayerData = {},
        Initialized = false,
        UpdateConnection = nil
    }
end

local ESP = getgenv()[ESP_KEY]

local function gs(service)
    local ok, result = pcall(function()
        if clonefunction and game.GetService then
            return clonefunction(game.GetService)(game, service)
        else
            return game:GetService(service)
        end
    end)
    return ok and result or nil
end

local function define(instance)
    if cloneref then
        local ok, protected = pcall(cloneref, instance)
        if ok and protected then
            return protected
        end
    end
    return instance
end

local RunService = define(gs("RunService"))
local Players = define(gs("Players"))
local LocalPlayer = define(Players.LocalPlayer)
local Camera = define(workspace.CurrentCamera)

local function GetCharacterBounds(character)
    if not character then return nil end
    
    local parts = {}
    for _, part in pairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            table.insert(parts, part)
        end
    end
    
    if #parts == 0 then return nil end
    
    local minX, minY, minZ = math.huge, math.huge, math.huge
    local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
    
    for _, part in ipairs(parts) do
        local cf, size = part.CFrame, part.Size
        local halfSize = size / 2
        
        local cornerPositions = {
            (cf * CFrame.new(-halfSize.X, -halfSize.Y, -halfSize.Z)).Position,
            (cf * CFrame.new(-halfSize.X, halfSize.Y, -halfSize.Z)).Position,
            (cf * CFrame.new(halfSize.X, -halfSize.Y, -halfSize.Z)).Position,
            (cf * CFrame.new(halfSize.X, halfSize.Y, -halfSize.Z)).Position,
            (cf * CFrame.new(-halfSize.X, -halfSize.Y, halfSize.Z)).Position,
            (cf * CFrame.new(-halfSize.X, halfSize.Y, halfSize.Z)).Position,
            (cf * CFrame.new(halfSize.X, -halfSize.Y, halfSize.Z)).Position,
            (cf * CFrame.new(halfSize.X, halfSize.Y, halfSize.Z)).Position
        }
        
        for _, pos in ipairs(cornerPositions) do
            minX = math.min(minX, pos.X)
            minY = math.min(minY, pos.Y)
            minZ = math.min(minZ, pos.Z)
            maxX = math.max(maxX, pos.X)
            maxY = math.max(maxY, pos.Y)
            maxZ = math.max(maxZ, pos.Z)
        end
    end
    
    local centerPos = Vector3.new(
        (minX + maxX) / 2,
        (minY + maxY) / 2,
        (minZ + maxZ) / 2
    )
    
    local size = Vector3.new(
        maxX - minX,
        maxY - minY,
        maxZ - minZ
    )
    
    return {
        CFrame = CFrame.new(centerPos),
        Size = size + Vector3.new(0.1, 0.1, 0.1)
    }
end

local function GetBoxCorners(bounds)
    if not bounds then return nil end
    
    local cf, size = bounds.CFrame, bounds.Size
    local halfSize = size / 2
    
    return {
        (cf * CFrame.new(-halfSize.X, -halfSize.Y, -halfSize.Z)).Position,
        (cf * CFrame.new(-halfSize.X, -halfSize.Y, halfSize.Z)).Position,
        (cf * CFrame.new(-halfSize.X, halfSize.Y, -halfSize.Z)).Position,
        (cf * CFrame.new(-halfSize.X, halfSize.Y, halfSize.Z)).Position,
        (cf * CFrame.new(halfSize.X, -halfSize.Y, -halfSize.Z)).Position,
        (cf * CFrame.new(halfSize.X, -halfSize.Y, halfSize.Z)).Position,
        (cf * CFrame.new(halfSize.X, halfSize.Y, -halfSize.Z)).Position,
        (cf * CFrame.new(halfSize.X, halfSize.Y, halfSize.Z)).Position
    }
end

local function Get2DBoxFromBounds(bounds)
    local corners = GetBoxCorners(bounds)
    if not corners then return nil end
    
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    
    for _, corner in ipairs(corners) do
        local screenPoint, onScreen = Camera:WorldToViewportPoint(corner)
        if onScreen then
            minX = math.min(minX, screenPoint.X)
            minY = math.min(minY, screenPoint.Y)
            maxX = math.max(maxX, screenPoint.X)
            maxY = math.max(maxY, screenPoint.Y)
        else
            return nil
        end
    end
    
    return {
        TopLeft = Vector2.new(minX, minY),
        TopRight = Vector2.new(maxX, minY),
        BottomLeft = Vector2.new(minX, maxY),
        BottomRight = Vector2.new(maxX, maxY),
        Width = maxX - minX,
        Height = maxY - minY
    }
end

local function GetCharacterCenter(character)
    if not character then return nil end
    
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if hrp then
        return hrp.Position
    end
    
    local bounds = GetCharacterBounds(character)
    if bounds then
        return bounds.CFrame.Position
    end
    
    return nil
end

local SKELETON_CONNECTIONS = {
    {"Head", "UpperTorso"},
    {"UpperTorso", "LowerTorso"},
    
    {"UpperTorso", "RightUpperArm"},
    {"RightUpperArm", "RightLowerArm"},
    {"RightLowerArm", "RightHand"},
    
    {"UpperTorso", "LeftUpperArm"},
    {"LeftUpperArm", "LeftLowerArm"},
    {"LeftLowerArm", "LeftHand"},
    
    {"LowerTorso", "RightUpperLeg"},
    {"RightUpperLeg", "RightLowerLeg"},
    {"RightLowerLeg", "RightFoot"},
    
    {"LowerTorso", "LeftUpperLeg"},
    {"LeftUpperLeg", "LeftLowerLeg"},
    {"LeftLowerLeg", "LeftFoot"}
}

local R6_CONNECTIONS = {
    {"Head", "Torso"},
    {"Torso", "Left Arm"},
    {"Torso", "Right Arm"},
    {"Torso", "Left Leg"},
    {"Torso", "Right Leg"}
}

local function GetJointPosition(character, partName)
    if not character then return nil end
    
    if partName == "UpperTorso" then
        local upperTorso = character:FindFirstChild("UpperTorso")
        if upperTorso and upperTorso:IsA("BasePart") then
            local size = upperTorso.Size
            local offset = Vector3.new(0, size.Y/2 - 0.2, 0)
            return upperTorso.Position + (upperTorso.CFrame.UpVector * offset.Y)
        end
        
        local torso = character:FindFirstChild("Torso")
        if torso and torso:IsA("BasePart") then
            local size = torso.Size
            local offset = Vector3.new(0, size.Y/2 - 0.5, 0)
            return torso.Position + (torso.CFrame.UpVector * offset.Y)
        end
    end
    
    local part = character:FindFirstChild(partName)
    if not part or not part:IsA("BasePart") then
        if partName == "UpperTorso" then
            part = character:FindFirstChild("Torso")
        elseif partName == "LowerTorso" then
            part = character:FindFirstChild("Torso")
        elseif partName == "RightUpperArm" then
            part = character:FindFirstChild("Right Arm")
        elseif partName == "LeftUpperArm" then
            part = character:FindFirstChild("Left Arm")
        elseif partName == "RightUpperLeg" then
            part = character:FindFirstChild("Right Leg")
        elseif partName == "LeftUpperLeg" then
            part = character:FindFirstChild("Left Leg")
        end
    end
    
    if part and part:IsA("BasePart") then
        return part.Position
    end
    
    return nil
end

function ESP:CreateSkeletonESP(player)
    local playerData = self.PlayerData[player]
    if not playerData then return end
    
    playerData.Objects.Skeleton = {}
    
    for _, connection in ipairs(SKELETON_CONNECTIONS) do
        local line = Drawing.new("Line")
        line.Thickness = self.SkeletonThickness
        line.Color = self.Color
        line.Transparency = self.SkeletonTransparency
        line.Visible = false
        
        table.insert(playerData.Objects.Skeleton, {
            Line = line,
            From = connection[1],
            To = connection[2]
        })
    end
    
    for _, connection in ipairs(R6_CONNECTIONS) do
        local line = Drawing.new("Line")
        line.Thickness = self.SkeletonThickness
        line.Color = self.Color
        line.Transparency = self.SkeletonTransparency
        line.Visible = false
        
        table.insert(playerData.Objects.Skeleton, {
            Line = line,
            From = connection[1],
            To = connection[2],
            IsR6 = true
        })
    end
end

function ESP:UpdateSkeletonESP(player, character)
    local playerData = self.PlayerData[player]
    if not playerData or not playerData.Objects.Skeleton then return end
    
    if not self.Enabled or not self.SkeletonEnabled or not character then
        for _, connection in ipairs(playerData.Objects.Skeleton) do
            connection.Line.Visible = false
        end
        return
    end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local rigType = humanoid and humanoid.RigType or Enum.HumanoidRigType.R15
    
    for _, connection in ipairs(playerData.Objects.Skeleton) do
        if (rigType == Enum.HumanoidRigType.R15 and connection.IsR6) or
           (rigType == Enum.HumanoidRigType.R6 and not connection.IsR6) then
            connection.Line.Visible = false
            continue
        end
        
        local fromPos = GetJointPosition(character, connection.From)
        local toPos = GetJointPosition(character, connection.To)
        
        if not fromPos or not toPos then
            connection.Line.Visible = false
            continue
        end
        
        local fromPoint, fromVisible = Camera:WorldToViewportPoint(fromPos)
        local toPoint, toVisible = Camera:WorldToViewportPoint(toPos)
        
        if not fromVisible or not toVisible then
            connection.Line.Visible = false
            continue
        end
        
        connection.Line.From = Vector2.new(fromPoint.X, fromPoint.Y)
        connection.Line.To = Vector2.new(toPoint.X, toPoint.Y)
        connection.Line.Visible = true
    end
end

function ESP:HideSkeletonESP(player)
    local playerData = self.PlayerData[player]
    if not playerData or not playerData.Objects.Skeleton then return end
    
    for _, connection in ipairs(playerData.Objects.Skeleton) do
        connection.Line.Visible = false
    end
end

function ESP:UpdateSkeletonColors()
    for player, playerData in pairs(self.PlayerData) do
        if playerData.Objects.Skeleton then
            for _, connection in ipairs(playerData.Objects.Skeleton) do
                connection.Line.Color = self.Color
                connection.Line.Thickness = self.SkeletonThickness
                connection.Line.Transparency = self.SkeletonTransparency
            end
        end
    end
end

function ESP:SetSkeletonThickness(thickness)
    self.SkeletonThickness = thickness
    
    for player, playerData in pairs(self.PlayerData) do
        if playerData.Objects.Skeleton then
            for _, connection in ipairs(playerData.Objects.Skeleton) do
                connection.Line.Thickness = thickness
            end
        end
    end
    
    return self
end

function ESP:SetSkeletonTransparency(transparency)
    self.SkeletonTransparency = transparency
    
    for player, playerData in pairs(self.PlayerData) do
        if playerData.Objects.Skeleton then
            for _, connection in ipairs(playerData.Objects.Skeleton) do
                connection.Line.Transparency = transparency
            end
        end
    end
    
    return self
end

function ESP:ToggleSkeleton(enabled)
    self.SkeletonEnabled = enabled
    
    if not enabled then
        for player, _ in pairs(self.PlayerData) do
            self:HideSkeletonESP(player)
        end
    end
    
    return self
end

function ESP:CreatePlayerESP(player)
    local playerData = {
        Objects = {},
        Type = "",
        Connection = nil
    }
    
    local box2D = {}
    for i = 1, 4 do
        box2D[i] = Drawing.new("Line")
        box2D[i].Thickness = self.Thickness
        box2D[i].Color = self.Color
        box2D[i].Transparency = self.Transparency
        box2D[i].Visible = false
    end
    playerData.Objects.Box2D = box2D
    
    local box2DCorner = {}
    for i = 1, 8 do
        box2DCorner[i] = Drawing.new("Line")
        box2DCorner[i].Thickness = self.Thickness
        box2DCorner[i].Color = self.Color
        box2DCorner[i].Transparency = self.Transparency
        box2DCorner[i].Visible = false
    end
    playerData.Objects.Box2DCorner = box2DCorner
    
    local box3D = {}
    for i = 1, 12 do
        box3D[i] = Drawing.new("Line")
        box3D[i].Thickness = self.Thickness
        box3D[i].Color = self.Color
        box3D[i].Transparency = self.Transparency
        box3D[i].Visible = false
    end
    playerData.Objects.Box3D = box3D
    
    local box3DCorner = {}
    for i = 1, 8 do
        box3DCorner[i] = {}
        for j = 1, 3 do
            box3DCorner[i][j] = Drawing.new("Line")
            box3DCorner[i][j].Thickness = self.Thickness
            box3DCorner[i][j].Color = self.Color
            box3DCorner[i][j].Transparency = self.Transparency
            box3DCorner[i][j].Visible = false
        end
    end
    playerData.Objects.Box3DCorner = box3DCorner
    
    local tracer = Drawing.new("Line")
    tracer.Thickness = self.TracerThickness
    tracer.Color = self.Color
    tracer.Transparency = self.TracerTransparency
    tracer.Visible = false
    playerData.Objects.Tracer = tracer
    
    self.PlayerData[player] = playerData
    
    self:CreateSkeletonESP(player)
end

function ESP:RemovePlayerESP(player)
    local playerData = self.PlayerData[player]
    if not playerData then return end
    
    for _, line in ipairs(playerData.Objects.Box2D) do
        line:Remove()
    end
    
    for _, line in ipairs(playerData.Objects.Box2DCorner) do
        line:Remove()
    end
    
    for _, line in ipairs(playerData.Objects.Box3D) do
        line:Remove()
    end
    
    for _, corner in ipairs(playerData.Objects.Box3DCorner) do
        for _, line in ipairs(corner) do
            line:Remove()
        end
    end
    
    playerData.Objects.Tracer:Remove()
    
    if playerData.Objects.Skeleton then
        for _, connection in ipairs(playerData.Objects.Skeleton) do
            connection.Line:Remove()
        end
    end
    
    self.PlayerData[player] = nil
end

function ESP:HidePlayerESP(player)
    local playerData = self.PlayerData[player]
    if not playerData then return end
    
    for _, line in ipairs(playerData.Objects.Box2D) do
        line.Visible = false
    end
    
    for _, line in ipairs(playerData.Objects.Box2DCorner) do
        line.Visible = false
    end
    
    for _, line in ipairs(playerData.Objects.Box3D) do
        line.Visible = false
    end
    
    for _, corner in ipairs(playerData.Objects.Box3DCorner) do
        for _, line in ipairs(corner) do
            line.Visible = false
        end
    end
    
    playerData.Objects.Tracer.Visible = false
    
    self:HideSkeletonESP(player)
end

function ESP:Update2DBox(player, bounds)
    local playerData = self.PlayerData[player]
    if not playerData then return end
    
    local box = Get2DBoxFromBounds(bounds)
    if not box then
        for _, line in ipairs(playerData.Objects.Box2D) do
            line.Visible = false
        end
        return
    end
    
    playerData.Objects.Box2D[1].From = box.TopLeft
    playerData.Objects.Box2D[1].To = box.TopRight
    playerData.Objects.Box2D[1].Visible = true
    
    playerData.Objects.Box2D[2].From = box.TopRight
    playerData.Objects.Box2D[2].To = box.BottomRight
    playerData.Objects.Box2D[2].Visible = true
    
    playerData.Objects.Box2D[3].From = box.BottomRight
    playerData.Objects.Box2D[3].To = box.BottomLeft
    playerData.Objects.Box2D[3].Visible = true
    
    playerData.Objects.Box2D[4].From = box.BottomLeft
    playerData.Objects.Box2D[4].To = box.TopLeft
    playerData.Objects.Box2D[4].Visible = true
end

function ESP:Update2DCornerBox(player, bounds)
    local playerData = self.PlayerData[player]
    if not playerData then return end
    
    local box = Get2DBoxFromBounds(bounds)
    if not box then
        for _, line in ipairs(playerData.Objects.Box2DCorner) do
            line.Visible = false
        end
        return
    end
    
    local cornerSize = box.Width * self.CornerSize
    if cornerSize > box.Height * self.CornerSize then
        cornerSize = box.Height * self.CornerSize
    end
    
    playerData.Objects.Box2DCorner[1].From = box.TopLeft
    playerData.Objects.Box2DCorner[1].To = Vector2.new(box.TopLeft.X + cornerSize, box.TopLeft.Y)
    playerData.Objects.Box2DCorner[1].Visible = true
    
    playerData.Objects.Box2DCorner[2].From = box.TopLeft
    playerData.Objects.Box2DCorner[2].To = Vector2.new(box.TopLeft.X, box.TopLeft.Y + cornerSize)
    playerData.Objects.Box2DCorner[2].Visible = true
    
    playerData.Objects.Box2DCorner[3].From = box.TopRight
    playerData.Objects.Box2DCorner[3].To = Vector2.new(box.TopRight.X - cornerSize, box.TopRight.Y)
    playerData.Objects.Box2DCorner[3].Visible = true
    
    playerData.Objects.Box2DCorner[4].From = box.TopRight
    playerData.Objects.Box2DCorner[4].To = Vector2.new(box.TopRight.X, box.TopRight.Y + cornerSize)
    playerData.Objects.Box2DCorner[4].Visible = true
    
    playerData.Objects.Box2DCorner[5].From = box.BottomLeft
    playerData.Objects.Box2DCorner[5].To = Vector2.new(box.BottomLeft.X + cornerSize, box.BottomLeft.Y)
    playerData.Objects.Box2DCorner[5].Visible = true
    
    playerData.Objects.Box2DCorner[6].From = box.BottomLeft
    playerData.Objects.Box2DCorner[6].To = Vector2.new(box.BottomLeft.X, box.BottomLeft.Y - cornerSize)
    playerData.Objects.Box2DCorner[6].Visible = true
    
    playerData.Objects.Box2DCorner[7].From = box.BottomRight
    playerData.Objects.Box2DCorner[7].To = Vector2.new(box.BottomRight.X - cornerSize, box.BottomRight.Y)
    playerData.Objects.Box2DCorner[7].Visible = true
    
    playerData.Objects.Box2DCorner[8].From = box.BottomRight
    playerData.Objects.Box2DCorner[8].To = Vector2.new(box.BottomRight.X, box.BottomRight.Y - cornerSize)
    playerData.Objects.Box2DCorner[8].Visible = true
end

function ESP:Update3DBox(player, bounds)
    local playerData = self.PlayerData[player]
    if not playerData then return end
    
    local corners = GetBoxCorners(bounds)
    if not corners then
        for _, line in ipairs(playerData.Objects.Box3D) do
            line.Visible = false
        end
        return
    end
    
    local screenCorners = {}
    local anyVisible = false
    
    for i, corner in ipairs(corners) do
        local screenPoint, onScreen = Camera:WorldToViewportPoint(corner)
        screenCorners[i] = {
            Position = Vector2.new(screenPoint.X, screenPoint.Y),
            Visible = onScreen
        }
        if onScreen then
            anyVisible = true
        end
    end
    
    if not anyVisible then
        for _, line in ipairs(playerData.Objects.Box3D) do
            line.Visible = false
        end
        return
    end
    
    local edges = {
        {1, 2}, {1, 3}, {1, 5},
        {2, 4}, {2, 6},
        {3, 4}, {3, 7},
        {4, 8},
        {5, 6}, {5, 7},
        {6, 8},
        {7, 8}
    }
    
    for i, edge in ipairs(edges) do
        local p1 = screenCorners[edge[1]]
        local p2 = screenCorners[edge[2]]
        
        if p1.Visible or p2.Visible then
            playerData.Objects.Box3D[i].From = p1.Position
            playerData.Objects.Box3D[i].To = p2.Position
            playerData.Objects.Box3D[i].Visible = true
        else
            playerData.Objects.Box3D[i].Visible = false
        end
    end
end

function ESP:Update3DCornerBox(player, bounds)
    local playerData = self.PlayerData[player]
    if not playerData then return end
    
    local corners = GetBoxCorners(bounds)
    if not corners then
        for _, corner in ipairs(playerData.Objects.Box3DCorner) do
            for _, line in ipairs(corner) do
                line.Visible = false
            end
        end
        return
    end
    
    local screenCorners = {}
    local anyVisible = false
    
    for i, corner in ipairs(corners) do
        local screenPoint, onScreen = Camera:WorldToViewportPoint(corner)
        screenCorners[i] = {
            Position = Vector2.new(screenPoint.X, screenPoint.Y),
            Visible = onScreen
        }
        if onScreen then
            anyVisible = true
        end
    end
    
    if not anyVisible then
        for _, corner in ipairs(playerData.Objects.Box3DCorner) do
            for _, line in ipairs(corner) do
                line.Visible = false
            end
        end
        return
    end
    
    local cornerConnections = {
        { {1, 2}, {1, 3}, {1, 5} },
        { {2, 1}, {2, 4}, {2, 6} },
        { {3, 1}, {3, 4}, {3, 7} },
        { {4, 2}, {4, 3}, {4, 8} },
        { {5, 1}, {5, 6}, {5, 7} },
        { {6, 2}, {6, 5}, {6, 8} },
        { {7, 3}, {7, 5}, {7, 8} },
        { {8, 4}, {8, 6}, {8, 7} }
    }
    
    for cornerIndex, connections in ipairs(cornerConnections) do
        local cornerVisible = screenCorners[cornerIndex].Visible
        local cornerPos = screenCorners[cornerIndex].Position
        
        for lineIndex, connection in ipairs(connections) do
            local line = playerData.Objects.Box3DCorner[cornerIndex][lineIndex]
            
            if cornerVisible then
                local connectedCornerIndex = connection[2]
                local connectedCornerPos = screenCorners[connectedCornerIndex].Position
                
                local direction = (connectedCornerPos - cornerPos).Unit
                local endPoint = cornerPos + direction * (cornerPos - connectedCornerPos).Magnitude * self.CornerSize
                
                line.From = cornerPos
                line.To = endPoint
                line.Visible = true
            else
                line.Visible = false
            end
        end
    end
end

function ESP:UpdateTracer(player, character)
    local playerData = self.PlayerData[player]
    if not playerData then return end
    
    local center = GetCharacterCenter(character)
    if not center then
        playerData.Objects.Tracer.Visible = false
        return
    end
    
    local screenPoint, onScreen = Camera:WorldToViewportPoint(center)
    if not onScreen then
        playerData.Objects.Tracer.Visible = false
        return
    end
    
    local from
    local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    
    if self.TracerOrigin == "Bottom" then
        from = Vector2.new(screenCenter.X, Camera.ViewportSize.Y)
    elseif self.TracerOrigin == "Top" then
        from = Vector2.new(screenCenter.X, 0)
    elseif self.TracerOrigin == "Center" then
        from = screenCenter
    elseif self.TracerOrigin == "Mouse" then
        local UserInputService = gs("UserInputService")
        from = UserInputService:GetMouseLocation()
    end
    
    playerData.Objects.Tracer.From = from
    playerData.Objects.Tracer.To = Vector2.new(screenPoint.X, screenPoint.Y)
    playerData.Objects.Tracer.Visible = self.TracersEnabled
end

function ESP:UpdatePlayerESP(player)
    if not self.Enabled then
        self:HidePlayerESP(player)
        return
    end
    
    local character = player.Character
    if not character then
        self:HidePlayerESP(player)
        return
    end
    
    local bounds = GetCharacterBounds(character)
    if not bounds then
        self:HidePlayerESP(player)
        return
    end
    
    if self.BoxType == "2D" then
        self:Update2DBox(player, bounds)
    elseif self.BoxType == "2DCorner" then
        self:Update2DCornerBox(player, bounds)
    elseif self.BoxType == "3D" then
        self:Update3DBox(player, bounds)
    elseif self.BoxType == "3DCorner" then
        self:Update3DCornerBox(player, bounds)
    end
    
    if self.BoxType ~= "2D" and self.BoxType ~= "None" then
        for _, line in ipairs(self.PlayerData[player].Objects.Box2D) do
            line.Visible = false
        end
    end
    
    if self.BoxType ~= "2DCorner" and self.BoxType ~= "None" then
        for _, line in ipairs(self.PlayerData[player].Objects.Box2DCorner) do
            line.Visible = false
        end
    end
    
    if self.BoxType ~= "3D" and self.BoxType ~= "None" then
        for _, line in ipairs(self.PlayerData[player].Objects.Box3D) do
            line.Visible = false
        end
    end
    
    if self.BoxType ~= "3DCorner" and self.BoxType ~= "None" then
        for _, corner in ipairs(self.PlayerData[player].Objects.Box3DCorner) do
            for _, line in ipairs(corner) do
                line.Visible = false
            end
        end
    end
    
    self:UpdateTracer(player, character)
    self:UpdateSkeletonESP(player, character)
end

function ESP:SetColor(color)
    self.Color = color
    
    for player, playerData in pairs(self.PlayerData) do
        for _, line in ipairs(playerData.Objects.Box2D) do
            line.Color = color
        end
        
        for _, line in ipairs(playerData.Objects.Box2DCorner) do
            line.Color = color
        end
        
        for _, line in ipairs(playerData.Objects.Box3D) do
            line.Color = color
        end
        
        for _, corner in ipairs(playerData.Objects.Box3DCorner) do
            for _, line in ipairs(corner) do
                line.Color = color
            end
        end
        
        playerData.Objects.Tracer.Color = color
        
        if playerData.Objects.Skeleton then
            for _, connection in ipairs(playerData.Objects.Skeleton) do
                connection.Line.Color = color
            end
        end
    end
    
    return self
end

function ESP:SetThickness(thickness)
    self.Thickness = thickness
    
    for player, playerData in pairs(self.PlayerData) do
        for _, line in ipairs(playerData.Objects.Box2D) do
            line.Thickness = thickness
        end
        
        for _, line in ipairs(playerData.Objects.Box2DCorner) do
            line.Thickness = thickness
        end
        
        for _, line in ipairs(playerData.Objects.Box3D) do
            line.Thickness = thickness
        end
        
        for _, corner in ipairs(playerData.Objects.Box3DCorner) do
            for _, line in ipairs(corner) do
                line.Thickness = thickness
            end
        end
    end
    
    return self
end

function ESP:SetTracerThickness(thickness)
    self.TracerThickness = thickness
    
    for player, playerData in pairs(self.PlayerData) do
        playerData.Objects.Tracer.Thickness = thickness
    end
    
    return self
end

function ESP:SetTracerOrigin(origin)
    self.TracerOrigin = origin
    return self
end

function ESP:SetCornerSize(size)
    self.CornerSize = size
    return self
end

function ESP:SetTracerTransparency(transparency)
    self.TracerTransparency = transparency
    
    for player, playerData in pairs(self.PlayerData) do
        playerData.Objects.Tracer.Transparency = transparency
    end
    
    return self
end

function ESP:SetTransparency(transparency)
    self.Transparency = transparency
    
    for player, playerData in pairs(self.PlayerData) do
        for _, line in ipairs(playerData.Objects.Box2D) do
            line.Transparency = transparency
        end
        
        for _, line in ipairs(playerData.Objects.Box2DCorner) do
            line.Transparency = transparency
        end
        
        for _, line in ipairs(playerData.Objects.Box3D) do
            line.Transparency = transparency
        end
        
        for _, corner in ipairs(playerData.Objects.Box3DCorner) do
            for _, line in ipairs(corner) do
                line.Transparency = transparency
            end
        end
    end
    
    return self
end

function ESP:SetupUpdate()
    if self.UpdateConnection then
        self.UpdateConnection:Disconnect()
    end
    
    self.UpdateConnection = RunService.RenderStepped:Connect(function()
        if not self.Enabled then return end
        
        for player, _ in pairs(self.PlayerData) do
            self:UpdatePlayerESP(player)
        end
    end)
end

function ESP:Init()
    if self.Initialized then return self end
    
    self:ToggleESP(true)
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            self:CreatePlayerESP(player)
        end
    end
    
    Players.PlayerAdded:Connect(function(player)
        if player ~= LocalPlayer then
            self:CreatePlayerESP(player)
        end
    end)
    
    Players.PlayerRemoving:Connect(function(player)
        self:RemovePlayerESP(player)
    end)
    
    self:SetupUpdate()
    
    self.Initialized = true
    return self
end

function ESP:ToggleESP(enabled)
    self.Enabled = enabled
    
    if not enabled then
        for player, _ in pairs(self.PlayerData) do
            self:HidePlayerESP(player)
        end
    end
    
    return self
end

function ESP:SetBoxType(boxType)
    self.BoxType = boxType

    if boxType == "None" then
        for player, playerData in pairs(self.PlayerData) do
            for _, line in ipairs(playerData.Objects.Box2D) do
                line.Visible = false
            end

            for _, line in ipairs(playerData.Objects.Box2DCorner) do
                line.Visible = false
            end

            for _, line in ipairs(playerData.Objects.Box3D) do
                line.Visible = false
            end

            for _, corner in ipairs(playerData.Objects.Box3DCorner) do
                for _, line in ipairs(corner) do
                    line.Visible = false
                end
            end
        end
    end
    
    for player, _ in pairs(self.PlayerData) do
        self:UpdatePlayerESP(player)
    end
    
    return self
end

function ESP:ToggleTracers(enabled)
    self.TracersEnabled = enabled
    
    if not enabled then
        for player, playerData in pairs(self.PlayerData) do
            playerData.Objects.Tracer.Visible = false
        end
    end
    
    return self
end

function ESP:Destroy()
    if self.UpdateConnection then
        self.UpdateConnection:Disconnect()
        self.UpdateConnection = nil
    end
    
    for player, _ in pairs(self.PlayerData) do
        self:RemovePlayerESP(player)
    end
    
    self.Initialized = false
    self.PlayerData = {}
    
    return self
end

ESP:Init()
ESP:ToggleESP(false)
getgenv().ToggleESP           = function(val)   ESP:ToggleESP(val) end
getgenv().SetBoxType          = function(opt)   ESP:SetBoxType(opt) end
getgenv().ToggleTracers       = function(val)   ESP:ToggleTracers(val) end
getgenv().ToggleSkeleton      = function(val)   ESP:ToggleSkeleton(val) end
getgenv().SetTracerOrigin     = function(opt)   ESP:SetTracerOrigin(opt) end
getgenv().SetThickness        = function(val)   ESP:SetThickness(val) end
getgenv().SetCornerSize       = function(val)   ESP:SetCornerSize(val) end
getgenv().SetColor            = function(col)   ESP:SetColor(col) end
getgenv().SetTransparency     = function(val)   ESP:SetTransparency(val) end
getgenv().SetTracerThickness  = function(val)   ESP:SetTracerThickness(val) end
getgenv().SetSkeletonThickness = function(val)  ESP:SetSkeletonThickness(val) end
getgenv().SetSkeletonTransparency = function(val) ESP:SetSkeletonTransparency(val) end
