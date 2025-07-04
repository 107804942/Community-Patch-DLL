--==========================================================
-- UnitFlagManager
-- Known bugs:
-- destroy: check fix for need to update plot & cargo & airbase
-- subs: check visibility fix
-- flag offsets vs UI precedence
--==========================================================

local math_max = math.max
local math_min = math.min
local math_ceil = math.ceil
local math_pi = math.pi
local math_cos = math.cos
local math_sin = math.sin
local pairs = pairs
local string_format = string.format
local table_insert = table.insert
local table_remove = table.remove
local type = type

include( "EUI_utilities" )
local IconLookup = EUI.IconLookup
local IconHookup = EUI.IconHookup
local CivIconHookup = EUI.CivIconHookup
local Color = EUI.Color
local GameInfo = EUI.GameInfoCache
local PrimaryColors = EUI.PrimaryColors
local BackgroundColors = EUI.BackgroundColors
include( "EUI_unit_include" )
local ShortUnitTip = EUI.ShortUnitTip

local ContextPtr = ContextPtr
local DomainTypes_DOMAIN_AIR = DomainTypes.DOMAIN_AIR
local Events = Events
local Game = Game
local GridToWorld = GridToWorld
local InStrategicView = InStrategicView
local Locale = Locale
local Map_GetPlot = Map.GetPlot
local Map_GetPlotByIndex = Map.GetPlotByIndex
local Mouse = Mouse
local Players = Players
local PreGame = PreGame
local ReligionTypes = ReligionTypes
local ToGridFromHex = ToGridFromHex
local UI_GetUnitFlagIcon = UI.GetUnitFlagIcon
local UI_GetUnitPortraitIcon = UI.GetUnitPortraitIcon
local UnitMoving = UnitMoving

-- Cache whether Promotion Flags is active, change settings
local EUI_options = Modding.OpenUserData( "Enhanced User Interface Options", 1 )
local isPromotionFlagsEUI = EUI_options.GetValue( "PromotionFlags" ) == 1
local g_isSquadsModEnabled = Game.IsCustomModOption("SQUADS");
local b_ShowSquadNumberUnderFlag = true;

print("Promotion Flags: "..tostring(isPromotionFlagsEUI))
local PromotionFlagsSettings_ShowUnitFreePromos = false
local PromotionFlagsSettings_ShowLeaderTraitPromos = true
local PromotionFlagsSettings_ShowForPlayer = true
local PromotionFlagsSettings_ShowForOthers = true
local PromotionFlagsSettings_MaxPromosToShow = 13

local GetPlotNumUnits = Map_GetPlot(0,0).GetNumLayerUnits or Map_GetPlot(0,0).GetNumUnits
local GetPlotUnit = Map_GetPlot(0,0).GetLayerUnit or Map_GetPlot(0,0).GetUnit

local g_ScrapControls = Controls.AirCraftFlags --!!! TODO
local g_AirCraftFlags = Controls.AirCraftFlags
local g_CivilianFlags = Controls.CivilianFlags
local g_MilitaryFlags = Controls.MilitaryFlags
local g_GarrisonFlags = Controls.GarrisonFlags
local g_AirbaseControls = Controls.AirbaseFlags
local g_SelectedFlags = Controls.SelectedFlags
g_SelectedFlags:ChangeParent( ContextPtr:LookUpControl( "../SelectedUnitContainer" ) or ContextPtr )

local g_toolTipControls = {}
TTManager:GetTypeControlTable( "EUI_UnitTooltip", g_toolTipControls )

local g_SelectedFlag
local g_SelectedCargo = {}
local g_AirbaseFlags = {}
local g_UnitFlags = {}
for i = -1, #Players do
	g_UnitFlags[i]={}
end
local g_spareNewUnitFlags = {}
local g_spareAirbaseFlags = {}
local g_usedPromotions = {}
local g_sparePromotions = {}

local g_activePlayerID = Game.GetActivePlayer()
local g_activeTeamID = Game.GetActiveTeam()
local g_activePlayer = Players[ g_activePlayerID ]
local g_activeTeam = Teams[ g_activeTeamID ]

local g_colorGreen = Color( 0, 1, 0, 1 )
local g_colorYellow = Color( 1, 1, 0, 1 )
local g_colorRed = Color( 1, 0, 0, 1 )
local g_colorWhite = Color( 1, 1, 1, 1 )

--[[
local DebugPrint = print;

local function DebugUnit( playerID, unitID, ... )
	local player = Players[ playerID ]
	local unit = player and player:GetUnitByID( unitID )
	DebugPrint( "Player#", playerID, "unit#", unitID, unit and Locale.Lookup(unit:GetNameKey()), "unitXY=", unit and unit:GetX(), unit and unit:GetY(), ... )
end
local function DebugFlag( flag, ... )
	if type(flag)=="table" then
		DebugUnit( flag.m_PlayerID, flag.m_UnitID, "flagXY=", flag.m_Plot and flag.m_Plot:GetX(), flag.m_Plot and flag.m_Plot:GetY(), ... )
	else
		DebugPrint( "flag=", flag, ... )
	end
end
]]--
function SquadsOptionChanged(optionKey, newValue)
	if optionKey == "ShowSquadNumberUnderFlag" then
		b_ShowSquadNumberUnderFlag = newValue;

		local playerID = Game.GetActivePlayer();
		local pActivePlayer = Players[playerID];
		for unit in pActivePlayer:Units() do
			local unitID = unit:GetID();
			flag = g_UnitFlags[ playerID ][ unitID ];
			if flag == nil then return end

			if b_ShowSquadNumberUnderFlag then
				if unit:GetSquadNumber() > -1 then
					flag.SquadNumber:SetHide( false );
					flag.SquadNumber:SetText( tostring(unit:GetSquadNumber()) );
				end
			else
				flag.SquadNumber:SetText("");
				flag.SquadNumber:SetHide( true );
			end
		end
	end
end
if g_isSquadsModEnabled then
	LuaEvents.SQUADS_OPTIONS_CHANGED.Add(SquadsOptionChanged);
end

--==========================================================
-- Manage flag interractions with user
--==========================================================
local function UnitFlagClicked( playerID, unitID )
	Events.SerialEventUnitFlagSelected( playerID, unitID )
end

local function CargoFlagClicked( playerID, unitID )
	--print("I clicked a cargo flag!", playerID, unitID)
	local player = Players[ playerID ]
	local unit = player and player:GetUnitByID( unitID )
	if unit then
		local plot = unit:GetPlot()
		if plot then
			for i = 0, GetPlotNumUnits( plot ) - 1 do
				local cargoUnit = GetPlotUnit( plot, i )
				if cargoUnit:GetTransportUnit() == unit then
					playerID, unitID = cargoUnit:GetOwner(), cargoUnit:GetID()
					if cargoUnit:CanMove() then break end
				end
			end
		end
	end
	Events.SerialEventUnitFlagSelected( playerID, unitID )
end

local function AirbaseFlagClicked( plotIndex )
	--print("I clicked an airbase flag!", plotIndex)
	local plot = Map_GetPlotByIndex( plotIndex )
	if plot then
		local playerID, unitID
		for i = 0, GetPlotNumUnits( plot ) - 1 do
			local unit = GetPlotUnit( plot, i )
			if unit:GetDomainType() == DomainTypes_DOMAIN_AIR then
				playerID, unitID = unit:GetOwner(), unit:GetID()
				if unit:CanMove() then break end
			end
		end
		if playerID and unitID then
			Events.SerialEventUnitFlagSelected( playerID, unitID )
		end
	end
end

local function UnitFlagToolTip( button )
	local playerID, unitID = button:GetVoid1(), button:GetVoid2()
	local player = Players[ playerID ]
	local unit = player and player:GetUnitByID( unitID )
	if unit then
		local toolTipString = ShortUnitTip( unit )
		if playerID == g_activePlayerID then
			toolTipString = toolTipString .. Locale.ConvertTextKey( "TXT_KEY_UPANEL_CLICK_TO_SELECT" )
		end
		g_toolTipControls.Text:SetText( toolTipString )

		local iconIndex, iconAtlas = UI_GetUnitPortraitIcon( unit )
		IconHookup( iconIndex, 128, iconAtlas, g_toolTipControls.UnitPortrait )
 		CivIconHookup( playerID, 64, g_toolTipControls.CivIcon, g_toolTipControls.CivIconBG, g_toolTipControls.CivIconShadow, false, true )
		local i = 0
		if not( unit.IsTrade and unit:IsTrade() ) then
			for unitPromotion in GameInfo.UnitPromotions() do
				if unit:IsHasPromotion(unitPromotion.ID) and unitPromotion.ShowInUnitPanel then
					i = i + 1
					local instance = g_usedPromotions[i]
					if not instance then
						instance = table_remove( g_sparePromotions )
						if instance then
							instance.Promotion:ChangeParent( g_toolTipControls.Stack )
						else
							instance = {}
							ContextPtr:BuildInstanceForControl( "Promotion", instance, g_toolTipControls.Stack )
						end
						g_usedPromotions[i] = instance
					end
                    -- UndeadDevel/FlagPromotions: add default fallback for the 32x32 icons as well
                    if not IconHookup( unitPromotion.PortraitIndex, 32, unitPromotion.IconAtlas, instance.Promotion ) then
                        print("No 32x32 icon for ".. unitPromotion.Type .. " failing back to the yellow triangle")
                        IconHookup( 59, 32, "PROMOTION_ATLAS", instance.Promotion )
                    end
					--IconHookup( unitPromotion.PortraitIndex, 32, unitPromotion.IconAtlas, instance.Promotion )
                    -- UndeadDevel end
				end
			end
		end
		for j = i+1, #g_usedPromotions do
			table_insert( g_sparePromotions, g_usedPromotions[j] )
			g_usedPromotions[j].Promotion:ChangeParent( g_ScrapControls )
			g_usedPromotions[j] = nil
		end
		g_toolTipControls.Stack:SetWrapWidth( math_ceil( i / math_ceil( i / 10 ) ) * 26 )
		g_toolTipControls.Box:DoAutoSize()
		g_toolTipControls.Box:DoAutoSize()
	end
end

--==========================================================
local function SetFlagParent( flag )
	-- DebugFlag( flag, "SetFlagParent" ) end
	if flag.m_IsSelected then
		flag.Anchor:ChangeParent( g_SelectedFlags )
	elseif flag.m_TransportUnit or flag.m_IsAirCraft then
		flag.Anchor:ChangeParent( g_AirCraftFlags )
	elseif flag.m_IsCivilian then
		flag.Anchor:ChangeParent( g_CivilianFlags )
	elseif flag.m_IsGarrisoned then
		flag.Anchor:ChangeParent( g_GarrisonFlags )
	else
		flag.Anchor:ChangeParent( g_MilitaryFlags )
	end
end

--==========================================================
local function UpdatePlotFlags( plot )
	-- DebugPrint( "UpdatePlotFlags at plot XY=", plot:GetX(), plot:GetY() ) end
	local flags = {}
	local aflags = {}
	local unit, flag, n
	local city = plot:GetPlotCity()
	if city then
		local l, r, y = -43, 43, Game.GetActiveTeam() == city:GetTeam() and -39 or -36
		local gflags = {}
		for i = 0, GetPlotNumUnits( plot ) - 1 do
			unit = GetPlotUnit( plot, i )
			flag = g_UnitFlags[ unit:GetOwner() ][ unit:GetID() ]
			if flag and flag.m_Plot then
				if unit:IsCargo() then
				elseif flag.m_IsAirCraft then
					table_insert( aflags, unit )
				elseif unit:IsGarrisoned() then
					table_insert( gflags, flag )
				else
					table_insert( flags, flag )
				end
			end
		end
		n = #flags
		-- DebugPrint( n,"flags found in city") end
		if n == 1 then
			flags[1].Container:SetOffsetVal( r, y )
		elseif n > 1 then
			local a = -math_min(35/(n-1),20)
			local b = y-a
			for i=n, 1, -1 do
				-- DebugFlag( flags[i],"update offset at position", i ) end
				flags[i].Container:SetOffsetVal( r, a*i+b )
				SetFlagParent( flags[i] )
			end
		end
		n = #gflags
		-- DebugPrint( n,"gflags found in city") end
		if n == 1 then
			gflags[1].Container:SetOffsetVal( l, y )
		elseif n > 1 then
			local a = -math_min(35/(n-1),20)
			local b = y-a
			for i=n, 1, -1 do
				-- DebugFlag( flags[i],"update offset at position", i ) end
				gflags[i].Container:SetOffsetVal( l, a*i+b )
				SetFlagParent( gflags[i] )
			end
		end
	else
		--print("updating cargo unit plot flags")
		for i = 0, GetPlotNumUnits( plot ) - 1 do
			unit = GetPlotUnit( plot, i )
			flag = g_UnitFlags[ unit:GetOwner() ][ unit:GetID() ]
			-- DebugFlag( flag,"candidate is aircraft?", flag and flag.m_IsAirCraft ) end
			if flag and flag.m_Plot then
				if unit:IsCargo() then
					--print("found cargo")
					table_insert( aflags, unit )
				elseif flag.m_IsAirCraft then
					----print("found an aircraft")
					--table_insert( aflags, unit )
				else
					--print("found a regular dude")
					table_insert( flags, flag )
				end
			end
		end
		n = #flags
		-- DebugPrint( n,"flags found outside city") end
		if n == 1 then
			flags[1].Container:SetOffsetVal( 0, 0 )
		elseif n > 1 then
			local a = -math_min(35/(n-1),20)
			for i=n, 1, -1 do
				-- DebugFlag( flags[i],"update offset at position", i ) end
				flags[i].Container:SetOffsetVal( 0, (i-1)*a )
				SetFlagParent( flags[i] )
			end
		end
	end
	n = #aflags
	-- DebugPrint( n,"airbase flags found") end
	local plotIndex = plot:GetPlotIndex()
	flag = g_AirbaseFlags[ plotIndex ]
	if n > 0 then
		--print("found some airplanes to store")
		
		local cargoUnitInvisible = false
		for i = 0, GetPlotNumUnits( plot ) - 1 do
			unit = GetPlotUnit( plot, i )
			if(unit:HasCargo())then
				cargoUnitInvisible = unit:IsInvisible(g_activeTeam, true)
				local cargoflag = g_UnitFlags[ unit:GetOwner() ][ unit:GetID() ]
				if cargoflag then
					--print("found the transport unit")
					cargoflag.CargoBG:SetHide( true )
				end
			end
		end
		
		if not flag then
			flag = table_remove( g_spareAirbaseFlags )
			if flag then
				flag.Anchor:ChangeParent( g_AirbaseControls )
			else
				flag = {}
				ContextPtr:BuildInstanceForControl( "AirbaseFlag", flag, g_AirbaseControls )
				flag.Button:RegisterCallback( Mouse.eLClick, AirbaseFlagClicked )
			end
			g_AirbaseFlags[ plotIndex ] = flag
			local x, y, z = GridToWorld( plot:GetX(), plot:GetY() )
			
			local flatval = 25;
			if city then
				flatval = 35;
			end
			flag.Anchor:SetWorldPositionVal( x, y, z + flatval ) -- World Position Offset
			flag.Button:SetVoid1( plotIndex )
		end
		
		flag.m_IsInvisibleToActiveTeam = not city and cargoUnitInvisible
		flag.Anchor:SetHide( not plot:IsVisible( g_activeTeamID, true) or flag.m_IsInvisibleToActiveTeam)
		flag.Button:SetText( n )
		flag.Button:SetToolTipString( plot:GetAirUnitsTooltip() )
		
	elseif flag then
		--print("no airplanes here")
		flag.Button:SetText( n )
		flag.Button:SetToolTipString( plot:GetAirUnitsTooltip() )
		g_AirbaseFlags[ plotIndex ] = nil
		flag.Anchor:ChangeParent( g_ScrapControls )
		table_insert( g_spareAirbaseFlags, flag )
		if flag.m_TransportUnit then
			local carrier = g_UnitFlags[ flag.m_TransportUnit:GetOwner() ][ flag.m_TransportUnit:GetID() ]
			if carrier then
				oldCarrier.CargoBG:SetHide( true )
			end
		end
	end
end--UpdatePlotFlags

--==========================================================
local function SetFlagSelected( flag, isSelected )
	-- DebugFlag( flag, "SetFlagSelected, isSelected=", isSelected ) end
	flag.m_IsSelected = isSelected
	flag.FlagHighlight:SetHide( not isSelected )
	-- RestoreCargoFlagParents
	for i = 1, #g_SelectedCargo do
		SetFlagParent( g_SelectedCargo[i] )
		g_SelectedCargo[i] = nil
	end
	if isSelected then
		local selectedUnit = flag.m_Player:GetUnitByID( flag.m_UnitID )
		local plot = selectedUnit and selectedUnit:GetPlot()
		if plot then
			local transportUnit = selectedUnit:GetTransportUnit()
			local cargoUnit, cargoFlag
			if transportUnit then
				-- DebugFlag( flag, "selected unit is carge" ) end
				local x, y
				local transportFlag = g_UnitFlags[ transportUnit:GetOwner() ][ transportUnit:GetID() ]
				if transportFlag then
					x, y = transportFlag.Container:GetOffsetVal()
				else
					x, y = 0, 0
				end
				local cargo = transportUnit:GetCargo()
				local a = math_min( math_pi / 3, 5.7 / cargo )
				local a0 = -a*(cargo-1)/2 - math_pi
				local j = 0
				-- DebugFlag( transportFlag, "transport identified, cargo#=", cargo ) end
				for i = 0, GetPlotNumUnits( plot ) - 1 do
					cargoUnit = GetPlotUnit( plot, i )
					if cargoUnit:GetTransportUnit() == transportUnit then
						cargoFlag = g_UnitFlags[ cargoUnit:GetOwner() ][ cargoUnit:GetID() ]
						if cargoFlag then
							-- DebugFlag( cargoFlag, "added to cargo at position", j ) end
							table_insert( g_SelectedCargo, cargoFlag )
							cargoFlag.Container:SetOffsetVal( math_cos( a*j + a0 )*38 + x, math_sin( a*j + a0 )*38 + y )
							cargoFlag.Anchor:ChangeParent( g_SelectedFlags )
						end
						j = j + 1
					end
				end
			elseif flag.m_IsAirCraft then
				local airbase = {}
				for i = 0, GetPlotNumUnits( plot ) - 1 do
					cargoUnit = GetPlotUnit( plot, i )
					cargoFlag = g_UnitFlags[ cargoUnit:GetOwner() ][ cargoUnit:GetID() ]
					if cargoFlag and cargoFlag.m_IsAirCraft and not cargoUnit:GetTransportUnit() then
						table_insert( airbase, cargoFlag )
					end
				end
				local n=#airbase
				-- DebugPrint( n, "aircraft found") end
				if n > 0 then
					local a = math_min( 0.5, 2.7 / n )
					local a0 = -a*(n+1)/2 - math_pi/2
					for i = 1, n do
						cargoFlag = airbase[i]
						-- DebugFlag( cargoFlag, "adding aircraft to airbase at position", i ) end
						table_insert( g_SelectedCargo, cargoFlag )
						cargoFlag.Anchor:ChangeParent( g_SelectedFlags )
						cargoFlag.Container:SetOffsetVal( math_cos( a*i + a0 )*80, math_sin( a*i + a0 )*80 )
					end
				end
			end
		end
		g_SelectedFlag = flag
	elseif g_SelectedFlag == flag then
		g_SelectedFlag = nil
	end
	SetFlagParent( flag )
end--SetFlagSelected

--==========================================================
local function FinishMove( flag )
	-- DebugFlag( flag, "FinishMove" ) end
	-- Have we changed carrier ?
	local unit = flag.m_Unit
	local transportUnit = unit:GetTransportUnit()
	if flag.m_TransportUnit ~= transportUnit then
		if flag.m_TransportUnit then
			local oldCarrier = g_UnitFlags[ flag.m_TransportUnit:GetOwner() ][ flag.m_TransportUnit:GetID() ]
			if oldCarrier then
				local cargo = oldCarrier.m_Unit:GetCargo()
				oldCarrier.CargoBG:SetHide( cargo < 1 )
				oldCarrier.Cargo:SetText( cargo )
			end
		end
		flag.m_TransportUnit = transportUnit
		if transportUnit then
			local newCarrier = g_UnitFlags[ transportUnit:GetOwner() ][ transportUnit:GetID() ]
			if newCarrier then
				local cargo = transportUnit:GetCargo()
				newCarrier.CargoBG:SetHide( cargo < 1 )
				newCarrier.Cargo:SetText( cargo )
			end
		end
	end
	-- Have we changed location ?
	local oldPlot = flag.m_Plot
	local newPlot = unit:GetPlot()
	if oldPlot ~= newPlot then
		flag.m_Plot = newPlot
		if oldPlot then
			UpdatePlotFlags( oldPlot )
		end
		if newPlot then
			local x, y, z = GridToWorld( newPlot:GetX(), newPlot:GetY() )
			flag.Anchor:SetWorldPositionVal( x, y, z + 35 ) -- World Position Offset
			UpdatePlotFlags( newPlot )
		end
	end
end

--==========================================================
local function UpdateFlagType( flag )
	-- DebugFlag( flag, "UpdateFlagType" ) end

	local unit = flag.m_Unit
	local textureName, maskName

	if unit:IsEmbarked() then
		textureName = "UnitFlagEmbark.dds"
		maskName = "UnitFlagEmbarkMask.dds"
		flag.UnitIconShadow:SetOffsetVal( -1, -2 )

	elseif unit:IsGarrisoned() then
		textureName = "UnitFlagBase.dds"
		maskName = "UnitFlagMask.dds"
		flag.UnitIconShadow:SetOffsetVal( -1, 1 )

	elseif unit:GetFortifyTurns() > 0 then
		textureName = "UnitFlagFortify.dds"
		maskName = "UnitFlagFortifyMask.dds"
		flag.UnitIconShadow:SetOffsetVal( -1, 0 )

	elseif flag.m_IsTrade then
		textureName = "UnitFlagTrade.dds"
		maskName = "UnitFlagTradeMask.dds"
		flag.UnitIconShadow:SetOffsetVal( -1, 0 )

	elseif not flag.m_IsCivilian then
		textureName = "UnitFlagBase.dds"
		maskName = "UnitFlagMask.dds"
		flag.UnitIconShadow:SetOffsetVal( -1, 0 )
	else
		textureName = "UnitFlagCiv.dds"
		maskName = "UnitFlagCivMask.dds"
		flag.UnitIconShadow:SetOffsetVal( -1, -3 )
	end

	flag.UnitIconShadow:ReprocessAnchoring()

	flag.FlagShadow:SetTexture( textureName )
	flag.FlagBase:SetTexture( textureName )
	flag.FlagBaseOutline:SetTexture( textureName )
	flag.LightEffect:SetTexture( textureName )
	flag.HealthBarBG:SetTexture( textureName )
	flag.AlphaAnim:SetTexture( textureName )
	flag.FlagHighlight:SetTexture( textureName )
	flag.ScrollAnim:SetMask( maskName )
end--UpdateFlagType

--==========================================================
local function UpdateFlagHealth( flag, damage, unit )
	-- DebugFlag( flag, "UpdateFlagHealth, damage=", damage ) end
	if damage > 0 then
		flag.m_MaxHitPoints = unit:GetMaxHitPoints()
		local healthPercent = 1 - damage / flag.m_MaxHitPoints
		if healthPercent > 0.66 then
			flag.HealthBar:SetFGColor( g_colorGreen )
		elseif healthPercent > 0.33 then
			flag.HealthBar:SetFGColor( g_colorYellow )
		elseif healthPercent > 0 then
			flag.HealthBar:SetFGColor( g_colorRed )
		else --unit is dead...
			healthPercent = 0
		end
		-- show the health bar
		flag.HealthBar:SetPercent( healthPercent )
		flag.HealthBarBG:SetHide( false )
		flag.HealthBar:SetHide( false )
		flag.AlphaAnim:SetTextureOffsetVal( 64, 64 )
		flag.FlagHighlight:SetTextureOffsetVal( 64, 128 )
		flag.CargoBG:SetOffsetX( 35 )
	else --full health
		-- hide the health bar
		flag.HealthBarBG:SetHide( true )
		flag.HealthBar:SetHide( true )
		flag.AlphaAnim:SetTextureOffsetVal( 0, 64 )
		flag.FlagHighlight:SetTextureOffsetVal( 0, 128 )
		flag.CargoBG:SetOffsetX( 35 )
	end
end--UpdateFlagHealth

--==========================================================
-- constructor
--==========================================================
local function CreateNewFlag( playerID, unitID, isSelected, isHiddenByFog, isInvisibleToActiveTeam )

	-- DebugUnit( playerID, unitID, "CreateNewFlag, isSelected=", isSelected, "isHiddenByFog", isHiddenByFog, "isInvisibleToActiveTeam", isInvisibleToActiveTeam ) end
	local player = Players[ playerID ]
	local unit = player and player:GetUnitByID( unitID )
	if unit and not unit:IsDead() then

		local teamID = player:GetTeam()
		local isAircraft = false
		local isCivilian = false
		local parentContainer
		if unit:IsCombatUnit() and not unit:IsEmbarked() then
			parentContainer = g_MilitaryFlags
		elseif unit:GetDomainType() == DomainTypes_DOMAIN_AIR then
			parentContainer = g_AirCraftFlags
			isAircraft = true
		else
			parentContainer = g_CivilianFlags
			isCivilian = true
		end

		local flag = table_remove( g_spareNewUnitFlags )
		if flag then
			flag.Anchor:ChangeParent( parentContainer )
			flag.FlagHighlight:SetColor( g_colorWhite )
		else
			flag = {}
			ContextPtr:BuildInstanceForControl( "UnitFlag", flag, parentContainer )
			flag.Button:RegisterCallback( Mouse.eLClick, UnitFlagClicked )
			flag.Cargo:RegisterCallback( Mouse.eLClick, CargoFlagClicked )
			flag.Button:SetToolTipCallback( UnitFlagToolTip )
		end
		---------------------------------------------------------
		-- Hook up the button
		flag.Cargo:SetVoids( playerID, unitID )
		flag.Button:SetVoids( playerID, unitID )

		---------------------------------------------------------
		-- store the flag and build the table for this player
		g_UnitFlags[ playerID ][ unitID ] = flag
		flag.m_TransportUnit = nil
		flag.m_IsAirCraft = isAircraft
		flag.m_IsCivilian = isCivilian
		flag.m_IsGarrisoned = unit:IsGarrisoned()
		flag.m_IsHiddenByFog = isHiddenByFog
		flag.m_IsInvisibleToActiveTeam = isInvisibleToActiveTeam
		flag.m_Plot = nil
		flag.m_IsSelected = isSelected
		flag.m_IsTrade = unit.IsTrade and unit:IsTrade()
		flag.m_MaxHitPoints = unit:GetMaxHitPoints()
		flag.m_Player = player
		flag.m_PlayerID = playerID
		flag.m_Unit = unit
		flag.m_UnitID = unitID

		---------------------------------------------------------
		-- Set Colors
		flag.FlagBase:SetColor( BackgroundColors[ playerID ] )
		local color = PrimaryColors[  playerID ]
		flag.UnitIcon:SetColor( color )
		flag.FlagBaseOutline:SetColor( color )

		---------------------------------------------------------
		-- Set Textures
		local flagOffset, flagAtlas = UI_GetUnitFlagIcon( unit )
		local textureOffset, textureSheet = IconLookup( flagOffset, 32, flagAtlas )
		flag.UnitIcon:SetTexture( textureSheet )
		flag.UnitIconShadow:SetTexture( textureSheet )
		flag.UnitIcon:SetTextureOffset( textureOffset )
		flag.UnitIconShadow:SetTextureOffset( textureOffset )

		---------------------------------------------------------
		-- Can carry units
		local cargo = unit:GetCargo()
		flag.CargoBG:SetHide( cargo < 1 )
		flag.Cargo:SetText( cargo )

		if g_isSquadsModEnabled and unit:GetSquadNumber() > -1 and b_ShowSquadNumberUnderFlag then
			flag.SquadNumber:SetHide( false )
			flag.SquadNumber:SetText( tostring(unit:GetSquadNumber()) )
		else
			flag.SquadNumber:SetHide( true )
			flag.SquadNumber:SetText( "" )
		end
		---------------------------------------------------------
		-- update all other info
		flag.Anchor:SetHide( isHiddenByFog or isInvisibleToActiveTeam )
		flag.FlagShadow:SetAlpha( unit:CanMove() and 1 or 0.5 )
		flag.Button:SetDisabled( g_activeTeamID ~= teamID )
		flag.Button:SetConsumeMouseOver( g_activeTeamID == teamID )
		UpdateFlagType( flag )
		UpdateFlagHealth( flag, unit:GetDamage(), unit )
		SetFlagSelected( flag, isSelected )
		if not isSelected and g_activeTeam:IsAtWar( teamID ) then
			flag.FlagHighlight:SetHide( false )
			flag.FlagHighlight:SetColor( g_colorRed )
		end
		FinishMove( flag )

		return flag
	else
		-- DebugUnit( playerID, unitID, "is nil or dead" ) end
	end

end--CreateNewFlag

--==========================================================
local function DestroyFlag( flag )
	--print("Destroying Flag Player/ID", flag.m_PlayerID, flag.m_UnitID )
	--DebugFlag( flag, "DestroyFlag" ) end
	flag.Anchor:ChangeParent( g_ScrapControls )
	table_insert( g_spareNewUnitFlags, flag )
	g_UnitFlags[ flag.m_PlayerID ][ flag.m_UnitID ] = nil
	if flag.m_Plot then
		--print("Destroying Flag Has Plot, Player/ID:", flag.m_PlayerID, flag.m_UnitID )
		UpdatePlotFlags( flag.m_Plot )
	end
end--DestroyFlag

--==========================================================
local function ForceHide( playerID, unitID, isForceHide )
	-- DebugUnit( playerID, unitID, "ForceHide, isForceHide=", isForceHide ) end
	local flag = g_UnitFlags[ playerID ][ unitID ]
	if flag then
		flag.Anchor:SetHide( isForceHide or flag.m_IsHiddenByFog or flag.m_IsInvisibleToActiveTeam )
	end
end--ForceHide

-- ak/FlagPromotions
local function AddPromotionIcon(flag, promoID, iconPositionID)
	local button = flag['Promotion'..iconPositionID]
	local promo = GameInfo.UnitPromotions[promoID]
	local player = Players[flag.m_PlayerID]
	local unit = player:GetUnitByID(flag.m_UnitID)
	
	--button:UnloadTexture()
	if not IconHookup( promo.PortraitIndex, 16, promo.IconAtlas, button ) then
		print("No 16x16 icon for ".. promo.Type .. " failing back to the yellow triangle")
		IconHookup( 59, 16, "PROMOTION_ATLAS", button )
	end
	
	local hoverText = ""
	if promo.SimpleHelpText then
		hoverText = string.format("[COLOR_YELLOW]%s[ENDCOLOR]", Locale.ConvertTextKey(promo.Help))
	else
		hoverText = string.format("[COLOR_YELLOW]%s[ENDCOLOR][NEWLINE]%s",
			Locale.ConvertTextKey(promo.Description),
			Locale.ConvertTextKey(promo.Help)
		)
	end	
--	if PromotionFlagsSettings.Debug then hoverText = hoverText .. "[NEWLINE]" .. promo.Type end
	
	-- add earlier rank promotions to the tooltip (eg add Drill 1 if we have Drill 2)
	local rankNum = promo.RankNumber - 1
	while rankNum > 0 do
		for nextPromo in GameInfo.UnitPromotions{RankList = promo.RankList, RankNumber = rankNum} do
			if unit:IsHasPromotion(nextPromo.ID) then
				if nextPromo.SimpleHelpText then
					hoverText = string.format("%s[NEWLINE][COLOR_YELLOW]%s[ENDCOLOR]",
						hoverText,
						Locale.ConvertTextKey(nextPromo.Help)
					)
				else
					hoverText = string.format("%s[NEWLINE][COLOR_YELLOW]%s[ENDCOLOR][NEWLINE]%s",
						hoverText,
						Locale.ConvertTextKey(nextPromo.Description),
						Locale.ConvertTextKey(nextPromo.Help)
					)
				end
--				if PromotionFlagsSettings.Debug then hoverText = hoverText .. "[NEWLINE]" .. nextPromo.Type end
			end
		end
		rankNum = rankNum - 1
	end
	
	button:SetToolTipString(hoverText)
end

local function UpdatePromotions(playerID, unitID)
	local flag = g_UnitFlags[ playerID ][ unitID ]
	if flag == nil then 
		-- DebugPrint("UpdatePromotions, No flag! playerID:" .. tostring(playerID) .. ", unitID:" .. tostring(unitID))
		return
	end

	if not PromotionFlagsSettings_ShowForPlayer and g_activePlayerID == playerID then
		return
	end
	if not PromotionFlagsSettings_ShowForOthers and g_activePlayerID ~= playerID then
		return
	end

	
	local player = Players[playerID]
	local unit = player:GetUnitByID(unitID)
	if unit == nil then 
		--that's weird, ah well nevermind!
		-- DebugPrint("UpdatePromotions, flag exists but, unit appears to be nil, bailing out... playerID:" .. tostring(playerID) ..  ", unitID:".. tostring(unitID))
		return
	end

	local iconPositionID	= 1
	local promos			= {}	
	local unitType = GameInfo.Units[unit:GetUnitType()].Type


	for promo in GameInfo.UnitPromotions() do
		local promoID = promo.ID
		if unit:IsHasPromotion(promoID) and promo.IsVisibleAboveFlag then
			local showPromo = true
			
			--don't show promos from leader traits
			if not PromotionFlagsSettings_ShowLeaderTraitPromos then
				local leaderType = player:GetLeaderType();
				local leaderInfo = GameInfo.Leaders[leaderType];
				local unitCombatInfoType = GameInfo.UnitCombatInfos[unit:GetUnitCombatType()].Type
				
				for l in GameInfo.Leader_Traits{LeaderType = leaderInfo.Type} do 
					for t in GameInfo.Trait_FreePromotionUnitCombats{TraitType = l.TraitType} do 
						if unitCombatInfoType == t.UnitCombatType and promo.Type == t.PromotionType then
							showPromo = false
						end
					end				
				end
			end

			-- don't show promos that automatically come with the unit
			for freepromo in GameInfo.Unit_FreePromotions{UnitType=unitType} do
				if promo.Type == freepromo.PromotionType and not PromotionFlagsSettings_ShowUnitFreePromos then
					showPromo = false
				end
			end

			if promo.RankList then
				-- hide promotion if the unit has a higher rank of that promotion (eg. hide Drill 1 if we have Drill 2)
				--for nextPromo in GameInfo.UnitPromotions{RankList = promo.RankList, RankNumber = promo.RankNumber + 1} do
				for nextPromo in GameInfo.UnitPromotions{RankList = promo.RankList} do
					if unit:IsHasPromotion(nextPromo.ID) and nextPromo.RankNumber > promo.RankNumber then
						showPromo = false
						break
					end					
				end
			end
			
			if showPromo then
				table.insert(promos, promoID)
			end
		end		
	end						
  
	table.sort(promos, function(a, b)
		return GameInfo.UnitPromotions[a].FlagPromoOrder < GameInfo.UnitPromotions[b].FlagPromoOrder
	end)

	local iPromotionsStackMax = math.min(13, (PromotionFlagsSettings_MaxPromosToShow or 13))
	for iconPositionID = 1, iPromotionsStackMax do
		local button = flag['Promotion'..iconPositionID]
		button:UnloadTexture()
		if promos[iconPositionID] then
			--local p = GameInfo.UnitPromotions[promos[iconPositionID]]
			AddPromotionIcon(flag, promos[iconPositionID], iconPositionID)
			button:SetHide(false)
		else
			button:SetHide(true)
		end
	end	

	flag.EarnedPromotionStack1:CalculateSize()
	flag.EarnedPromotionStack1:ReprocessAnchoring()
	
	flag.EarnedPromotionStack2:CalculateSize()
	flag.EarnedPromotionStack2:ReprocessAnchoring()
end

--==========================================================
-- On Unit Created
--==========================================================
Events.SerialEventUnitCreated.Add(
function( playerID, unitID, hexPos, unitType, cultureType, civID, primaryColor, secondaryColor, unitFlagIndex, fogState, isSelected, isMilitary, isVisible )
	-- DebugUnit( playerID, unitID, "SerialEventUnitCreated, fogState=", fogState, "isSelected=", isSelected, "isVisible=", isVisible, "XY=", ToGridFromHex( hexPos.x, hexPos.y ) ) 
	CreateNewFlag( playerID, unitID, isSelected, fogState ~= 2, not isVisible )
	-- ak
--	UpdatePromotions(playerID, unitID)

end)
if isPromotionFlagsEUI then
	Events.SerialEventUnitCreated.Add(UpdatePromotions)
end
--==========================================================
-- On Unit Position Changed
-- sent by the engine while it walks a unit around
--==========================================================
Events.LocalMachineUnitPositionChanged.Add(
function( playerID, unitID, unitPosition )
	-- DebugUnit( playerID, unitID, "LocalMachineUnitPositionChanged" ) end
	local flag = g_UnitFlags[ playerID ][ unitID ]
	if flag then
		-- DebugFlag( flag, "Setting flag position while moving" ) end
		flag.Anchor:SetWorldPositionVal( unitPosition.x, unitPosition.y, unitPosition.z + 35 ) -- World Position Offset
		local plot = flag.m_Plot
		if plot then
			if UnitMoving( playerID, unitID ) then
				flag.m_Plot = nil
			end
			local targetPlot = flag.m_Unit:GetPlot()
			if targetPlot ~= plot then
				UpdatePlotFlags( plot )
				-- DebugFlag( flag, "starting to move: setting flag offset to", 0, 0 ) end
				return flag.Container:SetOffsetVal( 0, 0 )
			end
		end
	else
		-- DebugUnit( playerID, unitID, "not found for LocalMachineUnitPositionChanged" ) end
	end
end)

--==========================================================
-- On Flag Type Change
--==========================================================
local function OnFlagTypeChange( playerID, unitID )
	-- DebugUnit( playerID, unitID, "OnFlagTypeChange" ) end
	local flag = g_UnitFlags[ playerID ][ unitID ]
	if flag then
		UpdateFlagType( flag )
	end
end
Events.UnitActionChanged.Add( OnFlagTypeChange )
Events.UnitEmbark.Add( OnFlagTypeChange ) -- GameplayUnitEmbark

--==========================================================
-- On Unit Move Queue Changed
--==========================================================
local function OnUnitMoveQueueChanged( playerID, unitID, hasRemainingMoves )
	-- DebugUnit( playerID, unitID, "OnUnitMoveQueueChanged, hasRemainingMoves=", hasRemainingMoves ) end
	local flag = g_UnitFlags[ playerID ][ unitID ]
	if flag then
		return FinishMove( flag )
	end
end--OnUnitMoveQueueChanged
Events.UnitMoveQueueChanged.Add( OnUnitMoveQueueChanged )

Events.SerialEventUnitTeleportedToHex.Add(
function( hexX, hexY, playerID, unitID )
	-- DebugUnit( playerID, unitID, "SerialEventUnitTeleportedToHex, XY=", ToGridFromHex( hexX, hexY ) ) end
	-- nukes teleport instead of moving
	-- spoof out the move queue changed logic.
	OnUnitMoveQueueChanged( playerID, unitID )
end)

--==========================================================
-- On Unit Visibility Changed (GameplayUnitVisibility)
--==========================================================
Events.UnitVisibilityChanged.Add(
function( playerID, unitID, isVisible, checkFlag )--, blendTime )
	-- DebugUnit( playerID, unitID, "UnitVisibilityChanged, isVisible=", isVisible, "checkFlag=", checkFlag ) end
	if checkFlag then
		local flag = g_UnitFlags[ playerID ][ unitID ]
		if flag then
			flag.m_IsInvisibleToActiveTeam = not isVisible
			flag.Anchor:SetHide( not isVisible or flag.m_IsInvisibleToActiveTeam or flag.m_IsHiddenByFog )
		end
	end
end)

--==========================================================
-- On Unit Destroyed (GameplayUnitDestroyed)
--==========================================================
Events.SerialEventUnitDestroyed.Add(
function( playerID, unitID )
	-- DebugUnit( playerID, unitID, "SerialEventUnitDestroyed" ) end
	local flag = g_UnitFlags[ playerID ][ unitID ]
	if flag then
		DestroyFlag( flag )
	else
		-- DebugUnit( playerID, unitID, "flag not found for SerialEventUnitDestroyed" ) end
	end
end)

--==========================================================
-- On Unit Selection Change
--==========================================================
Events.UnitSelectionChanged.Add(
function( playerID, unitID, _, _, _, isSelected )
	-- DebugUnit( playerID, unitID, "UnitSelectionChanged, isSelected=", isSelected ) end
	local flag = g_UnitFlags[ playerID ][ unitID ]
	if flag then
		SetFlagSelected( flag, isSelected )
		if isPromotionFlagsEUI then
			UpdatePromotions(playerID, unitID)
		end
	else
		-- DebugUnit( playerID, unitID, "flag not found for UnitSelectionChanged", isSelected ) end
	end
end)

--==========================================================
-- GameplayUnitSetDamage is called only if
-- the amount of damage actually changed
--==========================================================
Events.SerialEventUnitSetDamage.Add(
function( playerID, unitID, damage )--, previousDamage )
	-- !!! can be called for dead unit !!!
	-- DebugUnit( playerID, unitID, "SerialEventUnitSetDamage, damage=", damage ) end
	local flag = g_UnitFlags[ playerID ][ unitID ]
	if flag then
		local player = Players[ playerID ]
		local unit = player and player:GetUnitByID( unitID )
		if unit  then
			UpdateFlagHealth( flag, damage, unit )
		end
	else
		-- DebugUnit( playerID, unitID, "flag not found for SerialEventUnitSetDamage" ) end
	end
end)

--==========================================================
-- this goes off when a hex is seen or unseen
--==========================================================
Events.HexFOWStateChanged.Add(
function( hexPos, fogState, isWholeMap )
	-- DebugPrint( "HexFOWStateChanged, fogState=", fogState, "isWholeMap=", isWholeMap, "XY=", ToGridFromHex( hexPos.x, hexPos.y ) ) end
	local isInvisible = fogState ~= 2 -- eyes on
	if isWholeMap then
		-- unit flags
		for playerID = 0, #Players do
			for unitID, flag in pairs( g_UnitFlags[ playerID ] ) do
				flag.m_IsHiddenByFog = isInvisible
				flag.Anchor:SetHide( isInvisible or flag.m_IsInvisibleToActiveTeam )
			end
		end
		-- city flags
		for plotIndex, flag in pairs( g_AirbaseFlags ) do
			flag.Anchor:SetHide( isInvisible or flag.m_IsInvisibleToActiveTeam )
		end
	else
		local plot = Map_GetPlot( ToGridFromHex( hexPos.x, hexPos.y ) )
		if plot then
			-- unit flags
			for i = 0, GetPlotNumUnits( plot ) - 1 do
				local unit = GetPlotUnit( plot, i )
				local flag = unit and g_UnitFlags[ unit:GetOwner() ][ unit:GetID() ]
				if flag then
					flag.m_IsHiddenByFog = isInvisible
					flag.Anchor:SetHide( isInvisible or flag.m_IsInvisibleToActiveTeam )
				end
			end
			-- city flag
			local flag = g_AirbaseFlags[ plot:GetPlotIndex() ]
			if flag then
				flag.Anchor:SetHide( isInvisible or flag.m_IsInvisibleToActiveTeam)
			end
		end
	end
end)

--==========================================================
-- this goes off when a unit moves into or out of the fog
--==========================================================
Events.UnitStateChangeDetected.Add(
function( playerID, unitID, fogState )
	-- DebugUnit( playerID, unitID, "UnitStateChangeDetected, fogState=", fogState ) end
	local flag = g_UnitFlags[ playerID ][ unitID ]
	if flag then
		flag.m_IsHiddenByFog = fogState ~=2
		flag.Anchor:SetHide( fogState ~=2 or flag.m_IsInvisibleToActiveTeam )
	else
		-- DebugUnit( playerID, unitID, "flag not found for UnitStateChangeDetected", fogState ) end
	end
end)

--==========================================================
-- this goes off when GameplayUnitShouldDimFlag
-- decides a unit's flag dimming should change
--==========================================================
Events.UnitShouldDimFlag.Add(
function( playerID, unitID, isDimmed )
	-- DebugUnit( playerID, unitID, "UnitShouldDimFlag, isDimmed=", isDimmed ) end
	local flag = g_UnitFlags[ playerID ][ unitID ]
	if flag then
		flag.FlagShadow:SetAlpha( isDimmed and 0.5 or 1.0 )
	else
		-- DebugUnit( playerID, unitID, "flag not found for UnitShouldDimFlag" ) end
	end
end)

--==========================================================
-- On Unit Garrison
--==========================================================
Events.UnitGarrison.Add(
function( playerID, unitID, isGarrisoned )
	-- DebugUnit( playerID, unitID, "UnitGarrison, isGarrisoned=", isGarrisoned ) end
	local flag = g_UnitFlags[ playerID ][ unitID ]
	if flag then
		flag.m_IsGarrisoned = isGarrisoned
		SetFlagParent( flag )
		UpdateFlagType( flag )
	end
end)

--==========================================================
-- On City Created / Destroyed / Captured
--==========================================================
local function OnCity( hexPos )
	-- DebugPrint( "SerialEventCityDestroyed or SerialEventCityCaptured, XY=", ToGridFromHex( hexPos.x, hexPos.y ) ) end
	local plot = Map_GetPlot( ToGridFromHex( hexPos.x, hexPos.y ) )
	if plot then
		UpdatePlotFlags( plot )
	end
end
Events.SerialEventCityDestroyed.Add( OnCity )
Events.SerialEventCityCaptured.Add( OnCity )
Events.SerialEventCityCreated.Add( OnCity )

Events.SerialEventEnterCityScreen.Add(
function()
	g_SelectedFlags:SetHide( true )
end)
Events.SerialEventExitCityScreen.Add(
function()
	g_SelectedFlags:SetHide( InStrategicView() )
end)

--==========================================================
Events.StrategicViewStateChanged.Add( function( isStrategicView, isCityBanners )
	-- DebugPrint( "StrategicViewStateChanged, isStrategicView=", isStrategicView, "isCityBanners=", isCityBanners ) end
	g_CivilianFlags:SetHide( isStrategicView )
	g_MilitaryFlags:SetHide( isStrategicView )
	g_GarrisonFlags:SetHide( isStrategicView and not isCityBanners )
	g_AirbaseControls:SetHide( isStrategicView )
	g_SelectedFlags:SetHide( isStrategicView )
end)

--==========================================================
-- Hide flag during combat
--==========================================================
Events.RunCombatSim.Add(
function( m_AttackerPlayerID,
		m_AttackerUnitID,
		m_AttackerUnitDamage,
		m_AttackerFinalUnitDamage,
		m_AttackerMaxHitPoints,
		m_DefenderPlayerID,
		m_DefenderUnitID,
		m_DefenderUnitDamage,
		m_DefenderFinalUnitDamage,
		m_DefenderMaxHitPoints,
		m_bContinuation )
	-- DebugUnit( m_AttackerPlayerID, m_AttackerUnitID, "RunCombatSim", m_AttackerUnitDamage, m_AttackerFinalUnitDamage, m_AttackerMaxHitPoints, m_DefenderPlayerID, m_DefenderUnitID, m_DefenderUnitDamage, m_DefenderFinalUnitDamage, m_DefenderMaxHitPoints, m_bContinuation ) end
	ForceHide( m_AttackerPlayerID, m_AttackerUnitID, true )
	ForceHide( m_DefenderPlayerID, m_DefenderUnitID, true )
end)

--==========================================================
-- Show flag after combat
--==========================================================
Events.EndCombatSim.Add(
function( m_AttackerPlayerID,
		m_AttackerUnitID,
		m_AttackerUnitDamage,
		m_AttackerFinalUnitDamage,
		m_AttackerMaxHitPoints,
		m_DefenderPlayerID,
		m_DefenderUnitID,
		m_DefenderUnitDamage,
		m_DefenderFinalUnitDamage,
		m_DefenderMaxHitPoints )
	-- DebugUnit( m_AttackerPlayerID, m_AttackerUnitID, "EndCombatSim", m_AttackerUnitDamage, m_AttackerFinalUnitDamage, m_AttackerMaxHitPoints, m_DefenderPlayerID, m_DefenderUnitID, m_DefenderUnitDamage, m_DefenderFinalUnitDamage, m_DefenderMaxHitPoints ) end
	ForceHide( m_AttackerPlayerID, m_AttackerUnitID, false )
	ForceHide( m_DefenderPlayerID, m_DefenderUnitID, false )
end)

--==========================================================
-- War Declared
--==========================================================
Events.WarStateChanged.Add(
function( teamID1, teamID2, isAtWar )
	if teamID1 == g_activeTeamID then
		teamID1 = teamID2
	elseif teamID2 ~= g_activeTeamID then
		return
	end
	local isAtPeace = not isAtWar
	for playerID = 0, #Players do
		local player = Players[playerID]
		if player and player:IsAlive() and player:GetTeam() == teamID1 then
			for unitID, flag in pairs( g_UnitFlags[playerID] ) do
				flag.FlagHighlight:SetHide( isAtPeace )
				flag.FlagHighlight:SetColor( isAtPeace and g_colorWhite or g_colorRed )
			end
		end
	end
end)

--==========================================================
-- 'Active' (local human) player has changed TODO
--==========================================================
Events.GameplaySetActivePlayer.Add( function( activePlayerID )--, iPrevActivePlayerID )
	-- DebugPrint( "GameplaySetActivePlayer, activePlayerID=", activePlayerID ) end
	g_activePlayerID = activePlayerID
	g_activeTeamID = Game.GetActiveTeam()
	g_activePlayer = Players[ activePlayerID ]
	g_activeTeam = Teams[ g_activeTeamID ]
	if g_SelectedFlag then
		SetFlagSelected( g_SelectedFlag, false )
	end
	for playerID = 0, #Players do
		local player = Players[ playerID ]
		if player and player:IsAlive() then
			local teamID = player:GetTeam()
			local isActiveTeam = teamID == g_activeTeamID
			local isAtPeace = not g_activeTeam:IsAtWar( teamID )
			for unitID, flag in pairs( g_UnitFlags[playerID] ) do
				flag.Button:SetDisabled( not isActiveTeam )
				flag.Button:SetConsumeMouseOver( isActiveTeam )
				flag.FlagHighlight:SetHide( isAtPeace )
				flag.FlagHighlight:SetColor( isAtPeace and g_colorWhite or g_colorRed )
			end
		end
	end
end)

-- Remove this in case of performance issues, see the following comment from FlagPromotions: 
-- Considered removing this, as flags are updated as the promos are added.
-- But given that it takes less than a tenth of a second even late game,
-- it seems worth leaving in to make sure everything is up to date.
local function RefreshUnitPromotionsGlobally()
	local swStart = os.clock()
	local unitCount = 0
	for playerID,unitList in pairs(g_UnitFlags) do
		for unitID,flag in pairs(unitList) do
			UpdatePromotions(playerID, unitID)
			unitCount = unitCount + 1
		end
	end
	print(string.format("RefreshUnitPromotionsGlobally processed %i units in %.3f seconds", unitCount, os.clock()-swStart))
end

local function OnPromotionEvent(playerID, unitID, promoType)
	--DebugPrint( "OnPromotionEvent, playerID:" .. tostring(playerID) .. " unitID:" .. tostring(unitID) .. ", promoType:" .. tostring(promoType))
	UpdatePromotions(playerID, unitID)
end

if isPromotionFlagsEUI then
	Events.ActivePlayerTurnStart.Add( RefreshUnitPromotionsGlobally); 

	GameEvents.UnitPromoted.Add(OnPromotionEvent);
	Events.SerialEventUnitCreated.Add(UpdatePromotions);
	
	LuaEvents.PromoFlagsToggleShowUnitFreePromos.Add(function()
		PromotionFlagsSettings_ShowUnitFreePromos = not PromotionFlagsSettings_ShowUnitFreePromos; 
		RefreshUnitPromotionsGlobally()
	end);
end

if g_isSquadsModEnabled then
	LuaEvents.OnSquadChangeEvent.Add(function(playerID, unitID)
		local flag = g_UnitFlags[ playerID ][ unitID ]
		if flag == nil then return end
		
		local player = Players[playerID]
		local unit = player:GetUnitByID(unitID)
		if unit == nil then return end

		if unit:GetSquadNumber() > -1 and b_ShowSquadNumberUnderFlag then
			flag.SquadNumber:SetHide( false )
			flag.SquadNumber:SetText( tostring(unit:GetSquadNumber()) )
		else
				flag.SquadNumber:SetText("");
				flag.SquadNumber:SetHide( true );
		end
	end)
end

--==========================================================
-- on shutdown, we need to get our children back,
-- or they will get duplicted on future hotload
-- and we'll assert clearing the registered button handler
--==========================================================
ContextPtr:SetShutdown( function()
	-- DebugPrint( "SetShutdown" ) end
	g_SelectedFlags:ChangeParent( ContextPtr )
end)

--==========================================================
-- scan for all units when we are loaded
-- this keeps the flags from disappearing on hotload
--==========================================================
if ContextPtr:IsHotLoad() then
	-- DebugPrint( "IsHotLoad" ) end
	-- DestroyFlag any existing unit flags
	for playerID = 0, #Players do
		-- DebugPrint( playerID, "flag count:", #g_UnitFlags )end
		for unitID, flag in pairs( g_UnitFlags[playerID] ) do
			DestroyFlag( flag )
		end
	end
	for playerID = 0, #Players do
		local player = Players[playerID]
		if player and player:IsAlive() then
			for unit in player:Units() do
				local plot = unit:GetPlot()
				CreateNewFlag( playerID, unit:GetID(), unit:IsSelected(), plot and not plot:IsVisible( g_activeTeamID, true ),
				unit:IsInvisible( g_activeTeamID, true ) or (unit:IsCargo() and unit:GetTransportUnit():IsInvisible(g_activeTeamID, true)))
			end
		end
	end
end
