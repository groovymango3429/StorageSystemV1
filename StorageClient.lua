-- Place in StarterPlayerScripts

--[[
  StorageClient.lua
  Handles:
    - Inventory GUI (left)
    - Storage GUI (right)
    - Drag & drop inventory <-> storage
    - Opening storage shelves via ProximityPrompt (using StorageId attribute)
    - Syncing with server for all storage actions
    - Inventory GUI updates
    - Storage GUI updates
    - Visual feedback for dragging
    - Close inventory button and ESC/Tab support
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Signal = require(ReplicatedStorage.Modules.Signal)
local player = Players.LocalPlayer

-- GUI references (adjust as needed for your hierarchy)
local playerGui = player:WaitForChild("PlayerGui")
local invF = playerGui:WaitForChild("Storage"):WaitForChild("Inventory")
local itemsSF = invF:WaitForChild("ItemsScroll")
local itemSample = itemsSF:WaitForChild("Sample")

local storageGui = playerGui:WaitForChild("Storage"):WaitForChild("Storage")
local storageSF = storageGui:WaitForChild("ItemsScroll")
local storageSample = storageSF:WaitForChild("Sample")
local stackLabel = storageGui:WaitForChild("StackLabel")
local closeButton = storageGui:WaitForChild("Done")

local currentShelfId = nil
local currentShelfItems = {}
local currentShelfMax = 8
local inventoryData = nil

-- =========================
-- Inventory GUI (Left Side)
-- =========================

function updateInventoryDisplay(invData)
	-- Clear existing
	for _, child in ipairs(itemsSF:GetChildren()) do
		if child:IsA("TextButton") and child ~= itemSample then
			child:Destroy()
		end
	end
	-- Add each stack
	for _, stackData in ipairs(invData.Inventory) do
		local itemF = itemSample:Clone()
		itemF.Name = "Stack-" .. stackData.StackId
		itemF.Visible = true
		itemF.Parent = itemsSF

		-- Set image and count (Image is provided by server)
		itemF.Image.Image = stackData.Image or "rbxassetid://0"
		itemF.ItemCount.Text = tostring(#stackData.Items) .. "x"

		-- Drag-to-storage logic with visual feedback
		itemF.MouseButton1Down:Connect(function()
			local dragFrame = itemF:Clone()
			dragFrame.Parent = playerGui
			dragFrame.Visible = true
			dragFrame.Size = UDim2.fromOffset(itemF.AbsoluteSize.X, itemF.AbsoluteSize.Y)
			dragFrame.ZIndex = 10
			dragFrame.BackgroundTransparency = 0.25
			dragFrame.Position = UDim2.fromOffset(UIS:GetMouseLocation().X, UIS:GetMouseLocation().Y)

			-- Makes the dragFrame follow the mouse while dragging
			local moveConn
			moveConn = RunService.RenderStepped:Connect(function()
				local pos = UIS:GetMouseLocation()
				dragFrame.Position = UDim2.fromOffset(pos.X - dragFrame.AbsoluteSize.X/2, pos.Y - dragFrame.AbsoluteSize.Y/2)
			end)

			local upConn
			upConn = UIS.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					moveConn:Disconnect()
					upConn:Disconnect()
					dragFrame:Destroy()
					-- Naive hit check: if storageGui is open & visible, always transfer
					if currentShelfId and storageGui.Visible then
						Signal.FireServer("Storage:Deposit", currentShelfId, stackData.StackId)
					end
				end
			end)
		end)
	end
end

-- =========================
-- Storage GUI (Right Side)
-- =========================

function updateStorageDisplay()
	for _, child in ipairs(storageSF:GetChildren()) do
		if child:IsA("TextButton") and child ~= storageSample then
			child:Destroy()
		end
	end
	for _, stackData in ipairs(currentShelfItems) do
		local itemF = storageSample:Clone()
		itemF.Name = "Stack-" .. stackData.StackId
		itemF.Image.Image = stackData.Image or "rbxassetid://0"
		itemF.ItemCount.Text = tostring(#stackData.Items) .. "x"
		itemF.Visible = true
		itemF.Parent = storageSF

		-- Drag-to-inventory logic with visual feedback
		itemF.MouseButton1Down:Connect(function()
			local dragFrame = itemF:Clone()
			dragFrame.Parent = playerGui
			dragFrame.Visible = true
			dragFrame.Size = UDim2.fromOffset(itemF.AbsoluteSize.X, itemF.AbsoluteSize.Y)
			dragFrame.ZIndex = 10
			dragFrame.BackgroundTransparency = 0.25
			dragFrame.Position = UDim2.fromOffset(UIS:GetMouseLocation().X, UIS:GetMouseLocation().Y)

			local moveConn
			moveConn = RunService.RenderStepped:Connect(function()
				local pos = UIS:GetMouseLocation()
				dragFrame.Position = UDim2.fromOffset(pos.X - dragFrame.AbsoluteSize.X/2, pos.Y - dragFrame.AbsoluteSize.Y/2)
			end)

			local upConn
			upConn = UIS.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					moveConn:Disconnect()
					upConn:Disconnect()
					dragFrame:Destroy()
					if currentShelfId and storageGui.Visible then
						Signal.FireServer("Storage:Withdraw", currentShelfId, stackData.StackId)
					end
				end
			end)
		end)
	end
	stackLabel.Text = ("%d/%d stacks"):format(#currentShelfItems, currentShelfMax or 8)
end

-- =========================
-- Signal (Remote Event) Handlers
-- =========================

Signal.ListenRemote("Storage:Open", function(storageId, shelfItems, maxStacks)
	currentShelfId = storageId
	currentShelfItems = shelfItems
	currentShelfMax = maxStacks
	storageGui.Visible = true
	invF.Visible = true
	UIS.MouseIconEnabled = true
	UIS.MouseBehavior = Enum.MouseBehavior.Default
	updateStorageDisplay()
end)

Signal.ListenRemote("Storage:Update", function(storageId, shelfItems, maxStacks)
	if storageId ~= currentShelfId then
		return
	end
	currentShelfItems = shelfItems
	currentShelfMax = maxStacks
	updateStorageDisplay()
end)

Signal.ListenRemote("InventoryClient:Update", function(newInvData)
	inventoryData = newInvData
	updateInventoryDisplay(inventoryData)
end)

Signal.ListenRemote("Storage:Error", function(msg)
	warn("[Storage error]: " .. msg)
end)

-- ================ ProximityPrompt Handler (Open shelf by StorageId) ================

local function setupProximityPromptListeners()
	local function connectPrompt(prompt, shelf)
		prompt.Triggered:Connect(function()
			local storageId = shelf:GetAttribute("StorageId")
			if storageId then
				Signal.FireServer("Storage:Open", storageId)
			end
		end)
	end

	local function scanPlot()
		local plotsFolder = workspace:FindFirstChild("Plots")
		if not plotsFolder then
			return
		end
		local plot = plotsFolder:FindFirstChild(player.Name .. "'s Plot")
		if not plot then
			return
		end
		local objects = plot:FindFirstChild("Objects")
		if not objects then
			return
		end

		for _, shelf in ipairs(objects:GetChildren()) do
			local prompt = shelf:FindFirstChildWhichIsA("ProximityPrompt", true)
			if prompt and shelf:GetAttribute("StorageId") then
				connectPrompt(prompt, shelf)
			end
		end
	end

	scanPlot()
	workspace.ChildAdded:Connect(function(child)
		if child.Name == player.Name .. " Plot" then
			child:WaitForChild("Objects")
			scanPlot()
		end
	end)
end

setupProximityPromptListeners()

-- =========================
-- CLOSE INVENTORY FUNCTIONALITY
-- =========================

local function closeInventory()
	storageGui.Visible = false
	invF.Visible = false
	UIS.MouseBehavior = Enum.MouseBehavior.LockCenter -- re-locks the mouse for first-person
	UIS.MouseIconEnabled = false
	currentShelfId = nil
end

closeButton.MouseButton1Click:Connect(closeInventory)

-- Optional: allow pressing ESC or Tab to close inventory
UIS.InputBegan:Connect(function(input, processed)
	if not processed and (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.Tab) then
		if storageGui.Visible or invF.Visible then
			closeInventory()
		end
	end
end)

return true