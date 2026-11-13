// ---------------------------------------------------------------------------------------------------------
// entities/pcmod_base/filesystem.lua - hard-drive path helpers and file API.
// Included by pcmod_base/shared.lua inside its SERVER block.
// ---------------------------------------------------------------------------------------------------------

		// Internal path helpers. The hard drive table uses keys such as
		// "/mydocs/text/" for folders and "/mydocs/text/a.txt" for files, so
		// every public helper normalises its input before looking anything up.
		local function FS_NormalizePath( path )
			if (path == nil) then return "" end
			path = tostring( path )
			path = string.gsub( path, "\\", "/" )
			path = string.gsub( path, "/+", "/" )
			while (string.Left( path, 1 ) == "/") do
				path = string.sub( path, 2 )
			end
			while ((string.len( path ) > 0) && (string.Right( path, 1 ) == "/")) do
				path = string.sub( path, 1, string.len( path ) - 1 )
			end
			return path
		end

		local function FS_HardDrive( ent )
			local data = PCMod.Data[ ent:EntIndex() ]
			if (!data) then return nil end
			if (!data.HardDrive) then data.HardDrive = {} end
			return data.HardDrive
		end

		local function FS_FindKey( hd, path )
			if (!hd) then return nil end
			local norm = FS_NormalizePath( path )
			if (norm == "") then return nil end
			local direct = "/" .. norm
			if (hd[ direct ]) then return direct end
			if (hd[ direct .. "/" ]) then return direct .. "/" end
			// Older code (and FileList) treated paths case-insensitively.
			local lower = string.lower( direct )
			for key, _ in pairs( hd ) do
				local k = string.lower( key )
				if ((k == lower) || (k == lower .. "/")) then return key end
			end
			return nil
		end

		local function FS_ParentPath( path )
			local norm = FS_NormalizePath( path )
			for i = string.len( norm ), 1, -1 do
				if (string.sub( norm, i, i ) == "/") then
					return string.sub( norm, 1, i - 1 )
				end
			end
			return ""
		end

		local function FS_Basename( path )
			local norm = FS_NormalizePath( path )
			if (norm == "") then return "" end
			local name = string.match( norm, "([^/]+)$" )
			return name or norm
		end

		function ENT:IsPathLocked( path )
			local hd = FS_HardDrive( self )
			if (!hd) then return false end
			local norm = FS_NormalizePath( path )
			if (norm == "") then return false end
			local cur = ""
			for _, seg in ipairs( string.Explode( "/", norm ) ) do
				if (seg != "") then
					if (cur == "") then cur = seg else cur = cur .. "/" .. seg end
					local key = FS_FindKey( hd, cur )
					if (key && hd[ key ].Locked) then return true end
				end
			end
			return false
		end

		function ENT:MakeFolder( path )
			local hd = FS_HardDrive( self )
			if (!hd) then return false end
			local norm = FS_NormalizePath( path )
			if (norm == "") then return true end
			if (self:IsPathLocked( norm )) then
				PCMod.Msg( "Tried to create a folder in a locked path: " .. norm .. " (" .. tostring( self:EntIndex() ) .. ")", true )
				return false
			end
			local cur = ""
			for _, seg in ipairs( string.Explode( "/", norm ) ) do
				if (seg != "") then
					if (cur == "") then cur = seg else cur = cur .. "/" .. seg end
					local key = FS_FindKey( hd, cur )
					if (key) then
						if (hd[ key ].ItemType != "folder") then return false end
					else
						local item = {}
						item.ItemType = "folder"
						item.ItemName = cur
						item.ItemContent = ""
						item.Locked = false
						hd[ "/" .. cur .. "/" ] = item
					end
				end
			end
			return true
		end

		function ENT:ListDir( path )
			local out = {}
			local hd = FS_HardDrive( self )
			if (!hd) then return out end
			local norm = FS_NormalizePath( path )
			local prefix = "/" .. norm
			if (norm != "") then prefix = prefix .. "/" end
			local seen = {}
			for key, item in pairs( hd ) do
				if (string.Left( key, string.len( prefix ) ) == prefix) then
					local rest = string.sub( key, string.len( prefix ) + 1 )
					while ((string.len( rest ) > 0) && (string.Right( rest, 1 ) == "/")) do
						rest = string.sub( rest, 1, string.len( rest ) - 1 )
					end
					if ((rest != "") && (!string.find( rest, "/", 1, true ))) then
						local size = 0
						if (item.ItemType == "file") then size = string.len( item.ItemContent or "" ) end
						local info = {}
						info.Name = rest
						info.Path = ((norm == "") && rest) || (norm .. "/" .. rest)
						info.Type = item.ItemType
						info.Size = size
						info.Locked = (item.Locked == true)
						local idx = seen[ rest ]
						if (!idx) then
							seen[ rest ] = #out + 1
							table.insert( out, info )
						elseif (item.ItemType == "folder") then
							// If both "/name" and "/name/" exist, prefer the folder.
							out[ idx ] = info
						end
					end
				end
			end
			table.sort( out, function( a, b )
				if (a.Type != b.Type) then return (a.Type == "folder") end
				return (string.lower( a.Name ) < string.lower( b.Name ))
			end )
			return out
		end

		function ENT:GetItemInfo( path )
			local hd = FS_HardDrive( self )
			if (!hd) then return nil end
			local key = FS_FindKey( hd, path )
			if (!key) then return nil end
			local item = hd[ key ]
			if (!item) then return nil end
			local norm = FS_NormalizePath( key )
			local info = {}
			info.Name = FS_Basename( norm )
			info.Path = norm
			info.Type = item.ItemType
			info.Locked = (item.Locked == true)
			info.Size = 0
			if (item.ItemType == "file") then
				info.Size = string.len( item.ItemContent or "" )
				info.Content = item.ItemContent
			end
			return info
		end

		function ENT:RenameItem( oldpath, newpath )
			local hd = FS_HardDrive( self )
			if (!hd) then return false end
			local oldnorm = FS_NormalizePath( oldpath )
			local newnorm = FS_NormalizePath( newpath )
			if ((oldnorm == "") || (newnorm == "") || (oldnorm == newnorm)) then return false end
			local oldkey = FS_FindKey( hd, oldnorm )
			if (!oldkey) then return false end
			// Lookup is case-insensitive; use the stored spelling for every
			// descendant mutation as well or a case-variant path matches nothing.
			oldnorm = FS_NormalizePath( oldkey )
			if (self:IsPathLocked( oldnorm ) || self:IsPathLocked( newnorm )) then
				PCMod.Msg( "Tried to rename a locked path: " .. oldnorm .. " (" .. tostring( self:EntIndex() ) .. ")", true )
				return false
			end
			if (FS_FindKey( hd, newnorm )) then return false end
			local oldprefix = "/" .. oldnorm
			local newprefix = "/" .. newnorm
			// Never move a folder into itself.
			if (string.Left( newprefix, string.len( oldprefix ) + 1 ) == oldprefix .. "/") then return false end
			if (!self:MakeFolder( FS_ParentPath( newnorm ) )) then return false end
			local moves = {}
			for key, _ in pairs( hd ) do
				if ((key == oldprefix) || (string.Left( key, string.len( oldprefix ) + 1 ) == oldprefix .. "/")) then
					table.insert( moves, key )
				end
			end
			for _, key in ipairs( moves ) do
				local suffix = string.sub( key, string.len( oldprefix ) + 1 )
				if (hd[ newprefix .. suffix ]) then return false end
			end
			for _, key in ipairs( moves ) do
				local item = hd[ key ]
				local suffix = string.sub( key, string.len( oldprefix ) + 1 )
				local target = newprefix .. suffix
				hd[ target ] = item
				hd[ key ] = nil
				local rel = string.sub( target, 2 )
				while ((string.len( rel ) > 0) && (string.Right( rel, 1 ) == "/")) do
					rel = string.sub( rel, 1, string.len( rel ) - 1 )
				end
				item.ItemName = rel
			end
			return true
		end

		function ENT:CopyItem( oldpath, newpath )
			local hd = FS_HardDrive( self )
			if (!hd) then return false end
			local oldnorm = FS_NormalizePath( oldpath )
			local newnorm = FS_NormalizePath( newpath )
			if ((oldnorm == "") || (newnorm == "") || (oldnorm == newnorm)) then return false end
			local oldkey = FS_FindKey( hd, oldnorm )
			if (!oldkey) then return false end
			oldnorm = FS_NormalizePath( oldkey )
			if (self:IsPathLocked( oldnorm ) || self:IsPathLocked( newnorm )) then
				PCMod.Msg( "Tried to copy a locked path: " .. oldnorm .. " (" .. tostring( self:EntIndex() ) .. ")", true )
				return false
			end
			if (FS_FindKey( hd, newnorm )) then return false end
			local oldprefix = "/" .. oldnorm
			local newprefix = "/" .. newnorm
			if (string.Left( newprefix, string.len( oldprefix ) + 1 ) == oldprefix .. "/") then return false end
			if (!self:MakeFolder( FS_ParentPath( newnorm ) )) then return false end
			local copies = {}
			for key, item in pairs( hd ) do
				if ((key == oldprefix) || (string.Left( key, string.len( oldprefix ) + 1 ) == oldprefix .. "/")) then
					table.insert( copies, { key = key, item = item } )
				end
			end
			for _, v in ipairs( copies ) do
				local suffix = string.sub( v.key, string.len( oldprefix ) + 1 )
				if (hd[ newprefix .. suffix ]) then return false end
			end
			for _, v in ipairs( copies ) do
				local suffix = string.sub( v.key, string.len( oldprefix ) + 1 )
				local target = newprefix .. suffix
				local item = table.Copy( v.item )
				local rel = string.sub( target, 2 )
				while ((string.len( rel ) > 0) && (string.Right( rel, 1 ) == "/")) do
					rel = string.sub( rel, 1, string.len( rel ) - 1 )
				end
				item.ItemName = rel
				hd[ target ] = item
			end
			return true
		end

		function ENT:DeleteItem( path )
			local hd = FS_HardDrive( self )
			if (!hd) then return false end
			local norm = FS_NormalizePath( path )
			if (norm == "") then return false end
			local key = FS_FindKey( hd, norm )
			if (!key) then return false end
			norm = FS_NormalizePath( key )
			if (self:IsPathLocked( norm )) then
				PCMod.Msg( "Tried to delete a locked path: " .. norm .. " (" .. tostring( self:EntIndex() ) .. ")", true )
				return false
			end
			local prefix = "/" .. norm
			local dels = {}
			for key, item in pairs( hd ) do
				if ((key == prefix) || (string.Left( key, string.len( prefix ) + 1 ) == prefix .. "/")) then
					if (item.Locked) then return false end
					table.insert( dels, key )
				end
			end
			for _, key in ipairs( dels ) do
				hd[ key ] = nil
			end
			return true
		end

		function ENT:LinkFolder( dir )
			local hd = FS_HardDrive( self )
			if (!hd) then return end
			local norm = FS_NormalizePath( dir )
			if (norm == "") then return end
			local key = FS_FindKey( hd, norm )
			// Only an explicitly locked folder entry is protected. Creating a
			// folder *inside* a locked one (system/os/, system/data/) must keep
			// working: the entity/OS setup does exactly that during boot.
			if (key && hd[ key ].Locked) then
				PCMod.Msg( "Tried to overwrite locked folder: " .. norm .. " (" .. tostring( self:EntIndex() ) .. ")", true )
				return
			end
			if (key && (hd[ key ].ItemType != "folder")) then
				PCMod.Msg( "Tried to use file as a folder: " .. norm .. " (" .. tostring( self:EntIndex() ) .. ")", true )
				return
			end
			local tmp = {}
			tmp.ItemType = "folder"
			tmp.ItemName = norm
			tmp.ItemContent = ""
			tmp.Locked = false
			// Keep the historical key format (folders commonly end in "/"), so
			// existing save data and PCMod.Beam.FileList keep working.
			hd[ key or ( "/" .. norm .. "/" ) ] = tmp
		end
		
		function ENT:UnlinkItem( dir )
			local hd = FS_HardDrive( self )
			if (!hd) then return end
			local norm = FS_NormalizePath( dir )
			if (norm == "") then return end
			local key = FS_FindKey( hd, norm )
			if (!key) then return end
			// Removing a file that lives inside a locked folder is legitimate
			// (for example OS:RegisterRun deletes system/firstrun.sys). Only
			// the item itself being locked is refused here.
			if (hd[ key ].Locked) then
				PCMod.Msg( "Tried to unlink locked item: " .. norm .. " (" .. tostring( self:EntIndex() ) .. ")", true )
				return
			end
			hd[ key ] = nil
		end
		
		function ENT:LockItem( dir )
			local hd = FS_HardDrive( self )
			local key = FS_FindKey( hd, dir )
			if (key) then hd[ key ].Locked = true end
		end
		function ENT:UnLockItem( dir )
			local hd = FS_HardDrive( self )
			local key = FS_FindKey( hd, dir )
			if (key) then hd[ key ].Locked = false end
		end
		
		function ENT:WriteFile( filename, content )
			local hd = FS_HardDrive( self )
			if (!hd) then return false, "no_drive" end
			local norm = FS_NormalizePath( filename )
			if (norm == "") then return false, "invalid_path" end
			// Trusted entity/OS writes may still target locked folders during
			// setup and persistence. Untrusted program writes use
			// WriteFileChecked below, which enforces inherited locks too.
			local existing = FS_FindKey( hd, norm )
			if (existing && hd[ existing ].Locked) then
				PCMod.Msg( "Tried to overwrite locked file: " .. norm .. " (" .. tostring( self:EntIndex() ) .. ")", true )
				return false, "locked"
			end
			if (existing && (hd[ existing ].ItemType != "file")) then
				return false, "not_file"
			end
			local dir = FS_ParentPath( norm )
			local dirkey = FS_FindKey( hd, dir )
			if (dirkey && (hd[ dirkey ].ItemType == "file")) then
				PCMod.Msg( "Tried to use file as a folder: " .. dir .. " (" .. tostring( self:EntIndex() ) .. ")", true )
				return false, "parent_is_file"
			end
			// Preserve the stored key when an existing file was found through
			// case-insensitive lookup instead of creating a duplicate.
			local stored = existing and FS_NormalizePath( existing ) or norm
			local tmp = {}
			tmp.ItemType = "file"
			tmp.ItemName = stored
			tmp.ItemContent = content
			tmp.Locked = false
			hd[ existing or ( "/" .. norm ) ] = tmp
			return true
		end

		// Lock-aware write for player/program input. Entity and OS internals keep
		// using WriteFile because they legitimately populate system/data during
		// setup and save PC state while those folders are locked to users.
		function ENT:WriteFileChecked( filename, content )
			if (self:IsPathLocked( filename )) then
				PCMod.Msg( "Tried to write inside locked path: " .. tostring( filename ) .. " (" .. tostring( self:EntIndex() ) .. ")", true )
				return false, "locked"
			end
			return self:WriteFile( filename, content )
		end
		
		function ENT:ReadFile( filename )
			local hd = FS_HardDrive( self )
			local key = FS_FindKey( hd, filename )
			local item = key && hd[ key ]
			if (!item) then
				PCMod.Msg( "Tried to read unexistant file: " .. tostring( filename ) .. " (" .. tostring( self:EntIndex() ) .. ")", true )
				return ""
			end
			if (item.ItemType == "file") then return item.ItemContent end
			PCMod.Msg( "Tried to read a folder: " .. tostring( filename ) .. " (" .. tostring( self:EntIndex() ) .. ")", true )
			return ""
		end
		
		function ENT:FileFolderExist( filename )
			local hd = FS_HardDrive( self )
			if (FS_FindKey( hd, filename )) then return true end
			return false
		end

		function ENT:IsLocked( target )
			local hd = FS_HardDrive( self )
			local key = FS_FindKey( hd, target )
			if (!key) then return false end
			return hd[ key ].Locked
		end
		
