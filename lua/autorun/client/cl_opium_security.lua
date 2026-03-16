--[[
    Opium Security - Logique Client
    Gère l'affichage ESP, la vue caméra, le HUD et l'interface VGUI.
]]

-- Sécurité : s'assurer que la table globale existe
OpiumSecurity = OpiumSecurity or {}
OpiumSecurity.Config = OpiumSecurity.Config or {}

-- ============================================================================
-- VARIABLES LOCALES
-- ============================================================================

local isViewingCamera = false       -- Le joueur regarde-t-il à travers une caméra ?
local currentCamera = NULL          -- Entité caméra actuelle
local cameraPanel = nil             -- Panel VGUI du terminal
local notifications = {}            -- File de notifications actives

-- Cache des joueurs recherchés détectés par les caméras
local detectedPlayers = {}          -- [Player] = timestamp d'expiration du clignotement

-- ============================================================================
-- POLICES PERSONNALISÉES
-- ============================================================================

surface.CreateFont("OpiumSec_Title", {
    font = "Roboto",
    size = 28,
    weight = 700,
    antialias = true,
})

surface.CreateFont("OpiumSec_Subtitle", {
    font = "Roboto",
    size = 18,
    weight = 500,
    antialias = true,
})

surface.CreateFont("OpiumSec_Body", {
    font = "Roboto",
    size = 16,
    weight = 400,
    antialias = true,
})

surface.CreateFont("OpiumSec_Small", {
    font = "Roboto",
    size = 13,
    weight = 400,
    antialias = true,
})

surface.CreateFont("OpiumSec_ESP", {
    font = "Roboto",
    size = 14,
    weight = 600,
    antialias = true,
    outline = true,
})

surface.CreateFont("OpiumSec_ESPSmall", {
    font = "Roboto",
    size = 12,
    weight = 400,
    antialias = true,
    outline = true,
})

surface.CreateFont("OpiumSec_Notification", {
    font = "Roboto",
    size = 15,
    weight = 500,
    antialias = true,
})

-- ============================================================================
-- FONCTIONS UTILITAIRES CLIENT
-- ============================================================================

--- Récupère le nom RP d'un joueur
local function GetRPName(ply)
    if not IsValid(ply) then return "Inconnu" end
    if ply.getDarkRPVar then
        local rpName = ply:getDarkRPVar("rpname")
        if rpName then return rpName end
    end
    return ply:Nick()
end

--- Récupère le job d'un joueur
local function GetJobName(ply)
    if not IsValid(ply) then return "Inconnu" end
    if ply.getDarkRPVar then
        local job = ply:getDarkRPVar("job")
        if job then return job end
    end
    return team.GetName(ply:Team()) or "Inconnu"
end

--- Vérifie si un joueur est recherché
local function IsPlayerWanted(ply)
    if not IsValid(ply) then return false end
    -- DarkRP
    if ply.getDarkRPVar then
        if ply:getDarkRPVar("wanted") then return true end
    end
    -- Fallback custom
    if ply:GetNWBool("opium_wanted", false) then return true end
    return false
end

--- Dessine un texte avec ombre
local function DrawTextShadow(text, font, x, y, color, alignX, alignY)
    draw.SimpleText(text, font, x + 1, y + 1, Color(0, 0, 0, 180), alignX, alignY)
    draw.SimpleText(text, font, x, y, color, alignX, alignY)
end

-- ============================================================================
-- SYSTÈME DE VUE CAMÉRA (CalcView)
-- ============================================================================

hook.Add("CalcView", "OpiumSecurity_CameraView", function(ply, pos, angles, fov)
    if not isViewingCamera or not IsValid(currentCamera) then return end

    local camPos = currentCamera:GetPos() + currentCamera:GetForward() * 5 + currentCamera:GetUp() * 5
    local camAng = currentCamera:GetAngles()

    return {
        origin = camPos,
        angles = camAng,
        fov = 90,
        drawviewer = true,
    }
end)

-- Bloquer les mouvements pendant la vue caméra
hook.Add("StartCommand", "OpiumSecurity_FreezeInCamera", function(ply, cmd)
    if isViewingCamera and ply == LocalPlayer() then
        cmd:ClearMovement()
        cmd:ClearButtons()
    end
end)

-- ============================================================================
-- ESP / HUD DANS LA VUE CAMÉRA
-- ============================================================================

hook.Add("HUDPaint", "OpiumSecurity_CameraESP", function()
    if not isViewingCamera or not IsValid(currentCamera) then return end

    local camPos = currentCamera:GetPos() + currentCamera:GetForward() * 5 + currentCamera:GetUp() * 5
    local camAng = currentCamera:GetAngles()
    local cfg = OpiumSecurity.Config
    local colors = cfg.Colors
    local time = CurTime()

    -- ===== OVERLAY DE LA CAMÉRA =====
    local sw, sh = ScrW(), ScrH()

    -- Bandes noires en haut et en bas (effet cinématique)
    surface.SetDrawColor(0, 0, 0, 200)
    surface.DrawRect(0, 0, sw, 40)
    surface.DrawRect(0, sh - 40, sw, 40)

    -- Nom de la caméra en haut à gauche
    local camLabel = currentCamera:GetCamName() .. "  |  EN DIRECT"
    local camGroup = currentCamera:GetCamGroup()
    if camGroup and camGroup ~= "" then
        camLabel = camLabel .. "  |  " .. camGroup
    end
    DrawTextShadow(
        camLabel,
        "OpiumSec_Subtitle", 15, 12,
        colors.Accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP
    )

    -- Timestamp en haut à droite
    DrawTextShadow(
        os.date("%H:%M:%S"), "OpiumSec_Subtitle",
        sw - 15, 12, colors.TextDim,
        TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP
    )

    -- Indicateur REC clignotant
    if math.floor(time * 2) % 2 == 0 then
        draw.RoundedBox(4, sw - 80, sh - 32, 65, 22, Color(200, 30, 30, 200))
        DrawTextShadow("● REC", "OpiumSec_Small", sw - 48, sh - 21, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    -- Léger effet de scanlines
    surface.SetDrawColor(0, 0, 0, 15)
    for i = 0, sh, 3 do
        surface.DrawLine(0, i, sw, i)
    end

    -- ===== ESP SUR LES JOUEURS =====
    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) or ply == LocalPlayer() then continue end
        if not ply:Alive() then continue end

        local plyPos = ply:GetPos()
        local plyCenter = plyPos + Vector(0, 0, 40)
        local dist = camPos:Distance(plyCenter)

        -- Vérifier la distance
        if dist > cfg.ESPMaxDistance then continue end

        -- Vérifier le FOV
        if not OpiumSecurity.IsInCameraFOV(camPos, camAng, plyCenter) then continue end

        -- Vérifier la ligne de vue
        if not OpiumSecurity.HasLineOfSight(camPos, plyCenter, currentCamera) then continue end

        -- Convertir la position 3D en 2D
        local headPos = plyPos + Vector(0, 0, 75 + cfg.ESPHeightOffset)
        local screenPos = headPos:ToScreen()
        local feetScreen = plyPos:ToScreen()

        if not screenPos.visible then continue end

        local sx, sy = screenPos.x, screenPos.y
        local wanted = IsPlayerWanted(ply)
        local recentlyDetected = detectedPlayers[ply] and detectedPlayers[ply] > time

        -- ===== CADRE ROUGE CLIGNOTANT (si recherché ou détecté) =====
        if wanted or recentlyDetected then
            local blinkAlpha = math.abs(math.sin(time / cfg.BlinkSpeed * math.pi)) * 200 + 55

            -- Calculer la bounding box approximative
            local boxH = math.abs(feetScreen.y - screenPos.y) + 20
            local boxW = boxH * 0.5
            local boxX = sx - boxW / 2
            local boxY = sy - 10

            -- Cadre rouge clignotant
            surface.SetDrawColor(255, 50, 50, blinkAlpha)
            surface.DrawOutlinedRect(boxX, boxY, boxW, boxH, 2)

            -- Coins renforcés
            local cornerLen = 8
            surface.SetDrawColor(255, 30, 30, blinkAlpha)
            -- Haut-gauche
            surface.DrawRect(boxX, boxY, cornerLen, 3)
            surface.DrawRect(boxX, boxY, 3, cornerLen)
            -- Haut-droite
            surface.DrawRect(boxX + boxW - cornerLen, boxY, cornerLen, 3)
            surface.DrawRect(boxX + boxW - 3, boxY, 3, cornerLen)
            -- Bas-gauche
            surface.DrawRect(boxX, boxY + boxH - 3, cornerLen, 3)
            surface.DrawRect(boxX, boxY + boxH - cornerLen, 3, cornerLen)
            -- Bas-droite
            surface.DrawRect(boxX + boxW - cornerLen, boxY + boxH - 3, cornerLen, 3)
            surface.DrawRect(boxX + boxW - 3, boxY + boxH - cornerLen, 3, cornerLen)

            -- Label "RECHERCHÉ"
            DrawTextShadow(
                "⚠ RECHERCHÉ", "OpiumSec_ESP",
                sx, sy - 28, Color(255, 80, 80, blinkAlpha),
                TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM
            )
        end

        -- ===== INFORMATIONS DU JOUEUR =====
        local rpName = GetRPName(ply)
        local jobName = GetJobName(ply)
        local nameColor = wanted and colors.Danger or colors.Accent

        -- Fond semi-transparent derrière le texte
        local textW = math.max(
            surface.GetTextSize(rpName) or 0,
            surface.GetTextSize(jobName) or 0
        )
        surface.SetFont("OpiumSec_ESP")
        textW = select(1, surface.GetTextSize(rpName))
        local tw2 = select(1, surface.GetTextSize(jobName))
        textW = math.max(textW, tw2) + 16

        draw.RoundedBox(4, sx - textW / 2, sy - 8, textW, 34, Color(0, 0, 0, 140))

        -- Nom RP
        DrawTextShadow(rpName, "OpiumSec_ESP", sx, sy, nameColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

        -- Job
        DrawTextShadow(jobName, "OpiumSec_ESPSmall", sx, sy + 16, colors.TextDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end
end)

-- Cacher le HUD normal pendant la vue caméra
hook.Add("HUDShouldDraw", "OpiumSecurity_HideHUD", function(name)
    if isViewingCamera then
        if name ~= "CHudGMod" and name ~= "CHudChat" then
            return false
        end
    end
end)

-- ============================================================================
-- SYSTÈME DE NOTIFICATIONS
-- ============================================================================

hook.Add("HUDPaint", "OpiumSecurity_Notifications", function()
    local time = CurTime()
    local sw = ScrW()
    local y = 80

    for i = #notifications, 1, -1 do
        local notif = notifications[i]
        if time > notif.expire then
            table.remove(notifications, i)
        else
            local alpha = 255
            local remaining = notif.expire - time
            if remaining < 1 then
                alpha = remaining * 255
            end

            local w, h = 380, 85
            local x = sw - w - 20

            -- Animation d'entrée
            local age = time - notif.created
            if age < 0.3 then
                x = x + (1 - age / 0.3) * (w + 20)
            end

            -- Fond
            draw.RoundedBox(6, x, y, w, h, ColorAlpha(OpiumSecurity.Config.Colors.Background, alpha))

            -- Barre latérale rouge
            surface.SetDrawColor(ColorAlpha(OpiumSecurity.Config.Colors.Danger, alpha))
            surface.DrawRect(x, y, 4, h)

            -- Icône alerte
            DrawTextShadow("⚠ ALERTE CAMÉRA", "OpiumSec_Body", x + 14, y + 8, ColorAlpha(OpiumSecurity.Config.Colors.Danger, alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

            -- Contenu
            DrawTextShadow(notif.attacker, "OpiumSec_ESP", x + 14, y + 30, ColorAlpha(OpiumSecurity.Config.Colors.Text, alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            DrawTextShadow(notif.reason, "OpiumSec_Small", x + 14, y + 48, ColorAlpha(OpiumSecurity.Config.Colors.TextDim, alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            DrawTextShadow("📍 " .. notif.camera, "OpiumSec_Small", x + 14, y + 64, ColorAlpha(OpiumSecurity.Config.Colors.AccentDark, alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

            y = y + h + 8
        end
    end
end)

-- ============================================================================
-- INTERFACE VGUI - TERMINAL DE CONTRÔLE
-- ============================================================================

local function OpenCameraTerminal(camera)
    if IsValid(cameraPanel) then cameraPanel:Remove() end
    if not IsValid(camera) then return end

    currentCamera = camera
    isViewingCamera = true

    local colors = OpiumSecurity.Config.Colors
    local sw, sh = ScrW(), ScrH()

    -- Panel principal (barre de contrôle en bas)
    cameraPanel = vgui.Create("DPanel")
    cameraPanel:SetSize(500, 60)
    cameraPanel:SetPos(sw / 2 - 250, sh - 110)
    cameraPanel.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, colors.Background)
        surface.SetDrawColor(colors.Border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    -- Bouton Caméra Précédente
    local btnPrev = vgui.Create("DButton", cameraPanel)
    btnPrev:SetSize(100, 40)
    btnPrev:SetPos(10, 10)
    btnPrev:SetText("")
    btnPrev.Paint = function(self, w, h)
        local bg = self:IsHovered() and colors.AccentDark or colors.BackgroundLight
        draw.RoundedBox(6, 0, 0, w, h, bg)
        DrawTextShadow("◀ Précédent", "OpiumSec_Small", w / 2, h / 2, colors.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    btnPrev.DoClick = function()
        net.Start("opium_camera_switch")
            net.WriteInt(-1, 8)
            net.WriteEntity(currentCamera)
        net.SendToServer()
    end

    -- Bouton Quitter (centre)
    local btnExit = vgui.Create("DButton", cameraPanel)
    btnExit:SetSize(120, 40)
    btnExit:SetPos(190, 10)
    btnExit:SetText("")
    btnExit.Paint = function(self, w, h)
        local bg = self:IsHovered() and Color(180, 40, 40, 255) or colors.Danger
        draw.RoundedBox(6, 0, 0, w, h, bg)
        DrawTextShadow("✕ Quitter", "OpiumSec_Body", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    btnExit.DoClick = function()
        CloseCameraView()
    end

    -- Bouton Caméra Suivante
    local btnNext = vgui.Create("DButton", cameraPanel)
    btnNext:SetSize(100, 40)
    btnNext:SetPos(390, 10)
    btnNext:SetText("")
    btnNext.Paint = function(self, w, h)
        local bg = self:IsHovered() and colors.AccentDark or colors.BackgroundLight
        draw.RoundedBox(6, 0, 0, w, h, bg)
        DrawTextShadow("Suivant ▶", "OpiumSec_Small", w / 2, h / 2, colors.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    btnNext.DoClick = function()
        net.Start("opium_camera_switch")
            net.WriteInt(1, 8)
            net.WriteEntity(currentCamera)
        net.SendToServer()
    end

    -- Panel latéral : liste des joueurs visibles (pour déclarer recherché)
    local sidePanel = vgui.Create("DPanel")
    sidePanel:SetSize(280, 400)
    sidePanel:SetPos(20, sh / 2 - 200)
    sidePanel.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, colors.Background)
        surface.SetDrawColor(colors.Border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)

        -- Titre
        draw.RoundedBox(0, 0, 0, w, 36, colors.BackgroundLight)
        DrawTextShadow("👁 Joueurs Détectés", "OpiumSec_Subtitle", 12, 9, colors.Accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end
    sidePanel:SetParent(cameraPanel:GetParent())
    -- Stocker comme enfant logique pour nettoyage
    cameraPanel.sidePanel = sidePanel

    -- Scroll panel pour la liste des joueurs
    local playerList = vgui.Create("DScrollPanel", sidePanel)
    playerList:SetPos(5, 42)
    playerList:SetSize(270, 350)

    local sbar = playerList:GetVBar()
    sbar:SetHideButtons(true)
    sbar.Paint = function() end
    sbar.btnGrip.Paint = function(self, w, h)
        draw.RoundedBox(4, w / 2 - 2, 0, 4, h, colors.AccentDark)
    end

    -- Rafraîchir la liste des joueurs toutes les secondes
    local function RefreshPlayerList()
        if not IsValid(playerList) or not IsValid(currentCamera) then return end
        playerList:Clear()

        local camPos = currentCamera:GetPos() + currentCamera:GetForward() * 5 + currentCamera:GetUp() * 5
        local camAng = currentCamera:GetAngles()

        for _, ply in ipairs(player.GetAll()) do
            if not IsValid(ply) or ply == LocalPlayer() or not ply:Alive() then continue end

            local plyPos = ply:GetPos() + Vector(0, 0, 40)
            local dist = camPos:Distance(plyPos)

            if dist > OpiumSecurity.Config.ESPMaxDistance then continue end
            if not OpiumSecurity.IsInCameraFOV(camPos, camAng, plyPos) then continue end
            if not OpiumSecurity.HasLineOfSight(camPos, plyPos, currentCamera) then continue end

            local entry = vgui.Create("DPanel", playerList)
            entry:SetSize(260, 50)
            entry:Dock(TOP)
            entry:DockMargin(0, 2, 0, 2)

            local wanted = IsPlayerWanted(ply)
            local rpName = GetRPName(ply)
            local jobName = GetJobName(ply)

            entry.Paint = function(self, w, h)
                local bg = self:IsHovered() and colors.BackgroundLight or Color(25, 25, 35, 255)
                draw.RoundedBox(4, 0, 0, w, h, bg)

                if wanted then
                    surface.SetDrawColor(colors.Danger)
                    surface.DrawOutlinedRect(0, 0, w, h, 1)
                end

                local nameClr = wanted and colors.Danger or colors.Text
                DrawTextShadow(rpName, "OpiumSec_ESP", 10, 8, nameClr, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                DrawTextShadow(jobName, "OpiumSec_ESPSmall", 10, 26, colors.TextDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

                if wanted then
                    DrawTextShadow("RECHERCHÉ", "OpiumSec_ESPSmall", w - 10, 18, colors.Danger, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                end
            end

            -- Bouton recherché au clic
            entry:SetCursor("hand")
            entry.OnMousePressed = function()
                if not OpiumSecurity.IsPolice(LocalPlayer()) then
                    chat.AddText(Color(255, 80, 80), "[Opium Security] ", color_white, "Seule la police peut déclarer un joueur recherché.")
                    return
                end

                -- Ouvrir un mini-dialogue de confirmation
                local confirmFrame = vgui.Create("DFrame")
                confirmFrame:SetSize(320, 150)
                confirmFrame:Center()
                confirmFrame:SetTitle("")
                confirmFrame:MakePopup()
                confirmFrame:SetDraggable(false)
                confirmFrame.Paint = function(self, w, h)
                    draw.RoundedBox(8, 0, 0, w, h, colors.Background)
                    surface.SetDrawColor(colors.Border)
                    surface.DrawOutlinedRect(0, 0, w, h, 1)
                    DrawTextShadow("Déclarer recherché", "OpiumSec_Subtitle", w / 2, 15, colors.Accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
                    DrawTextShadow(rpName, "OpiumSec_Body", w / 2, 42, colors.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
                end

                local reasonInput = vgui.Create("DTextEntry", confirmFrame)
                reasonInput:SetPos(20, 70)
                reasonInput:SetSize(280, 30)
                reasonInput:SetPlaceholderText("Raison (optionnel)...")
                reasonInput:SetFont("OpiumSec_Body")
                reasonInput.Paint = function(self, w, h)
                    draw.RoundedBox(4, 0, 0, w, h, colors.BackgroundLight)
                    self:DrawTextEntryText(colors.Text, colors.AccentDark, colors.Text)
                end

                local btnConfirm = vgui.Create("DButton", confirmFrame)
                btnConfirm:SetPos(20, 110)
                btnConfirm:SetSize(135, 30)
                btnConfirm:SetText("")
                btnConfirm.Paint = function(self, w, h)
                    local bg = self:IsHovered() and Color(180, 40, 40) or colors.Danger
                    draw.RoundedBox(4, 0, 0, w, h, bg)
                    DrawTextShadow("Confirmer", "OpiumSec_Body", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
                btnConfirm.DoClick = function()
                    net.Start("opium_camera_wanted")
                        net.WriteEntity(ply)
                        net.WriteString(reasonInput:GetValue() or "")
                    net.SendToServer()
                    confirmFrame:Remove()
                end

                local btnCancel = vgui.Create("DButton", confirmFrame)
                btnCancel:SetPos(165, 110)
                btnCancel:SetSize(135, 30)
                btnCancel:SetText("")
                btnCancel.Paint = function(self, w, h)
                    local bg = self:IsHovered() and colors.BackgroundLight or colors.Panel
                    draw.RoundedBox(4, 0, 0, w, h, bg)
                    DrawTextShadow("Annuler", "OpiumSec_Body", w / 2, h / 2, colors.TextDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
                btnCancel.DoClick = function()
                    confirmFrame:Remove()
                end
            end
        end
    end

    RefreshPlayerList()

    -- Timer de rafraîchissement
    timer.Create("opium_refresh_playerlist", 1, 0, function()
        if IsValid(cameraPanel) and isViewingCamera then
            RefreshPlayerList()
        else
            timer.Remove("opium_refresh_playerlist")
        end
    end)
end

--- Ferme la vue caméra et nettoie l'interface
function CloseCameraView()
    isViewingCamera = false
    currentCamera = NULL

    if IsValid(cameraPanel) then
        if IsValid(cameraPanel.sidePanel) then
            cameraPanel.sidePanel:Remove()
        end
        cameraPanel:Remove()
    end

    cameraPanel = nil

    timer.Remove("opium_refresh_playerlist")

    net.Start("opium_camera_exit")
    net.SendToServer()
end

-- Touche Échap pour quitter la vue caméra
hook.Add("Think", "OpiumSecurity_EscapeCamera", function()
    if isViewingCamera and input.IsKeyDown(KEY_ESCAPE) then
        CloseCameraView()
    end
end)

-- ============================================================================
-- RÉCEPTION RÉSEAU
-- ============================================================================

-- Ouvrir / changer de caméra
net.Receive("opium_camera_open", function()
    local camera = net.ReadEntity()
    if not IsValid(camera) then return end

    OpenCameraTerminal(camera)
end)

-- Forcer la fermeture (caméra détruite par exemple)
net.Receive("opium_camera_exit", function()
    CloseCameraView()
end)

-- Notification d'infraction
net.Receive("opium_camera_notify", function()
    local attackerName = net.ReadString()
    local reason = net.ReadString()
    local camName = net.ReadString()
    local attackerEntity = net.ReadEntity()

    -- Ajouter à la liste des notifications
    table.insert(notifications, {
        attacker = attackerName,
        reason = reason,
        camera = camName,
        created = CurTime(),
        expire = CurTime() + 8,
    })

    -- Marquer le joueur comme détecté pour le clignotement ESP
    if IsValid(attackerEntity) then
        detectedPlayers[attackerEntity] = CurTime() + 15
    end

    -- Son d'alerte
    surface.PlaySound("buttons/button17.wav")

    -- Message chat
    chat.AddText(
        Color(255, 80, 80), "[ALERTE] ",
        Color(255, 255, 255), attackerName,
        Color(180, 180, 180), " - " .. reason,
        Color(100, 180, 255), " (" .. camName .. ")"
    )
end)
