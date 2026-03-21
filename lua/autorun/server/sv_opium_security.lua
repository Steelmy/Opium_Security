--[[
    Opium Security - Logique Serveur
    Détection d'infractions via les caméras et configuration des notifications par groupe.
]]

OpiumSecurity = OpiumSecurity or {}
OpiumSecurity.Config = OpiumSecurity.Config or {}
OpiumSecurity.GroupNotifyJobs = OpiumSecurity.GroupNotifyJobs or {}
OpiumSecurity.Groups = OpiumSecurity.Groups or {}
OpiumSecurity.DetectionCooldowns = {}

-- ============================================================================
-- NETWORK STRINGS
-- ============================================================================

util.AddNetworkString("opium_group_jobs_request")
util.AddNetworkString("opium_group_jobs_update")
util.AddNetworkString("opium_group_sync")
util.AddNetworkString("opium_group_add_manager")
util.AddNetworkString("opium_group_remove_manager")

-- ============================================================================
-- PERSISTENCE : GROUPES ET JOBS
-- ============================================================================

local DATA_DIR = "opium_security"
local DATA_FILE = DATA_DIR .. "/group_jobs.json"
local GROUPS_FILE = DATA_DIR .. "/groups.json"

--- Charge la configuration des jobs par groupe depuis le fichier
function OpiumSecurity.LoadGroupJobs()
    if not file.Exists(DATA_FILE, "DATA") then
        OpiumSecurity.GroupNotifyJobs = {}
        return
    end

    local raw = file.Read(DATA_FILE, "DATA")
    local data = util.JSONToTable(raw or "")
    OpiumSecurity.GroupNotifyJobs = data or {}
end

--- Sauvegarde la configuration des jobs par groupe
function OpiumSecurity.SaveGroupJobs()
    if not file.IsDir(DATA_DIR, "DATA") then
        file.CreateDir(DATA_DIR)
    end

    file.Write(DATA_FILE, util.TableToJSON(OpiumSecurity.GroupNotifyJobs, true))
end

--- Retourne la liste des team IDs notifiés pour un groupe
function OpiumSecurity.GetGroupJobs(groupID)
    return OpiumSecurity.GroupNotifyJobs[groupID] or {}
end

--- Définit la liste des team IDs notifiés pour un groupe
function OpiumSecurity.SetGroupJobs(groupID, jobTable)
    OpiumSecurity.GroupNotifyJobs[groupID] = jobTable
    OpiumSecurity.SaveGroupJobs()
end

-- Charger au démarrage
OpiumSecurity.LoadGroupJobs()

-- ============================================================================
-- PERSISTENCE : REGISTRE DES GROUPES
-- ============================================================================

--- Charge le registre des groupes depuis le fichier
function OpiumSecurity.LoadGroups()
    if not file.Exists(GROUPS_FILE, "DATA") then
        OpiumSecurity.Groups = {}
        return
    end

    local raw = file.Read(GROUPS_FILE, "DATA")
    local data = util.JSONToTable(raw or "")
    OpiumSecurity.Groups = data or {}
end

--- Sauvegarde le registre des groupes
function OpiumSecurity.SaveGroups()
    if not file.IsDir(DATA_DIR, "DATA") then
        file.CreateDir(DATA_DIR)
    end

    file.Write(GROUPS_FILE, util.TableToJSON(OpiumSecurity.Groups, true))
end

-- Charger au démarrage
OpiumSecurity.LoadGroups()

-- ============================================================================
-- GESTION DES GROUPES
-- ============================================================================

--- Crée un nouveau groupe avec un ID unique
-- @param owner Player Le joueur propriétaire
-- @param displayName string Le nom d'affichage du groupe
-- @return string L'ID unique du groupe
function OpiumSecurity.CreateGroup(owner, displayName)
    local steamID = owner:SteamID64() or "0"
    local groupID = steamID .. "_" .. os.time() .. "_" .. math.random(1000, 9999)

    OpiumSecurity.Groups[groupID] = {
        name = displayName,
        owner = steamID,
        managers = {},
    }

    OpiumSecurity.SaveGroups()
    OpiumSecurity.SyncGroupsToAll()

    return groupID
end

--- Supprime un groupe du registre
-- @param groupID string L'ID du groupe
function OpiumSecurity.DeleteGroup(groupID)
    OpiumSecurity.Groups[groupID] = nil
    OpiumSecurity.GroupNotifyJobs[groupID] = nil
    OpiumSecurity.SaveGroups()
    OpiumSecurity.SaveGroupJobs()
    OpiumSecurity.SyncGroupsToAll()
end

--- Vérifie si un joueur est le propriétaire d'un groupe
function OpiumSecurity.IsGroupOwner(ply, groupID)
    local group = OpiumSecurity.Groups[groupID]
    if not group then return false end
    return group.owner == (ply:SteamID64() or "0")
end

--- Vérifie si un joueur est gestionnaire d'un groupe
function OpiumSecurity.IsGroupManager(ply, groupID)
    local group = OpiumSecurity.Groups[groupID]
    if not group then return false end

    local steamID = ply:SteamID64() or "0"
    for _, managerID in ipairs(group.managers) do
        if managerID == steamID then return true end
    end

    return false
end

--- Vérifie si un joueur peut gérer un groupe (propriétaire, gestionnaire ou admin)
function OpiumSecurity.CanManageGroup(ply, groupID)
    if ply:IsSuperAdmin() then return true end
    return OpiumSecurity.IsGroupOwner(ply, groupID) or OpiumSecurity.IsGroupManager(ply, groupID)
end

--- Ajoute un gestionnaire à un groupe
function OpiumSecurity.AddManager(groupID, steamID64)
    local group = OpiumSecurity.Groups[groupID]
    if not group then return false end

    -- Vérifier qu'il n'est pas déjà manager
    for _, id in ipairs(group.managers) do
        if id == steamID64 then return false end
    end

    table.insert(group.managers, steamID64)
    OpiumSecurity.SaveGroups()
    OpiumSecurity.SyncGroupsToAll()
    return true
end

--- Retire un gestionnaire d'un groupe
function OpiumSecurity.RemoveManager(groupID, steamID64)
    local group = OpiumSecurity.Groups[groupID]
    if not group then return false end

    for i, id in ipairs(group.managers) do
        if id == steamID64 then
            table.remove(group.managers, i)
            OpiumSecurity.SaveGroups()
            OpiumSecurity.SyncGroupsToAll()
            return true
        end
    end

    return false
end

-- ============================================================================
-- SYNCHRONISATION DES GROUPES VERS LES CLIENTS
-- ============================================================================

--- Envoie le registre des groupes à un joueur
function OpiumSecurity.SyncGroupsTo(ply)
    if not IsValid(ply) then return end

    local json = util.TableToJSON(OpiumSecurity.Groups)

    net.Start("opium_group_sync")
        net.WriteUInt(string.len(json), 32)
        net.WriteData(json, string.len(json))
    net.Send(ply)
end

--- Envoie le registre des groupes à tous les joueurs
function OpiumSecurity.SyncGroupsToAll()
    local json = util.TableToJSON(OpiumSecurity.Groups)

    net.Start("opium_group_sync")
        net.WriteUInt(string.len(json), 32)
        net.WriteData(json, string.len(json))
    net.Broadcast()
end

-- Sync au joueur quand il spawn
hook.Add("PlayerInitialSpawn", "OpiumSecurity_SyncGroups", function(ply)
    -- Délai pour s'assurer que le client est prêt
    timer.Simple(2, function()
        if IsValid(ply) then
            OpiumSecurity.SyncGroupsTo(ply)
        end
    end)
end)

-- ============================================================================
-- RÉCEPTION RÉSEAU : GESTION DES MANAGERS
-- ============================================================================

--- Le client demande d'ajouter un gestionnaire
net.Receive("opium_group_add_manager", function(len, ply)
    if not IsValid(ply) then return end

    local groupID = net.ReadString()
    local targetSteamID = net.ReadString()

    -- Vérifier que le joueur est propriétaire du groupe
    if not OpiumSecurity.IsGroupOwner(ply, groupID) and not ply:IsSuperAdmin() then
        ply:ChatPrint("[Opium Security] Seul le propriétaire peut ajouter des gestionnaires.")
        return
    end

    if OpiumSecurity.AddManager(groupID, targetSteamID) then
        local targetName = targetSteamID
        for _, p in ipairs(player.GetAll()) do
            if IsValid(p) and p:SteamID64() == targetSteamID then
                targetName = p:Nick()
                p:ChatPrint("[Opium Security] Vous avez été ajouté comme gestionnaire du groupe \"" .. OpiumSecurity.GetGroupName(groupID) .. "\".")
                break
            end
        end
        ply:ChatPrint("[Opium Security] " .. targetName .. " ajouté comme gestionnaire.")
    else
        ply:ChatPrint("[Opium Security] Ce joueur est déjà gestionnaire ou le groupe n'existe pas.")
    end
end)

--- Le client demande de retirer un gestionnaire
net.Receive("opium_group_remove_manager", function(len, ply)
    if not IsValid(ply) then return end

    local groupID = net.ReadString()
    local targetSteamID = net.ReadString()

    if not OpiumSecurity.IsGroupOwner(ply, groupID) and not ply:IsSuperAdmin() then
        ply:ChatPrint("[Opium Security] Seul le propriétaire peut retirer des gestionnaires.")
        return
    end

    if OpiumSecurity.RemoveManager(groupID, targetSteamID) then
        ply:ChatPrint("[Opium Security] Gestionnaire retiré.")
    else
        ply:ChatPrint("[Opium Security] Ce joueur n'est pas gestionnaire de ce groupe.")
    end
end)

-- ============================================================================
-- RÉCEPTION RÉSEAU : CONFIGURATION DES JOBS
-- ============================================================================

--- Le client demande la config d'un groupe
net.Receive("opium_group_jobs_request", function(len, ply)
    if not IsValid(ply) then return end

    local groupName = net.ReadString()
    local jobs = OpiumSecurity.GetGroupJobs(groupName)

    net.Start("opium_group_jobs_update")
        net.WriteString(groupName)
        net.WriteUInt(#jobs, 8)
        for _, jobID in ipairs(jobs) do
            net.WriteInt(jobID, 16)
        end
    net.Send(ply)
end)

--- Le client envoie une nouvelle config pour un groupe
net.Receive("opium_group_jobs_update", function(len, ply)
    if not IsValid(ply) then return end

    local groupID = net.ReadString()
    local count = net.ReadUInt(8)
    local jobs = {}

    for i = 1, count do
        local jobID = net.ReadInt(16)
        table.insert(jobs, jobID)
    end

    -- Vérification : propriétaire, gestionnaire ou admin
    if not OpiumSecurity.CanManageGroup(ply, groupID) then
        ply:ChatPrint("[Opium Security] Vous n'avez pas les droits pour configurer ce groupe.")
        return
    end

    OpiumSecurity.SetGroupJobs(groupID, jobs)
    local displayName = OpiumSecurity.GetGroupName(groupID)
    ply:ChatPrint("[Opium Security] Configuration des alertes pour \"" .. displayName .. "\" sauvegardée (" .. count .. " jobs).")
end)

-- ============================================================================
-- DÉTECTION D'INFRACTIONS : EntityTakeDamage
-- ============================================================================

hook.Add("EntityTakeDamage", "OpiumSecurity_DetectInfraction", function(target, dmgInfo)
    local attacker = dmgInfo:GetAttacker()

    -- Uniquement dégâts joueur -> joueur
    if not IsValid(attacker) or not attacker:IsPlayer() then return end
    if not IsValid(target) or not target:IsPlayer() then return end
    if attacker == target then return end

    -- Cooldown par attaquant
    local steamID = attacker:SteamID64()
    local now = CurTime()

    if OpiumSecurity.DetectionCooldowns[steamID] and OpiumSecurity.DetectionCooldowns[steamID] > now then
        return
    end

    -- Vérifier si une caméra voit l'attaquant
    local attackerPos = attacker:GetPos() + Vector(0, 0, 40)
    local cfg = OpiumSecurity.Config
    local detectionRadius = cfg.DetectionRadius or 1500

    for _, cam in ipairs(ents.FindByClass("ent_security_cam")) do
        if not IsValid(cam) or not cam:GetCamActive() then continue end

        local camPos = cam:GetPos() + cam:GetForward() * 5 + cam:GetUp() * 5
        local camAng = cam:GetAngles()
        local dist = camPos:Distance(attackerPos)

        if dist > detectionRadius then continue end
        if not OpiumSecurity.IsInCameraFOV(camPos, camAng, attackerPos) then continue end
        if not OpiumSecurity.HasLineOfSight(camPos, attackerPos, cam) then continue end

        -- La caméra a vu l'infraction
        OpiumSecurity.DetectionCooldowns[steamID] = now + (cfg.DetectionCooldown or 10)

        -- Déterminer les jobs à notifier
        local groupID = cam:GetCamGroup()
        local notifyJobs = {}

        if groupID and groupID ~= "" then
            notifyJobs = OpiumSecurity.GetGroupJobs(groupID)
        end

        -- Fallback sur les PoliceTeams si aucun job configuré
        if #notifyJobs == 0 then
            notifyJobs = cfg.PoliceTeams or {}
        end

        -- Trouver les destinataires
        local recipients = {}
        for _, ply in ipairs(player.GetAll()) do
            if not IsValid(ply) then continue end

            for _, jobTeam in ipairs(notifyJobs) do
                if ply:Team() == jobTeam then
                    table.insert(recipients, ply)
                    break
                end
            end
        end

        -- Aussi notifier le joueur qui regarde cette caméra
        local camUser = cam:GetCamUser()
        if IsValid(camUser) and not table.HasValue(recipients, camUser) then
            table.insert(recipients, camUser)
        end

        if #recipients > 0 then
            local rpName = attacker:Nick()
            if attacker.getDarkRPVar then
                rpName = attacker:getDarkRPVar("rpname") or rpName
            end

            local reason = cfg.WantedReason or "Agression détectée par caméra"

            net.Start("opium_camera_notify")
                net.WriteString(rpName)
                net.WriteString(reason)
                net.WriteString(cam:GetCamName())
                net.WriteEntity(attacker)
            net.Send(recipients)
        end

        break -- Une seule notification par événement de dégâts
    end
end)

-- ============================================================================
-- NETTOYAGE PÉRIODIQUE DES COOLDOWNS
-- ============================================================================

timer.Create("OpiumSecurity_CleanCooldowns", 60, 0, function()
    local now = CurTime()
    for id, expire in pairs(OpiumSecurity.DetectionCooldowns) do
        if expire < now then
            OpiumSecurity.DetectionCooldowns[id] = nil
        end
    end
end)
