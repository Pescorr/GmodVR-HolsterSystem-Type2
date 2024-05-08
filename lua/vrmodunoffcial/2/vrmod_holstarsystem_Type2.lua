AddCSLuaFile()
if SERVER then return end
local convars, convarValues = vrmod.GetConvars()
local pouch_slots = 5
local pouch_weapons = {}
local pouch_positions = {}
local pouch_initial_positions = {}
local pouch_sizes = {}
local pouch_enabled = CreateClientConVar("vrmod_pouch_enabled", 1, true, FCVAR_ARCHIVE, nil, 0, 1) -- 新しく追加したconvar
local pouch_visible_name = CreateClientConVar("vrmod_pouch_visiblename", 1, true, FCVAR_ARCHIVE, nil, 0, 1)
--local pouch_leftwepenable = CreateClientConVar("vrmod_pouch_leftweapon_enable", 1, true, FCVAR_ARCHIVE, nil, 0, 1)
local pouch_visible_hud = CreateClientConVar("vrmod_pouch_visiblename_hud", 1, true, FCVAR_ARCHIVE, nil, 0, 1)
--local pouch_entitymode = CreateClientConVar("vrmod_pouch_entitymode_enable", 1, true, FCVAR_ARCHIVE, nil, 0, 1)
local pouch_saved_positions = {}
local pouch_locked = {}
-- local pouch_enter_sound = CreateClientConVar("vrmod_pouch_enter_sound", "common/wpn_moveselect.wav", true, FCVAR_ARCHIVE)
local pouch_pickup_sound = CreateClientConVar("vrmod_pouch_pickup_sound", "common/wpn_select.wav", true, FCVAR_ARCHIVE)
for i = 1, pouch_slots do
    CreateClientConVar("vrmod_pouch_weapon_" .. i, "", true, FCVAR_ARCHIVE)
    CreateClientConVar("vrmod_pouch_size_" .. i, 12, true, FCVAR_ARCHIVE) -- 新しく追加したconvar
    pouch_locked[i] = false
end

-- ConVarの値が変更されたことを検知するフックを追加
for i = 1, pouch_slots do
    cvars.AddChangeCallback(
        "vrmod_pouch_size_" .. i,
        function(convar_name, value_old, value_new)
            pouch_sizes[i] = tonumber(value_new)
        end, "vrmod_pouch_size_callback"
    )
end

for i = 1, pouch_slots do
    pouch_positions[i] = Vector(0, 0, 0)
    pouch_initial_positions[i] = Vector(0, 0, 0)
    pouch_sizes[i] = GetConVar("vrmod_pouch_size_" .. i):GetFloat() -- convarから値を取得するように変更
end

hook.Add(
    "VRMod_Tracking",
    "vrmod_holster_follow_player",
    function()
        if not pouch_enabled:GetBool() then return end -- ホルスター機能が無効の場合は処理を行わない
        local ply = LocalPlayer()
        if not g_VR.active then return end
        if not g_VR.threePoints then return end
        if ply:GetBonePosition(ply:LookupBone("ValveBiped.Bip01_Spine")) == nil then return end
        if ply:GetBonePosition(ply:LookupBone("ValveBiped.Bip01_Pelvis")) == nil then return end
        if not g_VR.tracking.hmd then return end
        local headPos, headAng = g_VR.tracking.hmd.pos, g_VR.tracking.hmd.ang
        local chestPos, chestAng = ply:GetBonePosition(ply:LookupBone("ValveBiped.Bip01_Spine"))
        local hipPos, hipAng = ply:GetBonePosition(ply:LookupBone("ValveBiped.Bip01_Pelvis"))
        pouch_positions[1] = headPos + (headAng:Right() * 7)
        pouch_positions[2] = headPos - (headAng:Right() * 7)
        pouch_positions[3] = chestPos + (headAng:Right() * 10)
        pouch_positions[4] = chestPos - (headAng:Right() * 10)
        pouch_positions[5] = hipPos - (hipAng:Right() * 16)
    end
)

hook.Add(
    "VRMod_Input",
    "vrutil_hook_pouchinput",
    function(action, pressed)
        if not g_VR.active then return end
        if not pouch_enabled:GetBool() then return end -- ホルスター機能が無効の場合は処理を行わない
        local function storeWeapon(leftHand)
            for i = 1, pouch_slots do
                if pouch_locked[i] then continue end
                local hand_pos = leftHand and g_VR.tracking.pose_lefthand.pos or g_VR.tracking.pose_righthand.pos
                if hand_pos:DistToSqr(pouch_positions[i]) < (pouch_sizes[i] * pouch_sizes[i]) then
                    local heldEntity = leftHand and g_VR.heldEntityLeft or g_VR.heldEntityRight
                    if IsValid(heldEntity) then
                        LocalPlayer():ConCommand("vrmod_pouch_weapon_" .. i .. " " .. heldEntity:GetClass())
                        heldEntity:Remove() -- エンティティを消去
                        if leftHand then
                            g_VR.heldEntityLeft = nil
                        else
                            g_VR.heldEntityRight = nil
                        end

                        return
                    end

                    local activeWeapon = LocalPlayer():GetActiveWeapon()
                    if IsValid(activeWeapon) and activeWeapon:GetClass() ~= "weapon_vrmod_empty" and ((leftHand and GetConVar("vrmod_lefthand"):GetBool()) or (not leftHand and not GetConVar("vrmod_lefthand"):GetBool())) then
                        LocalPlayer():ConCommand("vrmod_pouch_weapon_" .. i .. " " .. activeWeapon:GetClass())
                        LocalPlayer():ConCommand("use weapon_vrmod_empty")

                        return
                    end

                    break
                end
            end
        end

        local function equipWeaponOrEntity(leftHand)
            if not pouch_enabled:GetBool() then return end -- ホルスター機能が無効の場合は処理を行わない
            if not g_VR.active then return end
            for i = 1, pouch_slots do
                local hand_pos = leftHand and g_VR.tracking.pose_lefthand.pos or g_VR.tracking.pose_righthand.pos
                if hand_pos:DistToSqr(pouch_positions[i]) < (pouch_sizes[i] * pouch_sizes[i]) then
                    local wepclass = GetConVar("vrmod_pouch_weapon_" .. i):GetString()
                    if wepclass ~= "" then
                        if weapons.Get(wepclass) then
                            LocalPlayer():ConCommand("use " .. wepclass)
                            LocalPlayer():ConCommand("vrmod_lefthand " .. (leftHand and "1" or "0"))
                            surface.PlaySound(pouch_pickup_sound:GetString())
                        else
                            net.Start("vrmod_test_spawn_entity")
                            net.WriteString(wepclass)
                            net.WriteVector(hand_pos)
                            net.WriteAngle(leftHand and g_VR.tracking.pose_lefthand.ang or g_VR.tracking.pose_righthand.ang)
                            net.WriteBool(leftHand)
                            net.SendToServer()
                            surface.PlaySound(pouch_pickup_sound:GetString())
                        end
                    end

                    break
                end
            end
        end

        if action == "boolean_left_pickup" and not pressed then
            storeWeapon(true)
        elseif action == "boolean_right_pickup" and not pressed then
            storeWeapon(false)
        end

        if action == "boolean_left_pickup" and pressed then
            equipWeaponOrEntity(true)
        elseif action == "boolean_right_pickup" and pressed then
            equipWeaponOrEntity(false)
        end

        if action == "boolean_use" and pressed then
            for i = 1, pouch_slots do
                if g_VR.tracking.pose_lefthand.pos:DistToSqr(pouch_positions[i]) < (pouch_sizes[i] * pouch_sizes[i]) then
                    pouch_locked[i] = not pouch_locked[i]
                    break
                end

                if g_VR.tracking.pose_righthand.pos:DistToSqr(pouch_positions[i]) < (pouch_sizes[i] * pouch_sizes[i]) then
                    pouch_locked[i] = not pouch_locked[i]
                    break
                end
            end
        end
    end
)

hook.Add(
    "HUDPaint",
    "vrmod_holstarsystem_left_hudpaint",
    function()
        if not pouch_enabled:GetBool() then return end -- ホルスター機能が無効の場合は処理を行わない
        if not pouch_visible_hud:GetBool() then return end
        if not g_VR.active then return end
        for i = 1, pouch_slots do
            if g_VR.tracking.pose_lefthand.pos:DistToSqr(pouch_positions[i]) < (pouch_sizes[i] * pouch_sizes[i]) then
                local text = GetConVar("vrmod_pouch_weapon_" .. i):GetString()
                if text ~= "" then
                    if pouch_locked[i] then
                        text = "＊" .. text .. "＊" -- ロックされている場合は文字列の始まりと終わりに「＊」をつける
                    end

                    draw.SimpleText(text, "DermaLarge", ScrW() * 0.05, ScrH() * 0.9, Color(255, 255, 0, 200), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end

                if not IsValid(ply) then return end
                -- surface.PlaySound(pouch_enter_sound:GetString())
                break
            end
        end
    end
)

hook.Add(
    "HUDPaint",
    "vrmod_holstarsystem_right_hudpaint",
    function()
        if not pouch_enabled:GetBool() then return end -- ホルスター機能が無効の場合は処理を行わない
        if not pouch_visible_hud:GetBool() then return end
        if not g_VR.active then return end
        for i = 1, pouch_slots do
            if g_VR.tracking.pose_righthand.pos:DistToSqr(pouch_positions[i]) < (pouch_sizes[i] * pouch_sizes[i]) then
                local text = GetConVar("vrmod_pouch_weapon_" .. i):GetString()
                if text ~= "" then
                    if pouch_locked[i] then
                        text = "＊" .. text .. "＊" -- ロックされている場合は文字列の始まりと終わりに「＊」をつける
                    end

                    draw.SimpleText(text, "DermaLarge", ScrW() * 0.95, ScrH() * 0.9, Color(255, 255, 0, 200), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                end

                if not IsValid(ply) then return end
                -- surface.PlaySound(pouch_enter_sound:GetString())
                break
            end
        end
    end
)

hook.Add(
    "PostDrawTranslucentRenderables",
    "vrmod_holstarsystem_draw",
    function(depth, sky)
        if not pouch_enabled:GetBool() then return end -- ホルスター機能が無効の場合は処理を行わない
        if not pouch_visible_name:GetBool() then return end
        if not g_VR.threePoints or EyePos() ~= g_VR.view.origin then return end
        for i = 1, pouch_slots do
            local pos = pouch_positions[i]
            local size = pouch_sizes[i]
            render.SetColorMaterial()
            local color = pouch_locked[i] and Color(146, 253, 110, 80) or Color(255, 255, 255, 128)
            render.DrawSphere(pos, size, 16, 50, color)
            local entClass = GetConVar("vrmod_pouch_weapon_" .. i):GetString()
            if entClass ~= "" then
                local eyeAng = EyeAngles()
                eyeAng:RotateAroundAxis(eyeAng:Right(), 90)
                cam.Start3D2D(pos, eyeAng, 0.1)
                draw.SimpleText(entClass, "CloseCaption_Normal", 0, 0, Color(108, 81, 0), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                cam.End3D2D()
            end
        end
    end
)

if SERVER then
    util.AddNetworkString("vrmod_test_spawn_entity")
    net.Receive(
        "vrmod_test_spawn_entity",
        function(len, ply)
            local entClass = net.ReadString()
            local handPos = net.ReadVector()
            local handAng = net.ReadAngle()
            local isLeftHand = net.ReadBool()
            local spawnedEnt = ents.Create(entClass)
            if not IsValid(spawnedEnt) then return end
            local function followAndTryPickup()
                if not IsValid(spawnedEnt) then return end
                spawnedEnt:Spawn()
                spawnedEnt:SetPos(handPos)
                spawnedEnt:SetAngles(handAng - Angle(4.9, 4, -3.5))
                if IsValid(spawnedEnt) then
                    pickup(ply, isLeftHand, spawnedEnt:GetPos(), spawnedEnt:GetAngles())
                    timer.Remove(ply:UserID() .. "followAndTryPickup")
                end
            end

            timer.Create(ply:UserID() .. "followAndTryPickup", 0.01, 0, followAndTryPickup)
        end
    )
end