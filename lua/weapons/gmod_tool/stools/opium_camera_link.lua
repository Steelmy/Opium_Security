--[[
    Opium Security - Tool Gun : Liaison de Caméras
    Permet de relier des caméras en groupes via le Tool Gun.
    - Clic gauche : ajouter une caméra au groupe en cours
    - Clic droit : retirer une caméra de son groupe
    - Rechargement : finaliser le groupe et en commencer un nouveau
]]

TOOL.Category    = "Opium Security"
TOOL.Name        = "#tool.opium_camera_link.name"
TOOL.Command     = nil
TOOL.ConfigName  = ""

TOOL.ClientConVar["group"] = ""

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
local groupCounter = 0

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

local function GetGroupCameraCount(groupName)
    if groupName == "" then return 0 end
    local count = 0
    for _, cam in ipairs(ents.FindByClass("ent_security_cam")) do
        if IsValid(cam) and cam:GetCamGroup() == groupName then
            count = count + 1
        end
    end
    return count
end

local function GetGroupMonitorCount(groupName)
    if groupName == "" then return 0 end
    local count = 0
    for _, monitor in ipairs(ents.FindByClass("ent_security_monitor")) do
        if IsValid(monitor) and monitor:GetMonitorGroup() == groupName then
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

    -- Si pas de groupe actif, en créer un
    if not ActiveGroups[ply] then
        local customName = self:GetClientInfo("group")
        customName = string.Trim(customName or "")

        local groupName
        if customName ~= "" then
            groupName = string.sub(customName, 1, 32)
        else
            groupCounter = groupCounter + 1
            groupName = "GRP-" .. groupCounter
        end

        ActiveGroups[ply] = { name = groupName, count = 0 }
        self:SetStage(1)
    end

    local group = ActiveGroups[ply]

    if IsMonitor(ent) then
        ent:SetMonitorGroup(group.name)
        group.count = group.count + 1
        ply:ChatPrint("[Opium Security] Moniteur ajouté au groupe \"" .. group.name .. "\" (" .. group.count .. " éléments)")
    else
        ent:SetCamGroup(group.name)
        group.count = group.count + 1
        ply:ChatPrint("[Opium Security] " .. ent:GetCamName() .. " ajoutée au groupe \"" .. group.name .. "\" (" .. group.count .. " éléments)")
    end

    ply:EmitSound("buttons/button14.wav")

    return true
end

function TOOL:RightClick(trace)
    if not IsLinkable(trace.Entity) then return false end

    if CLIENT then return true end

    local ply = self:GetOwner()
    local ent = trace.Entity

    if IsMonitor(ent) then
        local oldGroup = ent:GetMonitorGroup()

        if oldGroup == "" then
            ply:ChatPrint("[Opium Security] Ce moniteur n'appartient à aucun groupe.")
            return true
        end

        ent:SetMonitorGroup("")

        if ActiveGroups[ply] and ActiveGroups[ply].name == oldGroup then
            ActiveGroups[ply].count = math.max(0, ActiveGroups[ply].count - 1)
        end

        ply:ChatPrint("[Opium Security] Moniteur retiré du groupe \"" .. oldGroup .. "\".")
        ply:EmitSound("buttons/button15.wav")
    else
        local oldGroup = ent:GetCamGroup()

        if oldGroup == "" then
            ply:ChatPrint("[Opium Security] " .. ent:GetCamName() .. " n'appartient à aucun groupe.")
            return true
        end

        ent:SetCamGroup("")

        if ActiveGroups[ply] and ActiveGroups[ply].name == oldGroup then
            ActiveGroups[ply].count = math.max(0, ActiveGroups[ply].count - 1)
        end

        local remaining = GetGroupCameraCount(oldGroup)
        ply:ChatPrint("[Opium Security] " .. ent:GetCamName() .. " retirée du groupe \"" .. oldGroup .. "\" (" .. remaining .. " restantes)")
        ply:EmitSound("buttons/button15.wav")
    end

    return true
end

function TOOL:Reload(trace)
    if CLIENT then return true end

    local ply = self:GetOwner()

    if ActiveGroups[ply] then
        local group = ActiveGroups[ply]
        ply:ChatPrint("[Opium Security] Groupe \"" .. group.name .. "\" finalisé avec " .. group.count .. " caméras.")
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
            local group = cam:GetCamGroup()
            local name = cam:GetCamName()

            local panelW, panelH = 300, 70
            local px, py = cx - panelW / 2, cy + 40

            if group and group ~= "" then
                panelH = 90
            end

            draw.RoundedBox(6, px, py, panelW, panelH, ColorAlpha(colors.Background, 220))
            surface.SetDrawColor(ColorAlpha(colors.Border, 200))
            surface.DrawOutlinedRect(px, py, panelW, panelH, 1)

            -- Barre accent en haut
            surface.SetDrawColor(colors.Accent)
            surface.DrawRect(px, py, panelW, 3)

            draw.SimpleText(name, "OpiumSec_Subtitle", cx, py + 18, colors.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

            if group and group ~= "" then
                local count = GetGroupCameraCount(group)
                draw.SimpleText("Groupe : " .. group, "OpiumSec_Body", cx, py + 42, colors.Accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
                draw.SimpleText(count .. " caméra(s) liée(s)", "OpiumSec_Small", cx, py + 62, colors.TextDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            else
                draw.SimpleText("Aucun groupe", "OpiumSec_Small", cx, py + 42, colors.TextDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            end
        end

        -- Info sur le moniteur visé
        if IsMonitor(trace.Entity) then
            local monitor = trace.Entity
            local group = monitor:GetMonitorGroup()

            local panelW, panelH = 300, 70
            local px, py = cx - panelW / 2, cy + 40

            if group and group ~= "" then
                panelH = 90
            end

            draw.RoundedBox(6, px, py, panelW, panelH, ColorAlpha(colors.Background, 220))
            surface.SetDrawColor(ColorAlpha(colors.Border, 200))
            surface.DrawOutlinedRect(px, py, panelW, panelH, 1)

            -- Barre accent en haut
            surface.SetDrawColor(colors.Accent)
            surface.DrawRect(px, py, panelW, 3)

            draw.SimpleText("Moniteur de Sécurité", "OpiumSec_Subtitle", cx, py + 18, colors.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

            if group and group ~= "" then
                local camCount = GetGroupCameraCount(group)
                local monCount = GetGroupMonitorCount(group)
                draw.SimpleText("Groupe : " .. group, "OpiumSec_Body", cx, py + 42, colors.Accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
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

    local selectedGroupName = nil

    function TOOL.BuildCPanel(CPanel)
        CPanel:AddControl("Header", {
            Description = "Relie les caméras de sécurité en groupes.\n\nClic gauche : ajouter au groupe\nClic droit : retirer du groupe\nRechargement : nouveau groupe"
        })

        CPanel:AddControl("TextBox", {
            Label = "Nom du groupe",
            Command = "opium_camera_link_group",
            MaxLength = 32,
        })

        CPanel:Help("Laissez vide pour un nom automatique (GRP-1, GRP-2...)")

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
        listView:AddColumn("Caméras")
        CPanel:AddItem(listView)

        -- Remplir la liste
        local function RefreshGroupList()
            listView:Clear()
            local groups = {}

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

            for name, data in pairs(groups) do
                listView:AddLine(name, data.cams .. " cam, " .. data.monitors .. " mon")
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

        -- Clic sur un groupe pour remplir le champ
        listView.OnRowSelected = function(_, _, row)
            local groupName = row:GetColumnText(1)
            selectedGroupName = groupName
            RunConsoleCommand("opium_camera_link_group", groupName)
        end

        -- Bouton configurer les alertes
        local btnAlerts = vgui.Create("DButton", CPanel)
        btnAlerts:SetText("Configurer les alertes")
        btnAlerts:SetTall(32)
        btnAlerts:SetTextColor(Color(255, 255, 255))
        btnAlerts.Paint = function(self, w, h)
            local bg = self:IsHovered() and Color(0, 140, 220, 255) or Color(0, 120, 200, 255)
            if not selectedGroupName then bg = Color(80, 80, 80, 255) end
            draw.RoundedBox(4, 0, 0, w, h, bg)
        end
        btnAlerts.DoClick = function()
            if not selectedGroupName then
                chat.AddText(Color(255, 80, 80), "[Opium Security] ", color_white, "Sélectionnez d'abord un groupe dans la liste.")
                return
            end
            OpenGroupJobsConfig(selectedGroupName)
        end
        CPanel:AddItem(btnAlerts)
    end

    -- ========================================================================
    -- FENÊTRE DE CONFIGURATION DES ALERTES PAR GROUPE
    -- ========================================================================

    local jobConfigFrame = nil

    function OpenGroupJobsConfig(groupName)
        -- Fermer l'ancienne fenêtre si elle existe
        if IsValid(jobConfigFrame) then jobConfigFrame:Remove() end

        local colors = OpiumSecurity and OpiumSecurity.Config and OpiumSecurity.Config.Colors
        if not colors then return end

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
            draw.SimpleText("Groupe : " .. groupName, "OpiumSec_Body", w / 2, 42, colors.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
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
                net.WriteString(groupName)
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
            net.WriteString(groupName)
        net.SendToServer()
    end

    -- Réception de la config du serveur
    net.Receive("opium_group_jobs_update", function()
        local groupName = net.ReadString()
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
end
