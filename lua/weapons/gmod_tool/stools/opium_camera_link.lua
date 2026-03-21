--[[
    Opium Security - Tool Gun : Liaison de Caméras
    Permet de relier des caméras et moniteurs en groupes via le Tool Gun.
    Système d'ID unique avec propriétaire et gestionnaires.
    - Clic gauche : ajouter une caméra/moniteur au groupe en cours
    - Clic droit : retirer une caméra/moniteur de son groupe
    - Rechargement : finaliser le groupe et en commencer un nouveau
]]

TOOL.Category    = "Opium Security"
TOOL.Name        = "#tool.opium_camera_link.name"
TOOL.Command     = nil
TOOL.ConfigName  = ""

TOOL.ClientConVar["group"] = ""
TOOL.ClientConVar["groupid"] = ""

TOOL.Information = {
    { name = "left" },
    { name = "right" },
    { name = "reload" },
}

if CLIENT then
    language.Add("tool.opium_camera_link.name", "Liaison Caméras")
    language.Add("tool.opium_camera_link.desc", "Relie les caméras et moniteurs de sécurité en groupes de vidéosurveillance")
    language.Add("tool.opium_camera_link.left", "Ajouter la caméra ou le moniteur au groupe actuel")
    language.Add("tool.opium_camera_link.right", "Retirer la caméra ou le moniteur de son groupe")
    language.Add("tool.opium_camera_link.reload", "Finaliser et commencer un nouveau groupe")
    language.Add("tool.opium_camera_link.0", "Clic gauche sur une caméra ou un moniteur pour commencer un groupe")
    language.Add("tool.opium_camera_link.1", "Clic gauche sur une caméra/moniteur pour l'ajouter au groupe. Rechargez pour finaliser.")
end

-- État serveur : groupe actif par joueur
local ActiveGroups = {}

-- ============================================================================
-- FONCTIONS UTILITAIRES
-- ============================================================================

local function IsCamera(ent)
    return IsValid(ent) and ent:GetClass() == "ent_security_cam"
end

local function IsMonitor(ent)
    return IsValid(ent) and ent:GetClass() == "ent_security_monitor"
end

local function IsLinkable(ent)
    return IsCamera(ent) or IsMonitor(ent)
end

local function GetEntityGroup(ent)
    if IsCamera(ent) then return ent:GetCamGroup() end
    if IsMonitor(ent) then return ent:GetMonitorGroup() end
    return ""
end

local function SetEntityGroup(ent, groupID)
    if IsCamera(ent) then ent:SetCamGroup(groupID) end
    if IsMonitor(ent) then ent:SetMonitorGroup(groupID) end
end

local function GetEntityLabel(ent)
    if IsCamera(ent) then return ent:GetCamName() end
    if IsMonitor(ent) then return "Moniteur" end
    return "Entité"
end

local function GetGroupCameraCount(groupID)
    if groupID == "" then return 0 end
    local count = 0
    for _, cam in ipairs(ents.FindByClass("ent_security_cam")) do
        if IsValid(cam) and cam:GetCamGroup() == groupID then
            count = count + 1
        end
    end
    return count
end

local function GetGroupMonitorCount(groupID)
    if groupID == "" then return 0 end
    local count = 0
    for _, monitor in ipairs(ents.FindByClass("ent_security_monitor")) do
        if IsValid(monitor) and monitor:GetMonitorGroup() == groupID then
            count = count + 1
        end
    end
    return count
end

-- ============================================================================
-- TOOL ACTIONS
-- ============================================================================

function TOOL:LeftClick(trace)
    if not IsLinkable(trace.Entity) then return false end

    if CLIENT then return true end

    local ply = self:GetOwner()
    local ent = trace.Entity

    -- Si pas de groupe actif, en créer un ou utiliser un existant
    if not ActiveGroups[ply] then
        local selectedGroupID = self:GetClientInfo("groupid")
        selectedGroupID = string.Trim(selectedGroupID or "")

        if selectedGroupID ~= "" and OpiumSecurity.Groups[selectedGroupID] then
            -- Utiliser un groupe existant : vérifier les permissions
            if not OpiumSecurity.CanManageGroup(ply, selectedGroupID) then
                ply:ChatPrint("[Opium Security] Vous n'avez pas les droits pour gérer ce groupe.")
                return true
            end

            local displayName = OpiumSecurity.GetGroupName(selectedGroupID)
            ActiveGroups[ply] = { id = selectedGroupID, name = displayName, count = 0 }
        else
            -- Créer un nouveau groupe
            local customName = self:GetClientInfo("group")
            customName = string.Trim(customName or "")

            local displayName
            if customName ~= "" then
                displayName = string.sub(customName, 1, 32)
            else
                displayName = "Groupe de " .. ply:Nick()
            end

            local groupID = OpiumSecurity.CreateGroup(ply, displayName)
            ActiveGroups[ply] = { id = groupID, name = displayName, count = 0 }
        end

        self:SetStage(1)
    end

    local group = ActiveGroups[ply]

    -- Vérifier les permissions (au cas où le groupe a changé entre-temps)
    if not OpiumSecurity.CanManageGroup(ply, group.id) then
        ply:ChatPrint("[Opium Security] Vous n'avez plus les droits pour gérer ce groupe.")
        ActiveGroups[ply] = nil
        self:SetStage(0)
        return true
    end

    SetEntityGroup(ent, group.id)
    group.count = group.count + 1

    local label = GetEntityLabel(ent)
    ply:ChatPrint("[Opium Security] " .. label .. " ajouté(e) au groupe \"" .. group.name .. "\" (" .. group.count .. " éléments)")
    ply:EmitSound("buttons/button14.wav")

    return true
end

function TOOL:RightClick(trace)
    if not IsLinkable(trace.Entity) then return false end

    if CLIENT then return true end

    local ply = self:GetOwner()
    local ent = trace.Entity
    local oldGroupID = GetEntityGroup(ent)

    if oldGroupID == "" then
        ply:ChatPrint("[Opium Security] " .. GetEntityLabel(ent) .. " n'appartient à aucun groupe.")
        return true
    end

    -- Vérifier les permissions
    if not OpiumSecurity.CanManageGroup(ply, oldGroupID) then
        ply:ChatPrint("[Opium Security] Vous n'avez pas les droits pour retirer des éléments de ce groupe.")
        return true
    end

    SetEntityGroup(ent, "")

    if ActiveGroups[ply] and ActiveGroups[ply].id == oldGroupID then
        ActiveGroups[ply].count = math.max(0, ActiveGroups[ply].count - 1)
    end

    local displayName = OpiumSecurity.GetGroupName(oldGroupID)
    ply:ChatPrint("[Opium Security] " .. GetEntityLabel(ent) .. " retiré(e) du groupe \"" .. displayName .. "\".")
    ply:EmitSound("buttons/button15.wav")

    return true
end

function TOOL:Reload(trace)
    if CLIENT then return true end

    local ply = self:GetOwner()

    if ActiveGroups[ply] then
        local group = ActiveGroups[ply]
        ply:ChatPrint("[Opium Security] Groupe \"" .. group.name .. "\" finalisé avec " .. group.count .. " éléments.")
        ActiveGroups[ply] = nil
        self:SetStage(0)
    else
        ply:ChatPrint("[Opium Security] Aucun groupe en cours.")
    end

    return true
end

function TOOL:Holster()
    if SERVER and IsValid(self:GetOwner()) then
        ActiveGroups[self:GetOwner()] = nil
    end
end

function TOOL:Deploy()
    if SERVER then
        self:SetStage(ActiveGroups[self:GetOwner()] and 1 or 0)
    end
end

-- Nettoyage quand un joueur se déconnecte
hook.Add("PlayerDisconnected", "OpiumSecurity_ToolCleanup", function(ply)
    ActiveGroups[ply] = nil
end)

-- ============================================================================
-- HUD CLIENT
-- ============================================================================

if CLIENT then
    function TOOL:DrawHUD()
        local trace = LocalPlayer():GetEyeTrace()
        local colors = OpiumSecurity and OpiumSecurity.Config and OpiumSecurity.Config.Colors

        if not colors then return end

        local sw, sh = ScrW(), ScrH()
        local cx, cy = sw / 2, sh / 2

        -- Info sur la caméra visée
        if IsCamera(trace.Entity) then
            local cam = trace.Entity
            local groupID = cam:GetCamGroup()
            local name = cam:GetCamName()

            local panelW, panelH = 300, 70
            local px, py = cx - panelW / 2, cy + 40

            if groupID and groupID ~= "" then
                panelH = 90
            end

            draw.RoundedBox(6, px, py, panelW, panelH, ColorAlpha(colors.Background, 220))
            surface.SetDrawColor(ColorAlpha(colors.Border, 200))
            surface.DrawOutlinedRect(px, py, panelW, panelH, 1)

            -- Barre accent en haut
            surface.SetDrawColor(colors.Accent)
            surface.DrawRect(px, py, panelW, 3)

            draw.SimpleText(name, "OpiumSec_Subtitle", cx, py + 18, colors.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

            if groupID and groupID ~= "" then
                local displayName = OpiumSecurity.GetGroupName(groupID)
                local count = GetGroupCameraCount(groupID)
                draw.SimpleText("Groupe : " .. displayName, "OpiumSec_Body", cx, py + 42, colors.Accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
                draw.SimpleText(count .. " caméra(s) liée(s)", "OpiumSec_Small", cx, py + 62, colors.TextDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            else
                draw.SimpleText("Aucun groupe", "OpiumSec_Small", cx, py + 42, colors.TextDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            end
        end

        -- Info sur le moniteur visé
        if IsMonitor(trace.Entity) then
            local monitor = trace.Entity
            local groupID = monitor:GetMonitorGroup()

            local panelW, panelH = 300, 70
            local px, py = cx - panelW / 2, cy + 40

            if groupID and groupID ~= "" then
                panelH = 90
            end

            draw.RoundedBox(6, px, py, panelW, panelH, ColorAlpha(colors.Background, 220))
            surface.SetDrawColor(ColorAlpha(colors.Border, 200))
            surface.DrawOutlinedRect(px, py, panelW, panelH, 1)

            -- Barre accent en haut
            surface.SetDrawColor(colors.Accent)
            surface.DrawRect(px, py, panelW, 3)

            draw.SimpleText("Moniteur de Sécurité", "OpiumSec_Subtitle", cx, py + 18, colors.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

            if groupID and groupID ~= "" then
                local displayName = OpiumSecurity.GetGroupName(groupID)
                local camCount = GetGroupCameraCount(groupID)
                local monCount = GetGroupMonitorCount(groupID)
                draw.SimpleText("Groupe : " .. displayName, "OpiumSec_Body", cx, py + 42, colors.Accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
                draw.SimpleText(camCount .. " caméra(s), " .. monCount .. " moniteur(s)", "OpiumSec_Small", cx, py + 62, colors.TextDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            else
                draw.SimpleText("Aucun groupe", "OpiumSec_Small", cx, py + 42, Color(255, 80, 80), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            end
        end

        -- Indicateur du groupe en cours (stage 1)
        if self:GetStage() == 1 then
            local panelW, panelH = 280, 36
            local px = sw - panelW - 20
            local py = sh / 2 - panelH / 2

            draw.RoundedBox(6, px, py, panelW, panelH, ColorAlpha(colors.Background, 220))
            surface.SetDrawColor(colors.Success)
            surface.DrawRect(px, py, 4, panelH)

            draw.SimpleText("Groupe en cours...", "OpiumSec_Body", px + 14, py + panelH / 2, colors.Success, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end

    -- ============================================================================
    -- PANNEAU DE CONFIGURATION (Menu Q -> Outils)
    -- ============================================================================

    local selectedGroupID = nil

    function TOOL.BuildCPanel(CPanel)
        CPanel:AddControl("Header", {
            Description = "Relie les caméras de sécurité en groupes.\n\nClic gauche : ajouter au groupe\nClic droit : retirer du groupe\nRechargement : nouveau groupe"
        })

        CPanel:AddControl("TextBox", {
            Label = "Nom du groupe",
            Command = "opium_camera_link_group",
            MaxLength = 32,
        })

        CPanel:Help("Laissez vide pour un nom automatique. Si un groupe existant est sélectionné ci-dessous, les entités seront ajoutées à ce groupe.")

        -- Liste des groupes existants
        local listLabel = vgui.Create("DLabel", CPanel)
        listLabel:SetText("Groupes existants :")
        listLabel:SetFont("DermaDefaultBold")
        listLabel:SetTextColor(Color(200, 200, 200))
        listLabel:SizeToContents()
        CPanel:AddItem(listLabel)

        local listView = vgui.Create("DListView", CPanel)
        listView:SetTall(200)
        listView:AddColumn("Groupe")
        listView:AddColumn("Propriétaire")
        listView:AddColumn("Entités")
        CPanel:AddItem(listView)

        -- Remplir la liste
        local function RefreshGroupList()
            listView:Clear()
            local groups = {}

            -- Collecter les groupes depuis les entités
            for _, cam in ipairs(ents.FindByClass("ent_security_cam")) do
                if IsValid(cam) then
                    local g = cam:GetCamGroup()
                    if g and g ~= "" then
                        groups[g] = groups[g] or { cams = 0, monitors = 0 }
                        groups[g].cams = groups[g].cams + 1
                    end
                end
            end

            for _, monitor in ipairs(ents.FindByClass("ent_security_monitor")) do
                if IsValid(monitor) then
                    local g = monitor:GetMonitorGroup()
                    if g and g ~= "" then
                        groups[g] = groups[g] or { cams = 0, monitors = 0 }
                        groups[g].monitors = groups[g].monitors + 1
                    end
                end
            end

            -- Ajouter aussi les groupes du registre (même sans entités)
            if OpiumSecurity.GroupRegistry then
                for gid, _ in pairs(OpiumSecurity.GroupRegistry) do
                    groups[gid] = groups[gid] or { cams = 0, monitors = 0 }
                end
            end

            for gid, data in pairs(groups) do
                local displayName = OpiumSecurity.GetGroupName(gid)
                local info = OpiumSecurity.GetGroupInfo(gid)

                -- Trouver le nom du propriétaire
                local ownerName = "Inconnu"
                if info and info.owner then
                    for _, ply in ipairs(player.GetAll()) do
                        if IsValid(ply) and ply:SteamID64() == info.owner then
                            ownerName = ply:Nick()
                            break
                        end
                    end
                end

                local line = listView:AddLine(
                    displayName,
                    ownerName,
                    data.cams .. " cam, " .. data.monitors .. " mon"
                )
                line._groupID = gid
            end
        end

        RefreshGroupList()

        -- Bouton de rafraîchissement
        local btnRefresh = vgui.Create("DButton", CPanel)
        btnRefresh:SetText("Rafraîchir la liste")
        btnRefresh:SetTall(28)
        btnRefresh.DoClick = function()
            RefreshGroupList()
        end
        CPanel:AddItem(btnRefresh)

        -- Clic sur un groupe pour le sélectionner
        listView.OnRowSelected = function(_, _, row)
            selectedGroupID = row._groupID
            RunConsoleCommand("opium_camera_link_groupid", selectedGroupID or "")
            RunConsoleCommand("opium_camera_link_group", "")
        end

        -- Bouton configurer les alertes
        local btnAlerts = vgui.Create("DButton", CPanel)
        btnAlerts:SetText("Configurer les alertes")
        btnAlerts:SetTall(32)
        btnAlerts:SetTextColor(Color(255, 255, 255))
        btnAlerts.Paint = function(self, w, h)
            local bg = self:IsHovered() and Color(0, 140, 220, 255) or Color(0, 120, 200, 255)
            if not selectedGroupID then bg = Color(80, 80, 80, 255) end
            draw.RoundedBox(4, 0, 0, w, h, bg)
        end
        btnAlerts.DoClick = function()
            if not selectedGroupID then
                chat.AddText(Color(255, 80, 80), "[Opium Security] ", color_white, "Sélectionnez d'abord un groupe dans la liste.")
                return
            end
            OpenGroupJobsConfig(selectedGroupID)
        end
        CPanel:AddItem(btnAlerts)

        -- Bouton gérer les accès
        local btnManagers = vgui.Create("DButton", CPanel)
        btnManagers:SetText("Gérer les accès")
        btnManagers:SetTall(32)
        btnManagers:SetTextColor(Color(255, 255, 255))
        btnManagers.Paint = function(self, w, h)
            local bg = self:IsHovered() and Color(120, 60, 200, 255) or Color(100, 50, 180, 255)
            if not selectedGroupID then bg = Color(80, 80, 80, 255) end
            draw.RoundedBox(4, 0, 0, w, h, bg)
        end
        btnManagers.DoClick = function()
            if not selectedGroupID then
                chat.AddText(Color(255, 80, 80), "[Opium Security] ", color_white, "Sélectionnez d'abord un groupe dans la liste.")
                return
            end
            OpenGroupManagerConfig(selectedGroupID)
        end
        CPanel:AddItem(btnManagers)

        -- Bouton désélectionner le groupe (nouveau groupe)
        local btnNewGroup = vgui.Create("DButton", CPanel)
        btnNewGroup:SetText("Créer un nouveau groupe")
        btnNewGroup:SetTall(28)
        btnNewGroup.DoClick = function()
            selectedGroupID = nil
            RunConsoleCommand("opium_camera_link_groupid", "")
            listView:ClearSelection()
        end
        CPanel:AddItem(btnNewGroup)
    end

    -- ========================================================================
    -- FENÊTRE DE CONFIGURATION DES ALERTES PAR GROUPE
    -- ========================================================================

    local jobConfigFrame = nil

    function OpenGroupJobsConfig(groupID)
        -- Fermer l'ancienne fenêtre si elle existe
        if IsValid(jobConfigFrame) then jobConfigFrame:Remove() end

        local colors = OpiumSecurity and OpiumSecurity.Config and OpiumSecurity.Config.Colors
        if not colors then return end

        local displayName = OpiumSecurity.GetGroupName(groupID)

        jobConfigFrame = vgui.Create("DFrame")
        jobConfigFrame:SetSize(420, 520)
        jobConfigFrame:Center()
        jobConfigFrame:SetTitle("")
        jobConfigFrame:MakePopup()
        jobConfigFrame:SetDraggable(true)
        jobConfigFrame:SetSizable(false)
        jobConfigFrame.Paint = function(self, w, h)
            draw.RoundedBox(8, 0, 0, w, h, colors.Background)
            surface.SetDrawColor(colors.Border)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            -- Barre d'accent en haut
            surface.SetDrawColor(colors.Accent)
            surface.DrawRect(0, 0, w, 3)

            -- Titre
            draw.SimpleText("Configuration des alertes", "OpiumSec_Subtitle", w / 2, 18, colors.Accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            draw.SimpleText("Groupe : " .. displayName, "OpiumSec_Body", w / 2, 42, colors.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            draw.SimpleText("Cochez les jobs qui recevront les notifications.", "OpiumSec_Small", w / 2, 64, colors.TextDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        end

        -- Checkbox list container
        local scrollPanel = vgui.Create("DScrollPanel", jobConfigFrame)
        scrollPanel:SetPos(15, 88)
        scrollPanel:SetSize(390, 370)

        local sbar = scrollPanel:GetVBar()
        sbar:SetHideButtons(true)
        sbar.Paint = function() end
        sbar.btnGrip.Paint = function(self, w, h)
            draw.RoundedBox(4, w / 2 - 2, 0, 4, h, colors.AccentDark)
        end

        -- Table pour stocker les checkboxes
        local jobChecks = {}

        -- Récupérer les jobs DarkRP
        local allJobs = {}
        if RPExtraTeams then
            for _, jobData in ipairs(RPExtraTeams) do
                table.insert(allJobs, {
                    id = jobData.team,
                    name = jobData.name or "Inconnu",
                    color = jobData.color or Color(255, 255, 255),
                })
            end
        else
            -- Fallback : utiliser les teams du moteur
            for id, data in pairs(team.GetAllTeams()) do
                if id > 0 and id < 1000 then
                    table.insert(allJobs, {
                        id = id,
                        name = data.Name or "Team " .. id,
                        color = team.GetColor(id) or Color(255, 255, 255),
                    })
                end
            end
        end

        -- Trier par nom
        table.sort(allJobs, function(a, b) return a.name < b.name end)

        for _, job in ipairs(allJobs) do
            local entry = vgui.Create("DPanel", scrollPanel)
            entry:SetTall(36)
            entry:Dock(TOP)
            entry:DockMargin(0, 2, 0, 0)

            local isChecked = false

            entry.Paint = function(self, w, h)
                local bg = self:IsHovered() and colors.BackgroundLight or Color(25, 25, 35, 255)
                draw.RoundedBox(4, 0, 0, w, h, bg)

                -- Pastille couleur du job
                draw.RoundedBox(3, 8, 10, 16, 16, job.color)

                -- Nom du job
                draw.SimpleText(job.name, "OpiumSec_Body", 32, h / 2, colors.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

                -- Indicateur de sélection
                if isChecked then
                    draw.RoundedBox(3, w - 36, 8, 20, 20, colors.Accent)
                    draw.SimpleText("✓", "OpiumSec_ESP", w - 26, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                else
                    draw.RoundedBox(3, w - 36, 8, 20, 20, Color(50, 50, 60, 255))
                    surface.SetDrawColor(colors.Border)
                    surface.DrawOutlinedRect(w - 36, 8, 20, 20, 1)
                end
            end

            entry:SetCursor("hand")
            entry.OnMousePressed = function()
                isChecked = not isChecked
            end

            jobChecks[job.id] = function() return isChecked end

            -- Setter pour quand on reçoit la config du serveur
            entry._setChecked = function(val) isChecked = val end
            entry._jobID = job.id
        end

        -- Stocker les entries pour mise à jour
        jobConfigFrame._entries = scrollPanel:GetCanvas():GetChildren()
        jobConfigFrame._jobChecks = jobChecks

        -- Bouton sauvegarder
        local btnSave = vgui.Create("DButton", jobConfigFrame)
        btnSave:SetPos(15, 470)
        btnSave:SetSize(185, 36)
        btnSave:SetText("")
        btnSave.Paint = function(self, w, h)
            local bg = self:IsHovered() and Color(0, 160, 230, 255) or colors.Accent
            draw.RoundedBox(6, 0, 0, w, h, bg)
            draw.SimpleText("Sauvegarder", "OpiumSec_Body", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        btnSave.DoClick = function()
            local selectedJobs = {}
            for jobID, getChecked in pairs(jobChecks) do
                if getChecked() then
                    table.insert(selectedJobs, jobID)
                end
            end

            net.Start("opium_group_jobs_update")
                net.WriteString(groupID)
                net.WriteUInt(#selectedJobs, 8)
                for _, jobID in ipairs(selectedJobs) do
                    net.WriteInt(jobID, 16)
                end
            net.SendToServer()

            if IsValid(jobConfigFrame) then jobConfigFrame:Remove() end
        end

        -- Bouton annuler
        local btnCancel = vgui.Create("DButton", jobConfigFrame)
        btnCancel:SetPos(220, 470)
        btnCancel:SetSize(185, 36)
        btnCancel:SetText("")
        btnCancel.Paint = function(self, w, h)
            local bg = self:IsHovered() and colors.BackgroundLight or colors.Panel
            draw.RoundedBox(6, 0, 0, w, h, bg)
            draw.SimpleText("Annuler", "OpiumSec_Body", w / 2, h / 2, colors.TextDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        btnCancel.DoClick = function()
            if IsValid(jobConfigFrame) then jobConfigFrame:Remove() end
        end

        -- Demander la config actuelle au serveur
        net.Start("opium_group_jobs_request")
            net.WriteString(groupID)
        net.SendToServer()
    end

    -- Réception de la config du serveur
    net.Receive("opium_group_jobs_update", function()
        local groupID = net.ReadString()
        local count = net.ReadUInt(8)
        local jobs = {}
        for i = 1, count do
            jobs[net.ReadInt(16)] = true
        end

        -- Mettre à jour les checkboxes si la fenêtre est ouverte
        if not IsValid(jobConfigFrame) then return end
        if not jobConfigFrame._entries then return end

        for _, entry in ipairs(jobConfigFrame._entries) do
            if IsValid(entry) and entry._setChecked and entry._jobID then
                entry._setChecked(jobs[entry._jobID] == true)
            end
        end
    end)

    -- ========================================================================
    -- FENÊTRE DE GESTION DES ACCÈS (MANAGERS)
    -- ========================================================================

    local managerFrame = nil

    function OpenGroupManagerConfig(groupID)
        if IsValid(managerFrame) then managerFrame:Remove() end

        local colors = OpiumSecurity and OpiumSecurity.Config and OpiumSecurity.Config.Colors
        if not colors then return end

        local info = OpiumSecurity.GetGroupInfo(groupID)
        if not info then
            chat.AddText(Color(255, 80, 80), "[Opium Security] ", color_white, "Groupe introuvable.")
            return
        end

        local displayName = info.name or groupID

        managerFrame = vgui.Create("DFrame")
        managerFrame:SetSize(420, 480)
        managerFrame:Center()
        managerFrame:SetTitle("")
        managerFrame:MakePopup()
        managerFrame:SetDraggable(true)
        managerFrame:SetSizable(false)
        managerFrame.Paint = function(self, w, h)
            draw.RoundedBox(8, 0, 0, w, h, colors.Background)
            surface.SetDrawColor(colors.Border)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            -- Barre d'accent violette
            surface.SetDrawColor(Color(100, 50, 180, 255))
            surface.DrawRect(0, 0, w, 3)

            -- Titre
            draw.SimpleText("Gestion des accès", "OpiumSec_Subtitle", w / 2, 18, Color(140, 80, 220), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            draw.SimpleText("Groupe : " .. displayName, "OpiumSec_Body", w / 2, 42, colors.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

            -- Propriétaire
            local ownerName = info.owner or "Inconnu"
            for _, ply in ipairs(player.GetAll()) do
                if IsValid(ply) and ply:SteamID64() == info.owner then
                    ownerName = ply:Nick()
                    break
                end
            end
            draw.SimpleText("Propriétaire : " .. ownerName, "OpiumSec_Small", w / 2, 64, colors.TextDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        end

        -- === SECTION GESTIONNAIRES ACTUELS ===
        local managerLabel = vgui.Create("DLabel", managerFrame)
        managerLabel:SetPos(15, 88)
        managerLabel:SetText("Gestionnaires actuels :")
        managerLabel:SetFont("OpiumSec_Body")
        managerLabel:SetTextColor(colors.Accent)
        managerLabel:SizeToContents()

        local managerList = vgui.Create("DScrollPanel", managerFrame)
        managerList:SetPos(15, 110)
        managerList:SetSize(390, 150)

        local sbar = managerList:GetVBar()
        sbar:SetHideButtons(true)
        sbar.Paint = function() end
        sbar.btnGrip.Paint = function(self, w, h)
            draw.RoundedBox(4, w / 2 - 2, 0, 4, h, Color(100, 50, 180))
        end

        local function RefreshManagerList()
            managerList:Clear()
            local managers = info.managers or {}

            if #managers == 0 then
                local noEntry = vgui.Create("DLabel", managerList)
                noEntry:SetTall(30)
                noEntry:Dock(TOP)
                noEntry:SetText("  Aucun gestionnaire")
                noEntry:SetFont("OpiumSec_Small")
                noEntry:SetTextColor(colors.TextDim)
                return
            end

            for _, managerSteamID in ipairs(managers) do
                local entry = vgui.Create("DPanel", managerList)
                entry:SetTall(36)
                entry:Dock(TOP)
                entry:DockMargin(0, 2, 0, 0)

                -- Trouver le nom du gestionnaire
                local managerName = managerSteamID
                for _, ply in ipairs(player.GetAll()) do
                    if IsValid(ply) and ply:SteamID64() == managerSteamID then
                        managerName = ply:Nick()
                        break
                    end
                end

                entry.Paint = function(self, w, h)
                    local bg = self:IsHovered() and colors.BackgroundLight or Color(25, 25, 35, 255)
                    draw.RoundedBox(4, 0, 0, w, h, bg)
                    draw.SimpleText(managerName, "OpiumSec_Body", 10, h / 2, colors.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end

                -- Bouton retirer
                local btnRemove = vgui.Create("DButton", entry)
                btnRemove:SetSize(70, 26)
                btnRemove:SetPos(310, 5)
                btnRemove:SetText("")
                btnRemove.Paint = function(self, w, h)
                    local bg = self:IsHovered() and Color(180, 40, 40) or colors.Danger
                    draw.RoundedBox(4, 0, 0, w, h, bg)
                    draw.SimpleText("Retirer", "OpiumSec_Small", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
                btnRemove.DoClick = function()
                    net.Start("opium_group_remove_manager")
                        net.WriteString(groupID)
                        net.WriteString(managerSteamID)
                    net.SendToServer()

                    -- Retirer localement pour feedback immédiat
                    for i, id in ipairs(info.managers) do
                        if id == managerSteamID then
                            table.remove(info.managers, i)
                            break
                        end
                    end
                    RefreshManagerList()
                end
            end
        end

        RefreshManagerList()

        -- === SECTION AJOUTER UN GESTIONNAIRE ===
        local addLabel = vgui.Create("DLabel", managerFrame)
        addLabel:SetPos(15, 270)
        addLabel:SetText("Ajouter un gestionnaire :")
        addLabel:SetFont("OpiumSec_Body")
        addLabel:SetTextColor(colors.Accent)
        addLabel:SizeToContents()

        -- Liste des joueurs en ligne
        local playerCombo = vgui.Create("DComboBox", managerFrame)
        playerCombo:SetPos(15, 295)
        playerCombo:SetSize(390, 30)
        playerCombo:SetValue("Sélectionner un joueur...")
        playerCombo:SetFont("OpiumSec_Body")
        playerCombo.Paint = function(self, w, h)
            draw.RoundedBox(4, 0, 0, w, h, colors.BackgroundLight)
            surface.SetDrawColor(colors.Border)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
        end

        local localSteamID = LocalPlayer():SteamID64()
        for _, ply in ipairs(player.GetAll()) do
            if IsValid(ply) then
                local steamID = ply:SteamID64()
                -- Ne pas inclure le propriétaire ni les gestionnaires existants
                if steamID ~= info.owner then
                    local alreadyManager = false
                    for _, mid in ipairs(info.managers or {}) do
                        if mid == steamID then alreadyManager = true break end
                    end
                    if not alreadyManager then
                        playerCombo:AddChoice(ply:Nick(), steamID)
                    end
                end
            end
        end

        -- Bouton ajouter
        local btnAdd = vgui.Create("DButton", managerFrame)
        btnAdd:SetPos(15, 335)
        btnAdd:SetSize(390, 36)
        btnAdd:SetText("")
        btnAdd.Paint = function(self, w, h)
            local bg = self:IsHovered() and Color(60, 160, 80) or colors.Success
            draw.RoundedBox(6, 0, 0, w, h, bg)
            draw.SimpleText("Ajouter comme gestionnaire", "OpiumSec_Body", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        btnAdd.DoClick = function()
            local _, steamID = playerCombo:GetSelected()
            if not steamID then
                chat.AddText(Color(255, 80, 80), "[Opium Security] ", color_white, "Sélectionnez un joueur.")
                return
            end

            net.Start("opium_group_add_manager")
                net.WriteString(groupID)
                net.WriteString(steamID)
            net.SendToServer()

            -- Ajouter localement pour feedback immédiat
            table.insert(info.managers, steamID)
            RefreshManagerList()

            -- Retirer du combo
            playerCombo:Clear()
            playerCombo:SetValue("Sélectionner un joueur...")
            for _, ply in ipairs(player.GetAll()) do
                if IsValid(ply) then
                    local sid = ply:SteamID64()
                    if sid ~= info.owner then
                        local isManager = false
                        for _, mid in ipairs(info.managers or {}) do
                            if mid == sid then isManager = true break end
                        end
                        if not isManager then
                            playerCombo:AddChoice(ply:Nick(), sid)
                        end
                    end
                end
            end
        end

        -- Séparateur
        local sep = vgui.Create("DPanel", managerFrame)
        sep:SetPos(15, 385)
        sep:SetSize(390, 1)
        sep.Paint = function(self, w, h)
            surface.SetDrawColor(colors.Border)
            surface.DrawRect(0, 0, w, h)
        end

        -- Info
        local infoLabel = vgui.Create("DLabel", managerFrame)
        infoLabel:SetPos(15, 395)
        infoLabel:SetSize(390, 40)
        infoLabel:SetText("Les gestionnaires peuvent ajouter et retirer\ndes caméras et moniteurs du groupe.")
        infoLabel:SetFont("OpiumSec_Small")
        infoLabel:SetTextColor(colors.TextDim)
        infoLabel:SetWrap(true)

        -- Bouton fermer
        local btnClose = vgui.Create("DButton", managerFrame)
        btnClose:SetPos(15, 435)
        btnClose:SetSize(390, 36)
        btnClose:SetText("")
        btnClose.Paint = function(self, w, h)
            local bg = self:IsHovered() and colors.BackgroundLight or colors.Panel
            draw.RoundedBox(6, 0, 0, w, h, bg)
            draw.SimpleText("Fermer", "OpiumSec_Body", w / 2, h / 2, colors.TextDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        btnClose.DoClick = function()
            if IsValid(managerFrame) then managerFrame:Remove() end
        end
    end
end
