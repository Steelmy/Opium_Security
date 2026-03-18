--[[
    Opium Security - Logique Serveur
    Détection d'infractions via les caméras et configuration des notifications par groupe.
]]

OpiumSecurity = OpiumSecurity or {}
OpiumSecurity.Config = OpiumSecurity.Config or {}
OpiumSecurity.GroupNotifyJobs = OpiumSecurity.GroupNotifyJobs or {}
OpiumSecurity.DetectionCooldowns = {}

-- ============================================================================
-- NETWORK STRINGS
-- ============================================================================

util.AddNetworkString("opium_group_jobs_request")
util.AddNetworkString("opium_group_jobs_update")

-- ============================================================================
-- PERSISTENCE : JOBS PAR GROUPE
-- ============================================================================

local DATA_DIR = "opium_security"
local DATA_FILE = DATA_DIR .. "/group_jobs.json"

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
function OpiumSecurity.GetGroupJobs(groupName)
    return OpiumSecurity.GroupNotifyJobs[groupName] or {}
end

--- Définit la liste des team IDs notifiés pour un groupe
function OpiumSecurity.SetGroupJobs(groupName, jobTable)
    OpiumSecurity.GroupNotifyJobs[groupName] = jobTable
    OpiumSecurity.SaveGroupJobs()
end

-- Charger au démarrage
OpiumSecurity.LoadGroupJobs()

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

    -- Vérification admin
    if not ply:IsAdmin() and not ply:IsSuperAdmin() then
        ply:ChatPrint("[Opium Security] Vous devez être admin pour configurer les alertes.")
        return
    end

    local groupName = net.ReadString()
    local count = net.ReadUInt(8)
    local jobs = {}

    for i = 1, count do
        local jobID = net.ReadInt(16)
        table.insert(jobs, jobID)
    end

    OpiumSecurity.SetGroupJobs(groupName, jobs)
    ply:ChatPrint("[Opium Security] Configuration des alertes pour \"" .. groupName .. "\" sauvegardée (" .. count .. " jobs).")
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
        local groupName = cam:GetCamGroup()
        local notifyJobs = {}

        if groupName and groupName ~= "" then
            notifyJobs = OpiumSecurity.GetGroupJobs(groupName)
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
