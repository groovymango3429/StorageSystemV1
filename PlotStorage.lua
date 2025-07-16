local playersRemaining = Instance.new("NumberValue")
local PlotManager = require(script.Parent.PlotManager)
local PlotSpawnPool = require(script.Parent.PlotSpawnPool)
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlotStore = DataStoreService:GetDataStore("PlotStore")
local placeableObjects = ReplicatedStorage.PlaceableObjects
local ServerStorage = game:GetService("ServerStorage")
local ToolTemplates = ServerStorage:WaitForChild("AllItems")

local ServerScriptService = game:GetService("ServerScriptService")
local ShelfData = require(ServerScriptService.StorageServer)

type ObjectInfo = {
	Name: string,
	Cf: {number},
	StorageId: string?, -- for storage objects
	StorageItems: table?, -- for storage bins
}

-- Recursively copy and sanitize all item fields needed for gameplay (Name, StackId, Count, Type, etc)
local function deepSanitize(value)
	local t = type(value)
	if t == "string" or t == "number" or t == "boolean" or t == "nil" then
		return value
	elseif t == "table" then
		local out = {}
		for k, v in pairs(value) do
			if type(k) == "string" or type(k) == "number" then
				out[k] = deepSanitize(v)
			end
		end
		return out
	else
		return nil -- strip out functions, instances, userdata, etc
	end
end

-- Save enough to reconstruct tools/items (add fields as needed)
local function sanitizeStack(stack)
	return {
		Name = stack.Name,
		StackId = stack.StackId,
		Count = stack.Count or (stack.Items and #stack.Items or 1),
		Type = stack.Type,
		-- Add more fields if your items need them!
		Items = stack.Items and deepSanitize(stack.Items) or nil, -- optional, if you need per-item info
	}
end

local function sanitizeShelfItems(items)
	local sanitized = {}
	for i, stack in ipairs(items) do
		sanitized[i] = sanitizeStack(stack)
	end
	return sanitized
end

local function serializePlot(plot: Model)
	local data = {}
	for _, object in plot.Objects:GetChildren() do
		local objectCF = plot:GetPivot():ToObjectSpace(object:GetPivot())
		local info: ObjectInfo = {
			Name = object.Name,
			Cf = table.pack(objectCF:GetComponents())
		}
		local storageId = object:GetAttribute("StorageId")
		if storageId then
			info.StorageId = storageId
			local storageData = ShelfData and ShelfData[storageId]
			if storageData and storageData.Items then
				info.StorageItems = sanitizeShelfItems(storageData.Items)
			end
		end
		table.insert(data, info)
	end
	return data
end

local PlotStorage = {}

function PlotStorage.Load(player: Player) 
	local success, data: {ObjectInfo} = pcall(function()
		return PlotStore:GetAsync(player.UserId)
	end)

	if not success then 
		warn(data)
		playersRemaining.Value += 1
		return 
	end
	if not Players:GetPlayerByUserId(player.UserId) then 
		return
	end

	local plot = PlotManager.SpawnPlot(player)
	if data then 
		for _, objectInfo in data do 
			local object = placeableObjects[objectInfo.Name]:Clone()
			local relativeCf = CFrame.new(table.unpack(objectInfo.Cf))
			object:PivotTo(plot:GetPivot():ToWorldSpace(relativeCf))
			if objectInfo.StorageId then
				object:SetAttribute("StorageId", objectInfo.StorageId)
				-- Restore shelf contents
				if objectInfo.StorageItems then
					ShelfData[objectInfo.StorageId] = {
						Items = deepSanitize(objectInfo.StorageItems),
						MaxStacks = 8,
						Owner = player,
						ShelfInstance = object,
					}
				else
					ShelfData[objectInfo.StorageId] = {
						Items = {},
						MaxStacks = 8,
						Owner = player,
						ShelfInstance = object,
					}
				end
			end
			object.Parent = plot.Objects 
		end
	end

	playersRemaining.Value += 1
end

function PlotStorage.Save(player: Player)
	local plot = PlotManager.GetPlot(player)
	if not plot or not plot:IsDescendantOf(workspace) then 
		playersRemaining.Value -= 1
		return 
	end

	local data = serializePlot(plot)

	-- Debug: Test serializability before saving
	local HttpService = game:GetService("HttpService")
	local ok, jsonOrErr = pcall(function()
		return HttpService:JSONEncode(data)
	end)
	if not ok then
		warn("[PlotStorage][Serialization ERROR]", jsonOrErr)
		warn("[PlotStorage][DATA]", data)
		playersRemaining.Value -= 1
		return
	end

	plot:Destroy()
	PlotSpawnPool.Return(player)

	local success, errMsg = pcall(function()
		PlotStore:SetAsync(player.UserId, data)
	end)

	if not success then 
		warn(errMsg)
	end

	playersRemaining.Value -= 1
end

function PlotStorage.WaitForSave()
	while playersRemaining.Value > 0 do
		playersRemaining.Changed:Wait()
	end
end

-- Handler: Withdraw an item from storage bin
-- Call this function when a player wants to take an item out of storage
function PlotStorage.WithdrawItem(player, storageId, stackIndex)
	local shelf = ShelfData[storageId]
	if not shelf or not shelf.Items or not shelf.Items[stackIndex] then return end

	local stack = shelf.Items[stackIndex]
	local toolName = stack.Name
	if not toolName then return end

	-- Find the tool template
	local toolTemplate = ToolTemplates and ToolTemplates:FindFirstChild(toolName)
	if toolTemplate then
		local toolClone = toolTemplate:Clone()
		toolClone.Parent = player.Backpack
	else
		warn("No tool template found for", toolName)
	end

	-- Decrement count (or remove stack if empty)
	stack.Count = (stack.Count or 1) - 1
	if stack.Count <= 0 then
		table.remove(shelf.Items, stackIndex)
	end

	-- Optionally, update the client about storage change here (e.g., via RemoteEvent)
end

return PlotStorage