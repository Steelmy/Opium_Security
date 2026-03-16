--[[
    Opium Security - Configuration Partagée
    Fichier chargé automatiquement par le serveur ET le client.
    Modifie les valeurs ci-dessous pour adapter l'addon à ton serveur.
]]

OpiumSecurity = OpiumSecurity or {}
OpiumSecurity.Config = OpiumSecurity.Config or {}

-- ============================================================================
-- JOBS DE POLICE (à configurer selon ton serveur DarkRP)
-- Ajoute ici tous les team IDs qui doivent recevoir les alertes caméra
-- et pouvoir utiliser le système de recherche.
-- ============================================================================
OpiumSecurity.Config.PoliceTeams = {
    -- Décommente et adapte selon tes jobs :
    -- TEAM_POLICE,
    -- TEAM_CHIEF,
    -- TEAM_MAYOR,
    -- TEAM_FBI,
    -- TEAM_SWAT,
}

-- ============================================================================
-- PARAMÈTRES DE LA CAMÉRA
-- ============================================================================

-- Rayon de détection de la caméra (en unités Source)
OpiumSecurity.Config.DetectionRadius = 1500

-- Angle du champ de vision de la caméra (en degrés, demi-angle)
OpiumSecurity.Config.DetectionFOV = 90

-- Distance maximale pour l'affichage ESP (en unités Source)
OpiumSecurity.Config.ESPMaxDistance = 2000

-- Hauteur au-dessus de la tête du joueur pour l'affichage ESP
OpiumSecurity.Config.ESPHeightOffset = 15

-- ============================================================================
-- PARAMÈTRES DU SYSTÈME DE RECHERCHE
-- ============================================================================

-- Durée de l'avis de recherche automatique (en secondes)
OpiumSecurity.Config.WantedDuration = 300

-- Raison affichée pour l'avis de recherche automatique
OpiumSecurity.Config.WantedReason = "Agression sur un citoyen"

-- Cooldown entre deux détections pour le même joueur (en secondes)
-- Évite le spam de notifications
OpiumSecurity.Config.DetectionCooldown = 10

-- ============================================================================
-- PARAMÈTRES VISUELS
-- ============================================================================

-- Couleurs de l'interface
OpiumSecurity.Config.Colors = {
    Background      = Color(18, 18, 24, 245),
    BackgroundLight  = Color(28, 28, 38, 255),
    Accent          = Color(0, 180, 255, 255),
    AccentDark      = Color(0, 120, 200, 255),
    Danger          = Color(220, 50, 50, 255),
    DangerGlow      = Color(255, 60, 60, 80),
    Success         = Color(50, 200, 80, 255),
    Text            = Color(220, 220, 230, 255),
    TextDim         = Color(140, 140, 160, 255),
    Border          = Color(60, 60, 80, 255),
    Panel           = Color(22, 22, 32, 250),
}

-- Vitesse de clignotement du cadre rouge (en secondes par cycle)
OpiumSecurity.Config.BlinkSpeed = 0.5

-- ============================================================================
-- FONCTIONS UTILITAIRES PARTAGÉES
-- ============================================================================

--- Vérifie si un joueur fait partie des forces de l'ordre
-- @param ply Player Le joueur à vérifier
-- @return boolean
function OpiumSecurity.IsPolice(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return false end

    local team = ply:Team()
    for _, policeTeam in ipairs(OpiumSecurity.Config.PoliceTeams) do
        if team == policeTeam then
            return true
        end
    end

    return false
end

--- Vérifie si une position est dans le champ de vision d'une caméra
-- @param camPos Vector Position de la caméra
-- @param camAng Angle Angle de la caméra
-- @param targetPos Vector Position de la cible
-- @return boolean
function OpiumSecurity.IsInCameraFOV(camPos, camAng, targetPos)
    local dir = (targetPos - camPos):GetNormalized()
    local forward = camAng:Forward()
    local dot = forward:Dot(dir)
    local halfFOV = math.cos(math.rad(OpiumSecurity.Config.DetectionFOV))

    return dot >= halfFOV
end

--- Vérifie la ligne de vue entre deux positions
-- @param from Vector Position de départ
-- @param to Vector Position cible
-- @param ignoreEntity Entity Entité à ignorer dans le trace
-- @return boolean
function OpiumSecurity.HasLineOfSight(from, to, ignoreEntity)
    local trace = util.TraceLine({
        start = from,
        endpos = to,
        filter = ignoreEntity,
        mask = MASK_VISIBLE,
    })

    return not trace.Hit or (IsValid(trace.Entity) and trace.Entity:IsPlayer())
end
