--[[
    Opium Security - Logique Serveur
    Gère la détection d'infractions, les notifications police,
    et le système d'avis de recherche.
]]

-- Chargement de la config partagée (déjà chargée via autorun, mais sécurité)
include("sh_opium_config.lua")

-- ============================================================================
-- INITIALISATION RÉSEAU
-- ============================================================================

util.AddNetworkString("opium_camera_open")      -- Serveur -> Client : ouvrir l'interface caméra
util.AddNetworkString("opium_camera_exit")       -- Bidirectionnel : quitter la vue caméra
util.AddNetworkString("opium_camera_switch")     -- Client -> Serveur : changer de caméra
util.AddNetworkString("opium_camera_notify")     -- Serveur -> Client : notification d'infraction
util.AddNetworkString("opium_camera_wanted")     -- Client -> Serveur : déclarer recherché manuellement
util.AddNetworkString("opium_camera_viewdata")   -- Serveur -> Client : données de vue caméra

-- Table des caméras actives (remplie par les entités)
OpiumSecurity.Cameras = OpiumSecurity.Cameras or {}

-- Cooldowns de détection par joueur (SteamID -> timestamp)
local detectionCooldowns = {}

-- ============================================================================
-- DÉTECTION D'INFRACTIONS
-- ============================================================================

--- Vérifie si un joueur est visible par au moins une caméra active
-- @param ply Player Le joueur à vérifier
-- @return boolean, Entity (true + la caméra qui le voit, ou false)
local function IsPlayerSeenByCamera(ply)
    if not IsValid(ply) then return false, nil end

    local plyPos = ply:GetPos() + Vector(0, 0, 40) -- Centre du joueur

    for _, cam in ipairs(OpiumSecurity.Cameras or {}) do
        if IsValid(cam) and cam:GetCamActive() then
            local camPos = cam:GetViewPos and cam:GetViewPos() or cam:GetPos()
            local camAng = cam:GetViewAngle and cam:GetViewAngle() or cam:GetAngles()
            local dist = camPos:Distance(plyPos)

            -- Vérifier la distance
            if dist <= OpiumSecurity.Config.DetectionRadius then
                -- Vérifier le champ de vision
                if OpiumSecurity.IsInCameraFOV(camPos, camAng, plyPos) then
                    -- Vérifier la ligne de vue
                    if OpiumSecurity.HasLineOfSight(camPos, plyPos, cam) then
                        return true, cam
                    end
                end
            end
        end
    end

    return false, nil
end

--- Envoie une notification à tous les policiers
-- @param attacker Player L'agresseur
-- @param camera Entity La caméra qui a détecté l'agression
local function NotifyPolice(attacker, camera)
    local camName = IsValid(camera) and camera:GetCamName() or "Caméra inconnue"
    local attackerName = attacker:Nick()

    -- Chercher le nom RP si DarkRP est installé
    if attacker.rpname then
        attackerName = attacker:rpname()
    elseif attacker.getDarkRPVar then
        local rpName = attacker:getDarkRPVar("rpname")
        if rpName then attackerName = rpName end
    end

    for _, ply in ipairs(player.GetAll()) do
        if OpiumSecurity.IsPolice(ply) then
            net.Start("opium_camera_notify")
                net.WriteString(attackerName)
                net.WriteString(OpiumSecurity.Config.WantedReason)
                net.WriteString(camName)
                net.WriteEntity(attacker)
            net.Send(ply)
        end
    end
end

--- Marque un joueur comme recherché
-- @param target Player Le joueur à marquer
-- @param reason string La raison
local function SetPlayerWanted(target, reason)
    if not IsValid(target) then return end

    -- Utiliser le système Wanted de DarkRP si disponible
    if target.wanted and target.setDarkRPVar then
        target:setDarkRPVar("wanted", true)
        target:setDarkRPVar("wantedReason", reason)

        -- Retirer le statut après la durée configurée
        timer.Create("opium_unwanted_" .. target:SteamID(), OpiumSecurity.Config.WantedDuration, 1, function()
            if IsValid(target) and target.setDarkRPVar then
                target:setDarkRPVar("wanted", false)
                target:setDarkRPVar("wantedReason", "")
            end
        end)
    else
        -- Fallback : utiliser une variable réseau custom
        target:SetNWBool("opium_wanted", true)
        target:SetNWString("opium_wanted_reason", reason)

        timer.Create("opium_unwanted_" .. target:SteamID(), OpiumSecurity.Config.WantedDuration, 1, function()
            if IsValid(target) then
                target:SetNWBool("opium_wanted", false)
                target:SetNWString("opium_wanted_reason", "")
            end
        end)
    end
end

-- Hook : Détection des agressions
hook.Add("EntityTakeDamage", "OpiumSecurity_DetectAggression", function(victim, dmgInfo)
    local attacker = dmgInfo:GetAttacker()

    -- Vérifier que l'attaquant et la victime sont des joueurs
    if not IsValid(attacker) or not attacker:IsPlayer() then return end
    if not IsValid(victim) or not victim:IsPlayer() then return end

    -- Ne pas détecter les dégâts entre policiers (friendly fire ignoré)
    if OpiumSecurity.IsPolice(attacker) and OpiumSecurity.IsPolice(victim) then return end

    -- Vérifier le cooldown
    local steamID = attacker:SteamID()
    local now = CurTime()
    if detectionCooldowns[steamID] and (now - detectionCooldowns[steamID]) < OpiumSecurity.Config.DetectionCooldown then
        return
    end

    -- Vérifier si l'attaquant est vu par une caméra
    local seen, camera = IsPlayerSeenByCamera(attacker)
    if seen then
        detectionCooldowns[steamID] = now

        -- Notifier la police
        NotifyPolice(attacker, camera)

        -- Marquer comme recherché
        SetPlayerWanted(attacker, OpiumSecurity.Config.WantedReason)

        -- Log dans la console serveur
        print("[Opium Security] " .. attacker:Nick() .. " détecté en agression par " .. camera:GetCamName())
    end
end)

-- ============================================================================
-- RÉCEPTION RÉSEAU
-- ============================================================================

-- Le joueur quitte la vue caméra
net.Receive("opium_camera_exit", function(len, ply)
    -- Libérer toutes les caméras utilisées par ce joueur
    for _, cam in ipairs(OpiumSecurity.Cameras or {}) do
        if IsValid(cam) and cam:GetCamUser() == ply then
            cam:SetCamUser(NULL)
        end
    end
end)

-- Le joueur change de caméra (next/previous)
net.Receive("opium_camera_switch", function(len, ply)
    local direction = net.ReadInt(8) -- 1 = next, -1 = previous
    local currentCam = net.ReadEntity()

    -- Libérer la caméra actuelle
    if IsValid(currentCam) then
        currentCam:SetCamUser(NULL)
    end

    -- Trouver la caméra suivante/précédente
    local cameras = {}
    for _, cam in ipairs(OpiumSecurity.Cameras or {}) do
        if IsValid(cam) and cam:GetCamActive() then
            table.insert(cameras, cam)
        end
    end

    if #cameras == 0 then
        net.Start("opium_camera_exit")
        net.Send(ply)
        return
    end

    -- Trouver l'index actuel
    local currentIndex = 1
    for i, cam in ipairs(cameras) do
        if cam == currentCam then
            currentIndex = i
            break
        end
    end

    -- Calculer le nouvel index
    local newIndex = currentIndex + direction
    if newIndex > #cameras then newIndex = 1 end
    if newIndex < 1 then newIndex = #cameras end

    local newCam = cameras[newIndex]
    newCam:SetCamUser(ply)

    -- Envoyer la nouvelle caméra au client
    net.Start("opium_camera_open")
        net.WriteEntity(newCam)
    net.Send(ply)
end)

-- Le joueur déclare manuellement un joueur recherché
net.Receive("opium_camera_wanted", function(len, ply)
    -- Vérifier que le joueur est bien policier
    if not OpiumSecurity.IsPolice(ply) then
        ply:ChatPrint("[Opium Security] Vous n'avez pas l'autorité pour déclarer quelqu'un recherché.")
        return
    end

    local target = net.ReadEntity()
    if not IsValid(target) or not target:IsPlayer() then return end

    local reason = net.ReadString()
    if reason == "" then reason = "Déclaré recherché par la police" end

    SetPlayerWanted(target, reason)

    -- Notifier le joueur qui a fait la demande
    ply:ChatPrint("[Opium Security] " .. target:Nick() .. " a été déclaré recherché.")

    -- Notifier la cible
    target:ChatPrint("[Opium Security] Vous avez été déclaré recherché : " .. reason)
end)

-- ============================================================================
-- NETTOYAGE
-- ============================================================================

-- Nettoyer quand un joueur se déconnecte
hook.Add("PlayerDisconnected", "OpiumSecurity_Cleanup", function(ply)
    local steamID = ply:SteamID()
    detectionCooldowns[steamID] = nil

    -- Libérer les caméras
    for _, cam in ipairs(OpiumSecurity.Cameras or {}) do
        if IsValid(cam) and cam:GetCamUser() == ply then
            cam:SetCamUser(NULL)
        end
    end

    -- Nettoyer le timer wanted
    timer.Remove("opium_unwanted_" .. steamID)
end)
